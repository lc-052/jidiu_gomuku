import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/game_kind.dart';
import '../widgets/section_card.dart';
import '../widgets/theme_settings_card.dart';
import '../widgets/adaptive_card_pair.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  GameKind _kind = GameKind.gomoku;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('寄丢棋室'), actions: [
          IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/settings')),
          const SizedBox(width: 12),
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  AdaptiveCardPair(
                      firstFlex: 3,
                      secondFlex: 2,
                      first: const _WelcomeCard(),
                      second: SectionCard(
                          title: '今天，下一局什么棋？',
                          child: Wrap(spacing: 12, runSpacing: 8, children: [
                            for (final kind in GameKind.values)
                              ChoiceChip(
                                  label: Text(kind.label),
                                  avatar: Icon(kind == GameKind.go
                                      ? Icons.blur_circular_rounded
                                      : Icons.grid_4x4_rounded),
                                  selected: _kind == kind,
                                  onSelected: (_) =>
                                      setState(() => _kind = kind)),
                          ]))),
                  const SizedBox(height: 20),
                  AdaptiveCardPair(
                      firstFlex: 3,
                      secondFlex: 2,
                      breakpoint: 680,
                      first: _ModeCard(
                          featured: true,
                          icon: Icons.people_outline_rounded,
                          title: '同屏对弈',
                          description: _kind == GameKind.go
                              ? '与朋友面对面，从九路开始。\n一子一地，步步经营。'
                              : '轮流执黑白，分享落子的乐趣。\n和身边的人，认真下一局。',
                          onTap: () =>
                              context.push('/game', extra: {'kind': _kind})),
                      second: AdaptiveCardPair(
                          breakpoint: 0,
                          first: _ModeCard(
                              icon: Icons.psychology_outlined,
                              title: '人机练习',
                              description: _kind == GameKind.go
                                  ? '提子围地，三档练习'
                                  : '三档难度，随时练习',
                              onTap: () => context.push('/game',
                                  extra: {'gameMode': 'ai', 'kind': _kind})),
                          second: _ModeCard(
                              icon: Icons.wifi_rounded,
                              title: '在线棋室',
                              description: '分享房间，远程交手',
                              onTap: () => context
                                  .push('/online', extra: {'kind': _kind})))),
                  const SizedBox(height: 20),
                  AdaptiveCardPair(
                      firstFlex: 2,
                      secondFlex: 3,
                      breakpoint: 760,
                      first: SectionCard(
                          title: '落子之前',
                          trailing: const Icon(Icons.lightbulb_outline_rounded),
                          child: Text(_kind == GameKind.go
                              ? '黑先白后，白贴 7.5 目。无气提子，禁止自杀与重复局面。双方连续停着后，确认死子再结算。'
                              : '黑方先行，横、竖或斜向连成五子即可获胜。自由五子棋规则，不设禁手。')),
                      second: const ThemeSettingsCard()),
                  const SizedBox(height: 24),
                  Text('一方棋盘 · 片刻从容',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ]))),
      );
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();
  @override
  Widget build(BuildContext context) => SectionCard(
          child: Row(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child:
                Image.asset('assets/icon/app_logo.png', width: 80, height: 80)),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('落一子，慢下来。', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('五子棋与围棋的小小天地',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ]));
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final VoidCallback? onTap;
  final bool featured;
  const _ModeCard(
      {required this.icon,
      required this.title,
      required this.description,
      this.onTap,
      this.featured = false});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = featured ? scheme.onPrimaryContainer : scheme.onSurface;
    return Card(
      color: featured ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
            padding: EdgeInsets.all(featured ? 24 : 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: featured
                            ? scheme.primary.withValues(alpha: .12)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon,
                        size: featured ? 30 : 24,
                        color: onTap == null
                            ? Theme.of(context).disabledColor
                            : scheme.primary)),
                if (featured) ...[
                  const Spacer(),
                  Text('面对面 · 慢慢下', style: TextStyle(color: ink))
                ],
              ]),
              SizedBox(height: featured ? 24 : 16),
              Text(title,
                  style: (featured
                          ? Theme.of(context).textTheme.headlineSmall
                          : Theme.of(context).textTheme.titleMedium)
                      ?.copyWith(color: ink)),
              const SizedBox(height: 8),
              Text(description,
                  style: TextStyle(
                      color: ink.withValues(alpha: .75), height: 1.6)),
              SizedBox(height: featured ? 28 : 20),
              Row(children: [
                Expanded(
                    child: Text(onTap == null ? '暂未开放' : '开始一局',
                        style: TextStyle(color: ink))),
                Icon(
                    onTap == null
                        ? Icons.lock_outline_rounded
                        : Icons.arrow_forward_rounded,
                    size: 20,
                    color: ink),
              ]),
            ])),
      ),
    );
  }
}
