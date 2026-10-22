import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/services/network_service.dart';
import 'package:gomuku/models/online_room_state.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/models/game_state.dart';

void main() {
  test('browser connects and synchronizes a real Go room over WebSocket',
      () async {
    const url = String.fromEnvironment('BROWSER_TEST_SERVER');
    expect(url, isNotEmpty);
    final a = NetworkService(serverUrl: url),
        b = NetworkService(serverUrl: url);
    final statesA = StreamController<OnlineRoomState>.broadcast(),
        statesB = StreamController<OnlineRoomState>.broadcast();
    a.onState = statesA.add;
    b.onState = statesB.add;
    Future<OnlineRoomState> wait(
        NetworkService n,
        StreamController<OnlineRoomState> stream,
        bool Function(OnlineRoomState) match) {
      final current = n.latestState;
      if (current != null && match(current)) return Future.value(current);
      return stream.stream
          .firstWhere(match)
          .timeout(const Duration(seconds: 8));
    }

    try {
      expect(await a.connect(), true);
      expect(await b.connect(), true);
      a.createRoom('浏览器联机测试', kind: GameKind.go);
      final room = await wait(a, statesA, (s) => s.phase == 'waiting');
      b.joinRoom(room.roomId);
      await wait(b, statesB, (s) => s.players.length == 2);
      a.startGame();
      b.startGame();
      await wait(a, statesA, (s) => s.phase == 'playing');
      await wait(b, statesB, (s) => s.phase == 'playing');
      a.makeMove(0, 1);
      await wait(b, statesB, (s) => s.moves == 1);
      b.makeMove(0, 0);
      await wait(a, statesA, (s) => s.moves == 2);
      a.makeMove(1, 0);
      await wait(b, statesB, (s) => s.moves == 3);
      expect(b.latestState!.board[0][0], CellState.empty);
      expect(b.latestState!.captures['black'], 1);
    } finally {
      a.dispose();
      b.dispose();
      await statesA.close();
      await statesB.close();
    }
  });
}
