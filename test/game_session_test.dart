import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/game_session.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/services/storage_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });
  testWidgets(
      'AI honors white preference, blocks extra input, and cancels pending turns',
      (tester) async {
    await StorageService().savePreferredColor('white');
    final session = GameSession(kind: GameKind.gomoku, size: 9, ai: true);
    expect(session.thinking, true);
    session.play(0, 0);
    expect(session.moves, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.moves, 1);
    expect(session.current, Player.white);
    session.play(0, 0);
    expect(session.thinking, true);
    session.undo();
    expect(session.moves, 1);
    expect(session.current, Player.white);
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.moves, 1);
    session.reset();
    expect(session.thinking, true);
    session.dispose();
    await tester.pump(const Duration(seconds: 1));
    await StorageService().savePreferredColor('black');
  });
  test('Go session can score, resume, finish, and undo an ended game', () {
    final s = GameSession(kind: GameKind.go, size: 9);
    s.play(0, 0);
    s.play(8, 8);
    s.pass();
    s.pass();
    expect(s.scoring, true);
    s.play(8, 8);
    expect(s.go.dead.length, 1);
    s.resume();
    expect(s.go.dead, isEmpty);
    s.pass();
    s.pass();
    s.finish();
    expect(s.over, true);
    s.undo();
    expect(s.over, false);
    expect(s.scoring, false);
    s.dispose();
  });
}
