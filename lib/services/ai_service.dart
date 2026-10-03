import 'dart:math';

import '../models/game_state.dart';
import 'game_engine.dart';

/// 候选点评估结果
/// [atk] AI 在此落子的进攻分；[dfn] 对手在此落子的威胁分（即 AI 的防守需求）
typedef _MoveScore = ({Position pos, int atk, int dfn});

/// AI 棋手服务 —— 棋型分级评分 + 显式堵截梯子 + 困难难度一层前瞻。
///
/// 旧实现存在“防守分双重取反”缺陷（防守评分实际评的是 AI 自己的进攻线），
/// 导致 AI 只顾进攻、从不拦截。本版防守逻辑设计：
///   1. 自己一手成五 → 直接取胜；
///   2. 对手一手成五 → 强制封堵；
///   3. 其余按“进攻分 + 防守分×权重”取最大。棋型量级严格分级
///      （五连 > 双四 > 冲四活三 > 双活三 > 活四 > 冲四 > 活三 > 眠三 > 活二 > 眠二），
///      对手的活三/活四等威胁点会获得巨大的防守分，AI 自然知难而退回防；
///   4. 困难难度再对头部候选做“对手最佳应招”的一层前瞻重评分。
class AIService {
  /// 棋盘尺寸
  final BoardSize boardSize;

  /// AI 难度等级
  final Difficulty difficulty;

  /// AI 执子颜色（展示用；实际以每次调用传入的颜色为准）
  final Player aiPlayer;

  /// 创建 AI 服务实例
  /// [boardSize] 棋盘大小
  /// [difficulty] AI 难度
  /// [aiPlayer] AI 执子颜色
  AIService({
    required this.boardSize,
    this.difficulty = Difficulty.medium,
    this.aiPlayer = Player.black,
  });

  /// 随机数生成器（简单难度故意留破绽用）
  final Random _random = Random();

  // ---------- 棋型分值分级（量级保证优先级不会被权重打穿） ----------
  static const int _five = 10000000; // 五连
  static const int _doubleFour = 4200000; // 双四（左右不能兼顾）
  static const int _fourThree = 3100000; // 冲四 + 活三（防不住）
  static const int _doubleOpenThree = 2000000; // 双活三
  static const int _openFour = 1000000; // 活四
  static const int _simpleFour = 100000; // 冲四 / 跳四
  static const int _openThree = 50000; // 活三
  static const int _sleepThree = 8000; // 眠三 / 跳三
  static const int _openTwo = 3000; // 活二
  static const int _sleepTwo = 200; // 眠二 / 跳二

  /// 五子棋的四个轴向
  static const List<List<int>> _directions = [
    [0, 1], // 横向
    [1, 0], // 纵向
    [1, 1], // 主对角 ↘
    [1, -1], // 副对角 ↙
  ];

