import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/services/go_engine.dart';
import 'package:gomuku/services/go_ai_service.dart';

void main() {
  void move(GoEngine g, int r, int c) =>
      expect(g.makeMove(r, c), true, reason: g.error);
  for (final difficulty in Difficulty.values) {
    test(
        '${difficulty.displayName}: captures a stone in atari without mutating source',
        () {
      final g = GoEngine();
      move(g, 0, 1);
      move(g, 0, 0);
      final board = g.board, history = g.moveCount;
      final ai = GoAIService(difficulty: difficulty, random: Random(7));
      final chosen = ai.getBestMove(g);
      expect(chosen, const Position(row: 1, col: 0));
      expect(g.board, board);
      expect(g.moveCount, history);
      expect(g.currentPlayer, Player.black);
      expect(g.blackCaptures, 0);
      expect(g.makeMove(chosen!.row, chosen.col), true);
      expect(g.blackCaptures, 1);
    });
    test('${difficulty.displayName}: saves a threatened group', () {
      final g = GoEngine();
      move(g, 0, 1);
      move(g, 0, 0);
      move(g, 8, 8);
      final chosen =
          GoAIService(difficulty: difficulty, random: Random(7)).getBestMove(g);
      expect(chosen, const Position(row: 1, col: 0));
    });
    test('${difficulty.displayName}: respects ko and leaves own eyes intact',
        () {
      final g = GoEngine();
      for (final p in [
        [0, 2],
        [0, 1],
        [1, 1],
        [1, 0],
        [8, 8],
        [0, 3],
        [0, 0]
      ]) {
        move(g, p[0], p[1]);
      }
      final chosen =
          GoAIService(difficulty: difficulty, random: Random(7)).getBestMove(g);
      expect(chosen, isNotNull);
      expect(chosen, isNot(const Position(row: 0, col: 1)));
      expect(g.makeMove(chosen!.row, chosen.col), true);
      final eye = GoEngine();
      for (final p in [
        [0, 1],
        [8, 8],
        [1, 0],
        [8, 7],
        [1, 1],
        [7, 8]
      ]) {
        move(eye, p[0], p[1]);
      }
      final selected = GoAIService(difficulty: difficulty, random: Random(7))
          .getBestMove(eye);
      expect(selected, isNot(const Position(row: 0, col: 0)));
    });
    test('${difficulty.displayName}: passes when only settled eyes remain', () {
      final g = GoEngine();
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
          if ((r == 0 && c == 0) || (r == 8 && c == 8)) continue;
          move(g, r, c);
          expect(g.pass(), true);
        }
      }
      expect(g.currentPlayer, Player.black);
      expect(GoAIService(difficulty: difficulty).getBestMove(g), isNull);
      expect(g.passes, 1);
    });
  }
  for (final size in [9, 13, 19]) {
    test(
        'hard opens legally on $size lines without answering an early pass with a pass',
        () {
      final g = GoEngine(size: size);
      g.pass();
      final watch = Stopwatch()..start();
      final chosen = GoAIService(difficulty: Difficulty.hard).getBestMove(g);
      watch.stop();
      // Printed for profiling, not a hardware-dependent timing assertion.
      // ignore: avoid_print
      print('Go hard $size: ${watch.elapsedMilliseconds}ms');
      expect(chosen, isNotNull);
      expect(g.makeMove(chosen!.row, chosen.col), true);
    });
  }
  test('background calculation transfers the engine safely', () async {
    final g = GoEngine();
    move(g, 0, 1);
    move(g, 0, 0);
    final chosen = await GoAIService.chooseMove(g, Difficulty.medium);
    expect(chosen, const Position(row: 1, col: 0));
    expect(g.moveCount, 2);
  });
  test('medium self-play reaches scoring with only legal moves', () {
    final g = GoEngine();
    final ai = GoAIService();
    for (int turn = 0; turn < 500 && !g.scoring; turn++) {
      final move = ai.getBestMove(g);
      if (move == null) {
        expect(g.pass(), true);
      } else {
        expect(g.makeMove(move.row, move.col), true);
      }
    }
    expect(g.scoring, true);
  });
  test('fork retains superko history and has independent board and passes', () {
    final g = GoEngine();
    for (final p in [
      [0, 2],
      [0, 1],
      [1, 1],
      [1, 0],
      [8, 8],
      [0, 3],
      [0, 0]
    ]) {
      move(g, p[0], p[1]);
    }
    final fork = g.fork();
    expect(fork.makeMove(0, 1), false);
    expect(fork.error, contains('劫争'));
    fork.pass();
    expect(g.passes, 0);
    expect(g.error, isNull);
  });
}
