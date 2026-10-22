import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/services/go_engine.dart';

void main() {
  void move(GoEngine g, int r, int c) =>
      expect(g.makeMove(r, c), true, reason: g.error);
  test('capture, undo restores stones and capture count', () {
    final g = GoEngine();
    move(g, 0, 1);
    move(g, 0, 0);
    move(g, 1, 0);
    expect(g.board[0][0], CellState.empty);
    expect(g.blackCaptures, 1);
    expect(g.undoMove(), true);
    expect(g.board[0][0], CellState.white);
    expect(g.blackCaptures, 0);
    expect(g.currentPlayer, Player.black);
  });
  test('suicide is rejected without changing turn or history', () {
    final g = GoEngine();
    move(g, 0, 1);
    move(g, 8, 8);
    move(g, 1, 0);
    final count = g.moveCount;
    expect(g.makeMove(0, 0), false);
    expect(g.currentPlayer, Player.white);
    expect(g.moveCount, count);
    expect(g.error, contains('禁入点'));
  });
  test('ko recapture rejected and allowed after an exchange elsewhere', () {
    final g = GoEngine();
    move(g, 0, 2);
    move(g, 0, 1);
    move(g, 1, 1);
    move(g, 1, 0);
    move(g, 8, 8);
    move(g, 0, 3);
    move(g, 0, 0);
    expect(g.blackCaptures, 1);
    expect(g.makeMove(0, 1), false);
    expect(g.error, contains('劫争'));
    move(g, 8, 7);
    move(g, 7, 8);
    move(g, 0, 1);
    expect(g.whiteCaptures, 1);
  });
  test('two passes enter scoring; undo and resume restore play', () {
    final g = GoEngine();
    expect(g.pass(), true);
    expect(g.pass(), true);
    expect(g.scoring, true);
    expect(g.makeMove(4, 4), false);
    expect(g.undoMove(), true);
    expect(g.passes, 1);
    expect(g.scoring, false);
    g.pass();
    g.resume();
    expect(g.scoring, false);
    expect(g.passes, 0);
    move(g, 4, 4);
  });
  test('area score includes enclosed points, neutral regions, and komi', () {
    final g = GoEngine();
    move(g, 0, 1);
    move(g, 8, 8);
    move(g, 1, 0);
    expect(g.score().black, 3);
    expect(g.score().white, 8.5);
    g.pass();
    g.pass();
    g.finish();
    expect(g.gameState, GameState.whiteWon);
    expect(g.makeMove(4, 4), false);
  });
  test('dead stone group marking, resume, and reset', () {
    final g = GoEngine();
    move(g, 0, 0);
    move(g, 8, 8);
    move(g, 0, 1);
    g.pass();
    g.pass();
    g.toggleDead(0, 0);
    expect(g.dead.length, 2);
    g.toggleDead(0, 1);
    expect(g.dead, isEmpty);
    g.toggleDead(8, 8);
    expect(g.score().white, 7.5);
    g.resume();
    expect(g.dead, isEmpty);
    g.reset();
    expect(g.moveCount, 0);
    expect(g.currentPlayer, Player.black);
  });
  test('invalid moves, defensive board copy, sizes and resignation', () {
    for (final size in [9, 13, 19]) {
      final g = GoEngine(size: size);
      expect(g.makeMove(-1, 0), false);
      expect(g.makeMove(size, 0), false);
      final copy = g.board;
      copy[0][0] = CellState.black;
      expect(g.board[0][0], CellState.empty);
      g.resign();
      expect(g.gameState, GameState.whiteWon);
      expect(g.undoMove(), true);
      expect(g.gameState, GameState.playing);
    }
  });
}
