import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/services/game_engine.dart';

void main() {
  group('GameEngine 核心规则', () {
    test('初始为黑方先行', () {
      final e = GameEngine();
      expect(e.currentPlayer, Player.black);
      expect(e.gameState, GameState.playing);
    });

    test('落子后轮到对方', () {
      final e = GameEngine();
      expect(e.makeMove(7, 7), true);
      expect(e.currentPlayer, Player.white);
    });

    test('拒绝在已占用位置重复落子', () {
      final e = GameEngine();
      e.makeMove(7, 7);
      e.makeMove(7, 8);
      expect(e.makeMove(7, 7), false);
    });

    test('拒绝越界坐标', () {
      final e = GameEngine();
      expect(e.makeMove(-1, 0), false);
      expect(e.makeMove(0, 15), false);
    });

    test('横向五连判黑胜', () {
      final e = GameEngine();
      // 黑: (7,0)-(7,4) 五连；白方垫在下方一行
      final seq = [
        [7, 0],
        [8, 0],
        [7, 1],
        [8, 1],
        [7, 2],
        [8, 2],
        [7, 3],
        [8, 3],
        [7, 4],
        [8, 4],
      ];
      for (final m in seq) {
        e.makeMove(m[0], m[1]);
      }
      expect(e.gameState, GameState.blackWon);
    });

    test('斜向五连判白胜', () {
      final e = GameEngine();
      final seq = [
        [0, 0],
        [1, 1],
        [0, 5],
        [2, 2],
        [1, 6],
        [3, 3],
        [2, 7],
        [4, 4],
        [3, 8],
        [5, 5],
      ];
      for (final m in seq) {
        e.makeMove(m[0], m[1]);
      }
      expect(e.gameState, GameState.whiteWon);
    });

    test('游戏结束后不允许继续落子', () {
      final e = GameEngine();
      final seq = [
        [7, 0],
        [8, 0],
        [7, 1],
        [8, 1],
        [7, 2],
        [8, 2],
        [7, 3],
        [8, 3],
        [7, 4],
        [8, 4],
      ];
      for (final m in seq) {
        e.makeMove(m[0], m[1]);
      }
      expect(e.gameState, GameState.blackWon);
      expect(e.makeMove(0, 14), false);
    });

    test('悔棋恢复上一手并回退行棋方', () {
      final e = GameEngine();
      e.makeMove(7, 7); // 黑
      e.makeMove(7, 8); // 白
      expect(e.undoMove(), true);
      expect(e.currentPlayer, Player.white);
      expect(e.board[7][8], CellState.empty);
    });

    test('board getter 返回副本，外部修改不影响内部状态', () {
      final e = GameEngine();
      final copy = e.board;
      copy[0][0] = CellState.black;
      expect(e.board[0][0], CellState.empty);
    });

    test('reset 清空全部状态', () {
      final e = GameEngine();
      e.makeMove(7, 7);
      e.reset();
      expect(e.currentPlayer, Player.black);
      expect(e.moveHistory, isEmpty);
      expect(e.board[7][7], CellState.empty);
    });
  });
}
