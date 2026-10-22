import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/theme_model.dart';
import '../models/theme_notifier.dart';
import 'section_card.dart';

class ThemeSettingsCard extends StatelessWidget {
  const ThemeSettingsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ThemeNotifier>();
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
        title: '外观与主题',
        subtitle: '柔和的色彩，让注意力留在棋盘上',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, bounds) {
              final columns = bounds.maxWidth >= 480 ? 3 : 2;
              final width = (bounds.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(ThemePalette.all.length, (i) {
                    final palette = ThemePalette.all[i];
                    return SizedBox(
                        width: width,
                        child: _PaletteTile(
                          palette: palette,
                          selected: notifier.chosenThemeIndex == i,
                          onTap: () => notifier.setThemeIndex(i),
                        ));
                  }));
            }),
            const SizedBox(height: 20),
            Text('显示模式', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in const [
                (ThemeMode.system, Icons.brightness_auto_outlined, '跟随系统'),
                (ThemeMode.light, Icons.light_mode_outlined, '浅色'),
                (ThemeMode.dark, Icons.dark_mode_outlined, '深色')
              ])
                ChoiceChip(
                    label: Text(entry.$3),
                    avatar: Icon(entry.$2, size: 18),
                    selected: notifier.themeMode == entry.$1,
                    onSelected: (_) => notifier.setThemeMode(entry.$1)),
            ]),
          ],
        ));
  }
}

class _PaletteTile extends StatelessWidget {
  final ThemePalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _PaletteTile(
      {required this.palette, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
        selected: selected,
        button: true,
        label: palette.name,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color:
                              selected ? scheme.primary : scheme.outlineVariant,
                          width: selected ? 2 : 1)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 44,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: dark
                                    ? palette.darkBackground
                                    : palette.bgColor,
                                borderRadius: BorderRadius.circular(9)),
                            child: Row(children: [
                              Expanded(
                                  child: Container(
                                      decoration: BoxDecoration(
                                          color: dark
                                              ? palette.darkCard
                                              : palette.cardColor,
                                          borderRadius:
                                              BorderRadius.circular(5)))),
                              const SizedBox(width: 6),
                              Container(
                                  width: 20,
                                  decoration: BoxDecoration(
                                      color: palette.primaryColor,
                                      borderRadius: BorderRadius.circular(5))),
                            ])),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: Text(palette.name,
                                  style:
                                      Theme.of(context).textTheme.labelLarge)),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                size: 16, color: scheme.primary)
                        ]),
                      ])),
            )));
  }
}
