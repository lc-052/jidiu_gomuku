import '../models/game_state.dart';

/// 游戏引擎 - 五子棋核心逻辑，完全无 UI 依赖，可独立测试
class GameEngine {
  /// 棋盘尺寸
  final BoardSize boardSize;

  /// 内部棋盘数据 [row][col]（供同目录的 AI/网络服务读取）
  late List<List<CellState>> _boardData;

  /// 当前落子方
  Player _currentPlayer;

  /// 走棋历史记录
  final List<MoveRecord> _moveHistory;

  /// 当前游戏状态
  GameState _gameState;

  /// 已执子的数量（用于判断悔棋次数上限）
  int _playedCount;

  // ---------- 构造函数 ----------

  /// 创建游戏引擎实例
  /// [boardSize] 棋盘大小，默认为标准15x15
  GameEngine({this.boardSize = BoardSize.standard})
      : _currentPlayer = Player.black,
        _moveHistory = [],
        _gameState = GameState.playing,
        _playedCount = 0 {
    _initBoard();
  }

  /// 初始化空棋盘
  void _initBoard() {
    _boardData = List.generate(
      boardSize.size,
      (_) => List.filled(boardSize.size, CellState.empty),
    );
    _playedCount = 0;
  }

  // ---------- Getter ----------

  /// 获取完整棋盘副本（二维数组深拷贝）
  List<List<CellState>> get board => _getBoardCopy();

  /// 当前落子方
  Player get currentPlayer => _currentPlayer;

  /// 走棋历史记录
  List<MoveRecord> get moveHistory => List.unmodifiable(_moveHistory);

  /// 当前游戏状态
  GameState get gameState => _gameState;

  /// 棋盘尺寸
  int get size => boardSize.size;

  /// 已落子总数
  int get playedCount => _playedCount;

  // ---------- 核心方法 ----------

  /// 尝试在指定位置落子
  /// 返回是否成功：合法位置且为空则成功
  bool makeMove(int row, int col) {
    // 游戏已结束，不允许继续落子
    if (_gameState != GameState.playing) return false;

    // 检查坐标合法性
    if (!isValidMove(row, col)) return false;

    // 放置棋子
    _boardData[row][col] = CellState.fromPlayer(_currentPlayer);

    // 记录走棋
    final record = MoveRecord(
      position: Position(row: row, col: col),
      player: _currentPlayer,
    );
    _moveHistory.add(record);
    _playedCount++;

    // 检查是否获胜
    if (checkWin(row, col)) {
      _gameState = _currentPlayer == Player.black
          ? GameState.blackWon
          : GameState.whiteWon;
      return true;
    }

    // 检查是否平局
    if (isDraw()) {
      _gameState = GameState.draw;
      return true;
    }

    // 切换玩家
    _currentPlayer = _currentPlayer.opponent();
    return true;
  }

  /// 悔棋：撤销上一步走棋
  /// 返回是否成功：有记录可撤销则成功
  bool undoMove() {
    if (_moveHistory.isEmpty) return false;

    // 如果游戏已结束，恢复到进行中状态
    if (_gameState != GameState.playing) {
      _gameState = GameState.playing;
    }

    // 取出最后一步
    final lastMove = _moveHistory.removeLast();

    // 恢复空格
    _boardData[lastMove.position.row][lastMove.position.col] = CellState.empty;

    // 回退玩家
    _currentPlayer = lastMove.player;
    _playedCount--;

    return true;
  }

  /// 检查指定位置是否形成五连珠
  /// [row] 行坐标, [col] 列坐标
  /// 返回是否获胜
  bool checkWin(int row, int col) {
    final stone = _boardData[row][col];
    if (stone == CellState.empty) return false;

    // 四个方向：水平、垂直、两条对角线
    final directions = [
      _Direction.horizontal,
      _Direction.vertical,
      _Direction.diagonalDownRight,
      _Direction.diagonalDownLeft,
    ];

    for (final dir in directions) {
      if (_checkDirection(row, col, dir, stone)) {
        return true;
      }
    }
    return false;
  }

  /// 检查棋盘是否已满（平局判断）
  bool isDraw() => _playedCount >= boardSize.size * boardSize.size;

  /// 检查是否为合法落子位置
  bool isValidMove(int row, int col) {
    // 范围检查
    if (row < 0 || row >= boardSize.size) return false;
    if (col < 0 || col >= boardSize.size) return false;
    // 位置必须为空
    return _boardData[row][col] == CellState.empty;
  }

  /// 重置棋盘到初始状态
  void reset() {
    _initBoard();
    _currentPlayer = Player.black;
    _moveHistory.clear();
    _gameState = GameState.playing;
  }

  /// 获取棋盘的深拷贝
  List<List<CellState>> getBoardCopy() => _getBoardCopy();

  /// 获取已悔棋的次数（即历史中已被撤销的步数与当前保留步数的差值，简化为历史长度）
  int getCapturedMovesCount() => _moveHistory.length;

  // ---------- 私有辅助方法 ----------

  /// 获取棋盘二维数组深拷贝
  List<List<CellState>> _getBoardCopy() {
    return _boardData.map((row) => List<CellState>.from(row)).toList();
  }

  /// 从指定位置沿某一方向扫描，判断是否有连续五子
  /// [row] 起始行, [col] 起始列, [direction] 扫描方向, [stone] 己方棋子
  bool _checkDirection(
      int row, int col, _Direction direction, CellState stone) {
    final dr = direction.rowDelta;
    final dc = direction.colDelta;

    // 向前计数（包含自身）
    int forward = 1;
    int r = row + dr;
    int c = col + dc;
    while (r >= 0 && r < boardSize.size && c >= 0 && c < boardSize.size) {
      if (_boardData[r][c] != stone) break;
      forward++;
      r += dr;
      c += dc;
    }

    // 向后计数（不包含自身）
    int backward = 1;
    r = row - dr;
    c = col - dc;
    while (r >= 0 && r < boardSize.size && c >= 0 && c < boardSize.size) {
      if (_boardData[r][c] != stone) break;
      backward++;
      r -= dr;
      c -= dc;
    }

    return (forward + backward - 1) >= 5;
  }
}

/// 四个扫描方向的枚举
enum _Direction {
  horizontal(0, 1), // 水平向右
  vertical(1, 0), // 垂直向下
  diagonalDownRight(1, 1), // 右下对角线
  diagonalDownLeft(1, -1); // 左下对角线

  final int rowDelta;
  final int colDelta;

  const _Direction(this.rowDelta, this.colDelta);
}
