import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/game_session.dart';
import 'package:gomuku/services/storage_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });
  setUp(() async {
    await StorageService().savePreferredColor('black');
  });

  testWidgets('AI turn blocks input and paired undo restores the human turn',
      (tester) async {
    final s = GameSession(
        kind: GameKind.go,
        size: 9,
        ai: true,
        goMoveChooser: (g, d) async => const Position(row: 4, col: 4));
    s.play(0, 0);
    expect(s.thinking, true);
    s.play(0, 1);
    s.pass();
    expect(s.moves, 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.moves, 2);
    expect(s.current, Player.black);
    expect(s.thinking, false);
    s.undo();
    expect(s.moves, 0);
    expect(s.current, Player.black);
    s.dispose();
  });
  testWidgets('undo, reset and dispose discard late background results',
      (tester) async {
    final results = <Completer<Position?>>[];
    final s = GameSession(
        kind: GameKind.go,
        size: 9,
        ai: true,
        goMoveChooser: (g, d) {
          final next = Completer<Position?>();
          results.add(next);
          return next.future;
        });
    s.play(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    s.undo();
    results[0].complete(const Position(row: 4, col: 4));
    await tester.pump();
    expect(s.moves, 0);
    expect(s.thinking, false);
    s.play(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    s.reset();
    results[1].complete(const Position(row: 4, col: 4));
    await tester.pump();
    expect(s.moves, 0);
    expect(s.thinking, false);
    s.play(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    int notified = 0;
    s.addListener(() => notified++);
    s.dispose();
    results[2].complete(const Position(row: 4, col: 4));
    await tester.pump();
    expect(notified, 0);
  });
  testWidgets(
      'white preference gives AI the opening and keeps that opening on undo',
      (tester) async {
    await StorageService().savePreferredColor('white');
    final s = GameSession(
        kind: GameKind.go,
        size: 13,
        ai: true,
        goMoveChooser: (g, d) async => g.board[3][3] == CellState.empty
            ? const Position(row: 3, col: 3)
            : const Position(row: 9, col: 9));
    expect(s.thinking, true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.moves, 1);
    expect(s.current, Player.white);
    expect(s.canUndo, false);
    s.play(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.moves, 3);
    s.undo();
    expect(s.moves, 1);
    expect(s.current, Player.white);
    s.dispose();
  });
  testWidgets('double pass enters scoring and undo removes the pass pair',
      (tester) async {
    final s = GameSession(
        kind: GameKind.go,
        size: 9,
        ai: true,
        goMoveChooser: (g, d) async => null);
    s.pass();
    expect(s.moves, 1);
    expect(s.thinking, true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.scoring, true);
    expect(s.thinking, false);
    expect(s.moves, 2);
    s.finish();
    expect(s.over, true);
    s.undo();
    expect(s.over, false);
    expect(s.scoring, false);
    expect(s.moves, 0);
    s.dispose();
  });
  testWidgets('resume schedules AI when computer passed first', (tester) async {
    await StorageService().savePreferredColor('white');
    int calls = 0;
    final s = GameSession(
        kind: GameKind.go,
        size: 9,
        ai: true,
        goMoveChooser: (g, d) async =>
            calls++ == 0 ? null : const Position(row: 4, col: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.status, contains('电脑已停着'));
    s.pass();
    expect(s.scoring, true);
    s.resume();
    expect(s.thinking, true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.current, Player.white);
    expect(s.board[4][4], CellState.black);
    s.dispose();
  });
  testWidgets('failed computation can be retried without consuming a turn',
      (tester) async {
    int calls = 0;
    final s = GameSession(
        kind: GameKind.go,
        size: 9,
        ai: true,
        goMoveChooser: (g, d) async {
          if (calls++ == 0) throw StateError('test failure');
          return const Position(row: 4, col: 4);
        });
    s.play(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.moves, 1);
    expect(s.thinking, false);
    expect(s.aiError, isNotNull);
    s.play(0, 1);
    s.pass();
    expect(s.moves, 1);
    s.retryAi();
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.moves, 2);
    expect(s.aiError, isNull);
    s.dispose();
  });
}
