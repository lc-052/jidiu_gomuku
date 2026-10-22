import 'package:flutter/material.dart';
import '../models/game_session.dart';
import '../models/game_state.dart';
import 'section_card.dart';

class PlayerStatusCard extends StatelessWidget {
  final GameSession session;
  const PlayerStatusCard({super.key, required this.session});
  @override
  Widget build(BuildContext context) => SectionCard(
      title: session.status,
      trailing: session.thinking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      child: Row(children: [
        for (final p in Player.values)
          Expanded(
              child: Row(children: [
            Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.color,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant))),
            const SizedBox(width: 8),
            Flexible(
                child: Text(session.isGo
                    ? '${p.cn}${session.ai ? (p == session.human ? " · 你" : " · 电脑") : ""} · 提 ${p == Player.black ? session.go.blackCaptures : session.go.whiteCaptures} 子'
                    : '${p.cn}${session.ai ? (p == session.human ? " · 你" : " · 电脑") : ""}')),
          ])),
      ]));
}

class GameActionsCard extends StatelessWidget {
  final GameSession session;
  final VoidCallback onRestart, onResign;
  const GameActionsCard(
      {super.key,
      required this.session,
      required this.onRestart,
      required this.onResign});
  @override
  Widget build(BuildContext context) => SectionCard(
      title: '对局操作',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: session.canUndo ? session.undo : null,
            icon: const Icon(Icons.undo_rounded),
            label: const Text('悔棋')),
        if (session.isGo && !session.scoring && !session.over)
          FilledButton.tonalIcon(
              onPressed: session.thinking ||
                      (session.ai && session.current != session.human)
                  ? null
                  : session.pass,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('停一手')),
        if (!session.over)
          TextButton.icon(
              onPressed: session.thinking ? null : onResign,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('认输')),
        if (session.aiError != null)
          FilledButton.tonalIcon(
              onPressed: session.retryAi,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试电脑落子')),
        TextButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新开始')),
      ]));
}

class GoScoringCard extends StatelessWidget {
  final GameSession session;
  const GoScoringCard({super.key, required this.session});
  @override
  Widget build(BuildContext context) {
    final score = session.go.score();
    return SectionCard(
        title: session.over ? '本局结算' : '终局核对',
        subtitle: session.over
            ? '面积计分结果'
            : session.ai
                ? '点击棋子标记或取消整块死子（叉号），核对后结算。未自动判定死活，也可继续下棋。'
                : '点击棋子标记或取消整块死子（叉号）。双方确认后结算；有争议可继续下棋。',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '黑 ${score.black.toStringAsFixed(1)} · 白 ${score.white.toStringAsFixed(1)}（含贴 7.5）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (session.over)
            Text(score.result)
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                  onPressed: session.finish,
                  child: Text(session.ai ? '确认计分，结算' : '双方确认，结算')),
              OutlinedButton(
                  onPressed: session.resume, child: const Text('继续下棋')),
            ]),
        ]));
  }
}

class MoveSummaryCard extends StatelessWidget {
  final GameSession session;
  const MoveSummaryCard({super.key, required this.session});
  @override
  Widget build(BuildContext context) => SectionCard(
      title: '棋局记录',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${session.size} × ${session.size} 棋盘 · 已行 ${session.moves} 手'),
        const SizedBox(height: 8),
        Text(session.last == null
            ? (session.moves == 0 ? '等待第一手落子' : '上一手：停着')
            : '最近落子：第 ${session.last!.row + 1} 行，第 ${session.last!.col + 1} 列'),
        if (session.isGo) ...[
          const SizedBox(height: 8),
          Text('连续停着：${session.go.passes} / 2')
        ],
      ]));
}
