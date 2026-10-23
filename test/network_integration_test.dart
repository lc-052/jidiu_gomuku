import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/online_room_state.dart';
import 'package:gomuku/services/network_service.dart';

class _Client {
  final NetworkService network;
  final states = StreamController<OnlineRoomState>.broadcast(sync: true);
  final errors = StreamController<String>.broadcast(sync: true);
  _Client(String url, String name) : network = NetworkService(serverUrl: url) {
    network.setName(name);
    network.onState = states.add;
    network.onError = (e, _) => errors.add(e);
  }
  Future<OnlineRoomState> wait(bool Function(OnlineRoomState) predicate) {
    final latest = network.latestState;
    if (latest != null && predicate(latest)) return Future.value(latest);
    return states.stream
        .firstWhere(predicate)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    network.dispose();
    await states.close();
    await errors.close();
  }
}

void main() {
  late Process process;
  late String url;
  setUpAll(() async {
    process = await Process.start(
        Platform.environment['NODE_BINARY'] ?? 'node', ['index.js'],
        workingDirectory: 'server', environment: {'PORT': '0'});
    process.stderr
        .transform(utf8.decoder)
        .listen((line) {/* available on process failure */});
    final ready = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line.startsWith('READY '))
        .timeout(const Duration(seconds: 10));
    url = 'http://127.0.0.1:${ready.split(' ').last}';
  });
  tearDownAll(() async {
    process.kill();
    await process.exitCode;
  });
  Future<(_Client, _Client)> room(GameKind kind, {int? size}) async {
    final a = _Client(url, '黑棋测试'), b = _Client(url, '白棋测试');
    addTearDown(() async {
      await a.close();
      await b.close();
    });
    expect(await a.network.connect(), true);
    expect(await b.network.connect(), true);
    a.network.createRoom('房间', kind: kind, size: size);
    final state = await a.wait((s) => s.phase == 'waiting');
    b.network.expectedKind = kind;
    b.network.joinRoom(state.roomId);
    await a.wait((s) => s.players.length == 2);
    await b.wait((s) => s.players.length == 2);
    a.network.startGame();
    b.network.startGame();
    await a.wait((s) => s.phase == 'playing');
    await b.wait((s) => s.phase == 'playing');
    return (a, b);
  }

  Future<void> move(
      _Client mover, _Client a, _Client b, int row, int col) async {
    final count = a.network.latestState!.moves;
    mover.network.makeMove(row, col);
    await a.wait((s) => s.moves == count + 1);
    await b.wait((s) => s.moves == count + 1);
    expect(a.network.latestState!.board, b.network.latestState!.board);
  }

  test('register once, both clients agree on Gomoku turns, undo, chat and win',
      () async {
    final (a, b) = await room(GameKind.gomoku);
    // Reject an out-of-turn packet without changing either board.
    final error = b.errors.stream.first;
    b.network.makeMove(0, 0);
    expect(await error, contains('不是你的回合'));
    expect(a.network.latestState!.moves, 0);
    await move(a, a, b, 4, 0);
    await move(b, a, b, 5, 0);
    final ask = Completer<void>();
    b.network.onUndoAsk = (_) => ask.complete();
    a.network.requestUndo();
    await ask.future;
    b.network.replyUndo(true);
    await a.wait((s) => s.moves == 0);
    await b.wait((s) => s.moves == 0);
    final message = Completer<String>();
    b.network.onChatMessage = (m, _) => message.complete(m);
    expect(await a.network.sendChat('测试消息'), true);
    expect(await message.future, '测试消息');
    // Waiting longer than the previous 2s delayed registration must not orphan a room.
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    for (int c = 0; c < 5; c++) {
      await move(a, a, b, 4, c);
      if (c < 4) await move(b, a, b, 5, c);
    }
    final finalA = await a.wait((s) => s.finished),
        finalB = await b.wait((s) => s.finished);
    expect(finalA.winner, Player.black);
    expect(finalB.winner, Player.black);
    a.network.startGame();
    final reviewing =
        await a.wait((s) => s.finished && s.isReady(Player.black));
    await b.wait((s) => s.finished && s.isReady(Player.black));
    expect(reviewing.board, finalA.board);
    expect(reviewing.moves, 9);
    expect(reviewing.reason, 'five-in-a-row');
    b.network.startGame();
    await a.wait((s) => s.phase == 'playing' && s.moves == 0);
    expect(
        a.network.latestState!.board
            .every((r) => r.every((v) => v == CellState.empty)),
        true);
  });
  test(
      'Go captures, consented undo, double pass, shared dead groups, and two-party scoring',
      () async {
    final (a, b) = await room(GameKind.go);
    await move(a, a, b, 0, 1);
    await move(b, a, b, 0, 0);
    await move(a, a, b, 1, 0);
    expect(a.network.latestState!.captures['black'], 1);
    expect(b.network.latestState!.board[0][0], CellState.empty);
    final ask = Completer<void>();
    b.network.onUndoAsk = (_) => ask.complete();
    a.network.requestUndo();
    await ask.future;
    b.network.replyUndo(true);
    await a.wait((s) => s.moves == 2);
    await b.wait((s) => s.moves == 2);
    expect(a.network.latestState!.captures['black'], 0);
    expect(a.network.latestState!.board[0][0], CellState.white);
    await move(a, a, b, 1, 0);
    b.network.sendRoomAction('pass');
    await a.wait((s) => s.passes == 1);
    a.network.sendRoomAction('pass');
    await a.wait((s) => s.phase == 'scoring');
    await b.wait((s) => s.phase == 'scoring');
    a.network.sendRoomAction(
        'confirmScore', {'revision': a.network.latestState!.revision});
    await b.wait((s) => s.confirmations.length == 1);
    final staleRevision = b.network.latestState!.revision;
    b.network.sendRoomAction(
        'markDead', {'row': 0, 'col': 1, 'revision': staleRevision});
    await a.wait((s) => s.dead.isNotEmpty);
    await b.wait((s) => s.dead.isNotEmpty);
    expect(a.network.latestState!.confirmations, isEmpty);
    b.network.sendRoomAction('markDead',
        {'row': 1, 'col': 0, 'revision': b.network.latestState!.revision});
    await a.wait((s) => s.dead.length == 2);
    await b.wait((s) => s.dead.length == 2);
    final error = b.errors.stream.first;
    b.network.sendRoomAction('confirmScore', {'revision': staleRevision});
    expect(await error, contains('更新'));
    a.network.sendRoomAction(
        'confirmScore', {'revision': a.network.latestState!.revision});
    await b.wait((s) => s.confirmations.length == 1);
    b.network.sendRoomAction(
        'confirmScore', {'revision': b.network.latestState!.revision});
    final endA = await a.wait((s) => s.finished),
        endB = await b.wait((s) => s.finished);
    expect(endA.reason, 'score');
    expect(endA.score, endB.score);
    expect(endA.winner, Player.white);
  });
  for (final size in [13, 19]) {
    test('Go $size-line board is shared and disconnection closes the match',
        () async {
      final (a, b) = await room(GameKind.go, size: size);
      expect(a.network.latestState!.size, size);
      expect(b.network.latestState!.size, size);
      await move(a, a, b, size - 1, size - 1);
      final closed = Completer<String>();
      a.network.onRoomClosed = (m) => closed.complete(m);
      await b.network.disconnect();
      expect(await closed.future, contains('离开'));
      expect(a.network.latestState!.finished, true);
      expect(a.network.latestState!.winner, Player.black);
      expect(a.network.roomId, isNull);
    });
  }
}