  /// 获取 AI 最佳走棋位置。
  /// [engine] 游戏引擎实例（只读棋盘状态），[ai] AI 本次执子颜色。
  /// 无合法空位时返回 null。
  Position? getBestMove(GameEngine engine, Player ai) {
    final board = engine.board;
    final n = board.length;
    if (n <= 0) return null;

    final opp = ai.opponent();

    // 空盘 → 天元
    if (_isEmptyBoard(board)) {
      final c = n ~/ 2;
      return isValidPosition(board, c, c)
          ? Position(row: c, col: c)
          : _anyEmptyCell(board);
    }

    final candidates = _candidatePositions(board);
    if (candidates.isEmpty) return _anyEmptyCell(board);

    // 逐候选点计算攻防分
    final scored = <_MoveScore>[
      for (final p in candidates)
        (
          pos: p,
          atk: _placementScore(board, p.row, p.col, ai),
          dfn: _placementScore(board, p.row, p.col, opp),
        ),
    ];

    // 1. 自己一手成五 → 直接取胜
    for (final s in scored) {
      if (s.atk >= _five) return s.pos;
    }

    // 2. 对手一手成五 → 强制封堵（多口可堵时选自己进攻价值最高的点）
    final mustBlock = scored.where((s) => s.dfn >= _five).toList();
    if (mustBlock.isNotEmpty) {
      mustBlock.sort((a, b) => b.atk.compareTo(a.atk));
      return mustBlock.first.pos;
    }

    // 3. 攻防合一评分（防守权重按难度调节；量级分级本身已保证大部分威胁取舍）
    final defenseWeight = switch (difficulty) {
      Difficulty.easy => 0.55,
      Difficulty.medium => 1.0,
      Difficulty.hard => 1.05,
    };
    int valueOf(_MoveScore s) => s.atk + (s.dfn * defenseWeight).round();

    scored.sort((a, b) {
      final v = valueOf(b) - valueOf(a);
      if (v != 0) return v;
      final atk = b.atk - a.atk; // 对攻打平时优先自己进攻（对攻必胜先动手方）
      if (atk != 0) return atk;
      return _centerGain(b.pos, n) - _centerGain(a.pos, n); // 靠近中心者优先
    });

    // 4. 简单难度：20% 概率从前六名随机挑（故意留破绽）
    if (difficulty == Difficulty.easy && _random.nextInt(100) < 20) {
      final top = scored.take(6).toList();
      return top[_random.nextInt(top.length)].pos;
    }

    if (difficulty != Difficulty.hard) return scored.first.pos;

    // 5. 困难难度：头部 8 个候选加一层“对手最佳应招”前瞻。
    //    落子本身已达“必应”级别（活四+或封对方活四+）时无需前瞻——对手必须应。
    ({_MoveScore move, int total})? best;
    for (final m in scored.take(8)) {
      int total = valueOf(m);
      if (m.atk < _openFour && m.dfn < _openFour) {
        final after = _deepCopyBoard(board);
        after[m.pos.row][m.pos.col] = CellState.fromPlayer(ai);
        var oppReply = 0; // 对手反手的最大威胁
        var ownFollow = 0; // 自己这手的后续潜力
        for (final q in _candidatePositions(after)) {
          final t = _placementScore(after, q.row, q.col, opp);
          if (t > oppReply) oppReply = t;
          final f = _placementScore(after, q.row, q.col, ai);
          if (f > ownFollow) ownFollow = f;
        }
        total += (0.35 * ownFollow).round() - (0.75 * oppReply).round();
      }
      if (best == null || total > best.total) {
        best = (move: m, total: total);
      }
    }
    return best?.move.pos ?? scored.first.pos;
  }

  // ========== 棋型评估 ==========

  /// 在空位 (row,col) 落 [player] 子的“成形”评分：
  /// 四轴棋型分之和 + 复合杀形（双四/四三/双活三）取大。
  int _placementScore(
    List<List<CellState>> board,
    int row,
    int col,
    Player player,
  ) {
    if (!isValidPosition(board, row, col)) return 0;
    final stone = CellState.fromPlayer(player);

    var openFourAxis = 0,
        simpleFourAxis = 0,
        openThreeAxis = 0,
        sleepThreeAxis = 0,
        openTwoAxis = 0,
        sleepTwoAxis = 0;

    for (final d in _directions) {
      final s = _axisScore(board, row, col, d[0], d[1], stone);
      if (s >= _five) {
        return _five; // 任一轴成五即必胜，无需再看其余轴
      } else if (s >= _openFour) {
        openFourAxis++;
      } else if (s >= _simpleFour) {
        simpleFourAxis++;
      } else if (s >= _openThree) {
        openThreeAxis++;
      } else if (s >= _sleepThree) {
        sleepThreeAxis++;
      } else if (s >= _openTwo) {
        openTwoAxis++;
      } else if (s >= _sleepTwo) {
        sleepTwoAxis++;
      }
    }

    var total = openFourAxis * _openFour +
        simpleFourAxis * _simpleFour +
        openThreeAxis * _openThree +
        sleepThreeAxis * _sleepThree +
        openTwoAxis * _openTwo +
        sleepTwoAxis * _sleepTwo;

    // 复合杀形（取大值，防止单线求和被低估掩盖致命威胁）
    final forcing = openFourAxis + simpleFourAxis; // “成四”轴数
    if (forcing >= 2) total = max(total, _doubleFour);
    if (forcing >= 1 && openThreeAxis >= 1) total = max(total, _fourThree);
    if (openThreeAxis >= 2) total = max(total, _doubleOpenThree);

    return total;
  }

