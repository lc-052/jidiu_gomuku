import 'game_kind.dart';
import 'game_state.dart';

/// Complete server-authoritative room snapshot (protocol 2).
class OnlineRoomState {
  final String roomId, roomName, phase;
  final GameKind kind;
  final int size, revision, moves, passes;
  final List<List<CellState>> board;
  final Player current;
  final Player? winner;
  final String? reason;
  final Position? last;
  final Set<Position> dead;
  final List<Map<String, dynamic>> players;
  final Set<String> confirmations;
  final Map<String, dynamic> captures;
  final Map<String, dynamic>? score;
  final bool undoPending;
  OnlineRoomState._(Map<String, dynamic> data)
      : roomId = data['roomId'] as String,
        roomName = data['roomName'] as String,
        phase = data['phase'] as String,
        kind = data['kind'] == 'go' ? GameKind.go : GameKind.gomoku,
        size = data['size'] as int,
        revision = data['revision'] as int,
        moves = data['moveCount'] as int,
        passes = data['passes'] as int,
        current =
            data['currentPlayer'] == 'white' ? Player.white : Player.black,
        winner = data['winnerColor'] == null
            ? null
            : data['winnerColor'] == 'white'
                ? Player.white
                : Player.black,
        reason = data['reason'] as String?,
        last = data['lastMove'] == null
            ? null
            : Position(
                row: data['lastMove']['row'] as int,
                col: data['lastMove']['col'] as int),
        board = (data['board'] as List)
            .map((r) => (r as List)
                .map((v) => v == 'black'
                    ? CellState.black
                    : v == 'white'
                        ? CellState.white
                        : CellState.empty)
                .toList())
            .toList(),
        dead = (data['dead'] as List)
            .map((p) => Position(row: p['row'] as int, col: p['col'] as int))
            .toSet(),
        players = (data['players'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList(),
        confirmations = Set<String>.from(data['confirmations'] as List),
        captures = Map<String, dynamic>.from(data['captures'] as Map),
        score = data['score'] == null
            ? null
            : Map<String, dynamic>.from(data['score'] as Map),
        undoPending = data['undoPending'] == true;
  factory OnlineRoomState.fromJson(Map<String, dynamic> data) {
    final state = OnlineRoomState._(data);
    if (![9, 13, 15, 19].contains(state.size) ||
        state.board.length != state.size ||
        state.board.any((r) => r.length != state.size)) {
      throw const FormatException('无效的服务器棋盘');
    }
    return state;
  }
  String colorKey(Player color) => color == Player.black ? 'black' : 'white';
  bool isReady(Player color) =>
      players.any((p) => p['color'] == colorKey(color) && p['ready'] == true);
  bool get finished => phase == 'finished';
  String get status => phase == 'waiting'
      ? '等待双方准备'
      : phase == 'scoring'
          ? '核对死子与计分'
          : finished
              ? (winner == null ? '本局和棋' : '${winner!.cn}获胜')
              : '轮到${current.cn}落子';
}
