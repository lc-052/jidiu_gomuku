import 'package:flutter/material.dart';
import '../models/game_state.dart';

/// Winning stones are derived from the final position, never from a reset board.
Set<Position> gomokuWinningLine(
    List<List<CellState>> board, Position? last, Player? winner) {
  if (last == null || winner == null) return {};
  final cell = winner == Player.black ? CellState.black : CellState.white;
  final n = board.length;
  bool matches(int r, int c) =>
      r >= 0 && r < n && c >= 0 && c < n && board[r][c] == cell;
  if (!matches(last.row, last.col)) return {};
  final result = <Position>{};
  for (final (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)]) {
    final line = <Position>[last];
    for (final sign in [-1, 1]) {
      var r = last.row + dr * sign, c = last.col + dc * sign;
      while (matches(r, c)) {
        line.add(Position(row: r, col: c));
        r += dr * sign;
        c += dc * sign;
      }
    }
    if (line.length >= 5) result.addAll(line);
  }
  return result;
}

String endReason(String? reason) => switch (reason) {
      'five-in-a-row' => '五子连线获胜，获胜棋子已在棋盘上圈出。',
      'resign' => '认输结束',
      'disconnected' => '对手断线，对局结束',
      'left' => '对手离开，对局结束',
      'score' => '终局面积计分（白贴 7.5 目）',
      'draw' => '棋盘已满，本局和棋',
      _ => '本局结束',
    };

class GameResultDetails extends StatelessWidget {
  final String title, reason;
  final int size, moves;
  final Position? last;
  final String? score, players;
  const GameResultDetails(
      {super.key,
      required this.title,
      required this.reason,
      required this.size,
      required this.moves,
      this.last,
      this.score,
      this.players});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(reason),
          if (players != null) ...[const SizedBox(height: 8), Text(players!)],
          const SizedBox(height: 8),
          Text('$size × $size · 共 $moves 手'),
          if (last != null)
            Text('最后落子：第 ${last!.row + 1} 行，第 ${last!.col + 1} 列'),
          if (score != null) ...[const SizedBox(height: 8), Text(score!)],
          const SizedBox(height: 12),
          const Text('最终棋盘已保留，关闭弹窗即可查看。'),
        ],
      );
}