  /// 单轴棋型评分：以虚拟棋子为中心构建 9 格窗字符串，
  /// 其中 X=己方（含中心虚拟子）、O=对方、.=空、#=出界，
  /// 依此识别 连五 / 活四 / 冲四 / 跳四 / 活三 / 眠三 / 跳三 / 活二 / 眠二 / 跳二。
  int _axisScore(
    List<List<CellState>> board,
    int row,
    int col,
    int dr,
    int dc,
    CellState stone,
  ) {
    final n = board.length;
    final chars = List<String>.filled(9, '.');
    for (int i = -4; i <= 4; i++) {
      if (i == 0) {
        chars[i + 4] = 'X'; // 落子假设
        continue;
      }
      final r = row + dr * i;
      final c = col + dc * i;
      if (r < 0 || r >= n || c < 0 || c >= n) {
        chars[i + 4] = '#';
        continue;
      }
      final cell = board[r][c];
      chars[i + 4] =
          cell == stone ? 'X' : (cell == CellState.empty ? '.' : 'O');
    }
    final s = chars.join();

    // 含中心（下标 4）的最长连续 X 段及两端状态
    int lo = 4;
    while (lo > 0 && s[lo - 1] == 'X') {
      lo--;
    }
    int hi = 4;
    while (hi < 8 && s[hi + 1] == 'X') {
      hi++;
    }
    final run = hi - lo + 1;
    final left = lo > 0 ? s[lo - 1] : '#';
    final right = hi < 8 ? s[hi + 1] : '#';

    if (run >= 5) return _five;

    if (run == 4) {
      if (left == '.' && right == '.') return _openFour;
      if (left == '.' || right == '.') return _simpleFour;
      return 0; // 死四
    }

    // 断形检测：任一 5 格窗（必含中心）无干扰且 X 数尽量多
    int maxBroken = 0;
    for (int w = 0; w <= 4; w++) {
      final win = s.substring(w, w + 5);
      if (win.contains('O') || win.contains('#')) continue;
      final xCount = win.split('').where((ch) => ch == 'X').length;
      if (xCount > maxBroken) maxBroken = xCount;
    }
    if (maxBroken >= 4) return _simpleFour; // XXX.X / XX.XX / X.XXX 跳四

    if (run == 3) {
      if (left == '.' && right == '.') return _openThree;
      if (left == '.' || right == '.') return _sleepThree;
      return 0;
    }
    if (maxBroken >= 3) return _sleepThree; // X.XX / XX.X 跳三

    if (run == 2) {
      if (left == '.' && right == '.') return _openTwo;
      if (left == '.' || right == '.') return _sleepTwo;
      return 0;
    }
    if (maxBroken >= 2) return _sleepTwo; // X.X 跳二

    return 0;
  }

  // ========== 辅助方法 ==========

  /// 生成候选点：与任意已有棋子八邻相邻的空位
  List<Position> _candidatePositions(List<List<CellState>> board) {
    final n = board.length;
    final seen = <String>{};
    final result = <Position>[];
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (board[r][c] == CellState.empty) continue;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final nr = r + dr;
            final nc = c + dc;
            if (isValidPosition(board, nr, nc)) {
              final key = '$nr,$nc';
              if (seen.add(key)) result.add(Position(row: nr, col: nc));
            }
          }
        }
      }
    }
    return result;
  }

  /// 判断棋盘是否为空
  bool _isEmptyBoard(List<List<CellState>> board) {
    for (final row in board) {
      for (final cell in row) {
        if (cell != CellState.empty) return false;
      }
    }
    return true;
  }

  /// 判断指定坐标是否在棋盘范围内且为空
  bool isValidPosition(List<List<CellState>> board, int row, int col) {
    if (row < 0 || row >= board.length || col < 0 || col >= board[row].length) {
      return false;
    }
    return board[row][col] == CellState.empty;
  }

  /// 越靠中心值越大（评分并列时的择点偏置）
  int _centerGain(Position p, int n) =>
      (n - 1) - ((p.row - n ~/ 2).abs() + (p.col - n ~/ 2).abs());

  /// 深拷贝棋盘
  List<List<CellState>> _deepCopyBoard(List<List<CellState>> source) =>
      source.map((row) => List<CellState>.from(row)).toList();

  /// 在任意空位中随机选一个（兜底）
  Position? _anyEmptyCell(List<List<CellState>> board) {
    final emptyCells = <Position>[];
    for (int r = 0; r < board.length; r++) {
      for (int c = 0; c < board[r].length; c++) {
        if (board[r][c] == CellState.empty) {
          emptyCells.add(Position(row: r, col: c));
        }
      }
    }
    return emptyCells.isNotEmpty
        ? emptyCells[_random.nextInt(emptyCells.length)]
        : null;
  }
}
