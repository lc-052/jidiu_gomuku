import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/online_room_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/screens/online_game_screen.dart';
import 'package:gomuku/services/network_service.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:gomuku/widgets/board_widget.dart';

Map<String, dynamic> position(
        {int size = 9, String phase = 'playing', int revision = 1}) =>
    {
      'roomId': '123456',
      'roomName': '测试棋室',
      'kind': 'go',
      'size': size,
      'phase': phase,
      'board': List.generate(size, (_) => List<String?>.filled(size, null)),
      'currentPlayer': 'black',
      'moveCount': 0,
      'passes': phase == 'scoring' ? 2 : 0,
      'lastMove': null,
      'dead': <dynamic>[],
      'players': [
        {'name': '黑棋玩家', 'color': 'black', 'ready': true},
        {'name': '白棋玩家', 'color': 'white', 'ready': true}
      ],
      'confirmations': <String>[],
      'captures': {'black': 0, 'white': 0},
      'score': phase == 'scoring' ? {'black': 0, 'white': 7.5} : null,
      'winnerColor': null,
      'reason': null,
      'revision': revision,
      'undoPending': false,
    };

class PreviewNetwork extends NetworkService {
  final actions = <String>[];
  PreviewNetwork(Map<String, dynamic> data) {
    latestState = OnlineRoomState.fromJson(data);
    roomId = latestState!.roomId;
  }
  @override
  bool get isConnected => true;
  @override
  void requestState() {}
  @override
  void leaveRoom() {
    resetRoomState();
  }

  @override
  void makeMove(int row, int col) {
    actions.add('move:$row:$col');
  }

  @override
  void sendRoomAction(String event, [Map<String, dynamic> data = const {}]) {
    actions.add('$event:${data['revision']}');
  }

  void emit(Map<String, dynamic> data) {
    latestState = OnlineRoomState.fromJson(data);
    onState?.call(latestState!);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });
  Widget wrap(PreviewNetwork n) => MaterialApp(
      theme: ThemePalette.all.first.materialTheme(Brightness.light),
      home: OnlineGameScreen(key: ValueKey(n), network: n));
  testWidgets(
      'server-authoritative boards, ready and scoring cards fit phone and desktop',
      (tester) async {
    for (final dimensions in [const Size(360, 800), const Size(1280, 900)]) {
      tester.view.physicalSize = dimensions;
      tester.view.devicePixelRatio = 1;
      for (final phase in ['waiting', 'playing', 'scoring', 'finished']) {
        final n = PreviewNetwork(position(size: 19, phase: phase));
        await tester.pumpWidget(wrap(n));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(BoardWidget), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('a tap waits for server confirmation instead of placing locally',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    final n = PreviewNetwork(position());
    await tester.pumpWidget(wrap(n));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(BoardWidget)));
    await tester.pump();
    expect(n.actions, ['move:4:4']);
    expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).board[4][4],
        CellState.empty);
    final next = position(revision: 2);
    next['board'][4][4] = 'black';
    next['moveCount'] = 1;
    next['currentPlayer'] = 'white';
    n.emit(next);
    await tester.pump();
    expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).board[4][4],
        CellState.black);
    await tester.tapAt(tester.getCenter(find.byType(BoardWidget)));
    await tester.pump();
    expect(n.actions.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
