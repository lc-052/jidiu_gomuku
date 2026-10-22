import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../services/storage_service.dart';
import '../widgets/section_card.dart';
import '../widgets/theme_settings_card.dart';
import '../widgets/adaptive_card_pair.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final storage = StorageService();
  Future<void> _save(Future<void> value) async {
    await value;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  AdaptiveCardPair(
                      firstFlex: 3,
                      secondFlex: 2,
                      breakpoint: 760,
                      first: const ThemeSettingsCard(),
                      second: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionCard(
                                title: '人机练习',
                                subtitle: '五子棋与围棋难度',
                                child:
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final d in Difficulty.values)
                                    ChoiceChip(
                                        label: Text(d.displayName),
                                        selected:
                                            storage.difficultyIndex == d.index,
                                        onSelected: (_) => _save(storage
                                            .saveDifficultyIndex(d.index))),
                                ])),
                            const SizedBox(height: 16),
                            SectionCard(
                                title: '执子偏好',
                                subtitle: '人机对局，黑方先行',
                                child:
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final p in Player.values)
                                    ChoiceChip(
                                        label: Text('执${p.cn}'),
                                        selected: storage.preferredColor == p,
                                        onSelected: (_) => _save(
                                            storage.savePreferredColor(
                                                p == Player.black
                                                    ? 'black'
                                                    : 'white'))),
                                ])),
                          ])),
                  const SizedBox(height: 20),
                  AdaptiveCardPair(
                      breakpoint: 0,
                      first: _FeedbackCard(
                          title: '触感反馈',
                          description: '落子时轻触振动',
                          icon: Icons.vibration_rounded,
                          value: storage.vibrationEnabled,
                          onChanged: (v) =>
                              _save(storage.saveVibrationEnabled(v))),
                      second: _FeedbackCard(
                          title: '落子音效',
                          description: '轻柔的系统提示',
                          icon: Icons.music_note_outlined,
                          value: storage.soundEnabled,
                          onChanged: (v) =>
                              _save(storage.saveSoundEnabled(v)))),
                  const SizedBox(height: 20),
                  const SectionCard(
                      title: '关于寄丢棋室',
                      child: Text(
                          '一方棋盘，两种乐趣。五子棋支持双人、人机与在线联机；围棋支持 9 / 13 / 19 路双人及离线人机练习。设置会自动保存。')),
                ]))),
      );
}

class _FeedbackCard extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FeedbackCard(
      {required this.title,
      required this.description,
      required this.icon,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => SectionCard(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child:
                    Icon(icon, color: Theme.of(context).colorScheme.primary)),
            Switch.adaptive(value: value, onChanged: onChanged),
          ]),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(description,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ));
}
