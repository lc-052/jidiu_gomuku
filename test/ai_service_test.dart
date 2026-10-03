import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/services/ai_service.dart';
import 'package:gomuku/services/game_engine.dart';

/// 构造一个「黑方四连」（黑子 (7,3)-(7,6)，两端 (7,2)/(7,7) 均空），白方即将行棋的局面。
/// 双方各走 4 手，交替合法，黑方四连成形后轮到白方。
GameEngine buildBlackFourEngine() {
  final e = GameEngine(boardSize: BoardSize.standard);
  e.makeMove(7, 3); // 黑
  e.makeMove(0, 0); // 白
  e.makeMove(7, 4); // 黑
  e.makeMove(0, 1); // 白
  e.makeMove(7, 5); // 黑
  e.makeMove(0, 2); // 白
  e.makeMove(7, 6); // 黑 → 黑四连，白必须封堵
  return e;
}

/// 构造一个「白方四连」（白子 (7,3)-(7,6)），轮黑走，AI 执白时一手即可成五。
GameEngine buildWhiteFourEngine() {
  final e = GameEngine(boardSize: BoardSize.standard);
  e.makeMove(0, 0); // 黑
  e.makeMove(7, 3); // 白
  e.makeMove(0, 1); // 黑
  e.makeMove(7, 4); // 白
  e.makeMove(5, 0); // 黑
  e.makeMove(7, 5); // 白
  e.makeMove(5, 1); // 黑
  e.makeMove(7, 6); // 白 → 白四连
  return e;
}

/// 构造一个「黑方活三」（黑子 (7,5)-(7,7)，两端 (7,4)/(7,8) 均空），轮白行棋。
GameEngine buildBlackOpenThreeEngine() {
  final e = GameEngine(boardSize: BoardSize.standard);
  e.makeMove(7, 5); // 黑
  e.makeMove(0, 0); // 白
  e.makeMove(7, 6); // 黑
  e.makeMove(0, 1); // 白
  e.makeMove(7, 7); // 黑 → 黑活三，白应封堵
  return e;
}

void main() {
  group('AI 堵截能力回归测试', () {
    test('空棋盘首手落天元', () {
      final e = GameEngine(boardSize: BoardSize.standard);
      final ai = AIService(boardSize: BoardSize.standard);
      final mv = ai.getBestMove(e, Player.black)!;
      expect(mv, const Position(row: 7, col: 7));
    });

    for (final d in Difficulty.values) {
      test('对手四连成五时必封堵（${d.displayName}）', () {
        final e = buildBlackFourEngine();
        final ai = AIService(
          boardSize: BoardSize.standard,
          difficulty: d,
          aiPlayer: Player.white,
        );
        final mv = ai.getBestMove(e, Player.white)!;
        // 只有 (7,2) 和 (7,7) 两个堵口
        expect(
          [const Position(row: 7, col: 2), const Position(row: 7, col: 7)],
          contains(mv),
          reason: '${d.displayName} 难度下 AI 没有封堵对手四连，落点 $mv',
        );
      });
    }

    test('自己能一手成五时优先取胜', () {
      final e = buildWhiteFourEngine();
      final ai = AIService(
        boardSize: BoardSize.standard,
        difficulty: Difficulty.hard,
        aiPlayer: Player.white,
      );
      final mv = ai.getBestMove(e, Player.white)!;
      expect(
        [const Position(row: 7, col: 2), const Position(row: 7, col: 7)],
        contains(mv),
      );
      // 落子后必须真的成五
      final after = List<List<CellState>>.from(
        e.board.map((r) => List<CellState>.from(r)),
      );
      after[mv.row][mv.col] = CellState.white;
      var run = 0, best = 0;
      for (int c = 0; c < 15; c++) {
        if (after[mv.row][c] == CellState.white) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
      }
      expect(best, greaterThanOrEqualTo(5), reason: 'AI 自称能赢却没成五');
    });

    for (final d in [Difficulty.medium, Difficulty.hard]) {
      test('对手活三时封堵两端之一（${d.displayName}）', () {
        final e = buildBlackOpenThreeEngine();
        final ai = AIService(
          boardSize: BoardSize.standard,
          difficulty: d,
          aiPlayer: Player.white,
        );
        final mv = ai.getBestMove(e, Player.white)!;
        expect(
          [const Position(row: 7, col: 4), const Position(row: 7, col: 8)],
          contains(mv),
          reason: '${d.displayName} 难度下 AI 没有拦截活三，落点 $mv',
        );
      });
    }

    test('返回的点一定是合法空位', () {
      final e = buildBlackFourEngine();
      for (final d in Difficulty.values) {
        final ai = AIService(
          boardSize: BoardSize.standard,
          difficulty: d,
          aiPlayer: Player.white,
        );
        final mv = ai.getBestMove(e, Player.white)!;
        expect(e.board[mv.row][mv.col], CellState.empty,
            reason: '${d.displayName} 返回了非空位 $mv');
      }
    });
  });
}
