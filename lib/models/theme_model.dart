import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Five quiet Material 3 palettes, including matching board colors.
class ThemePalette {
  final String name;
  final Color primaryColor;
  final Color bgColor;
  final Color boardBgColor;
  final Color textColor;
  final Color cardColor;
  final Color darkBackground;
  final Color darkCard;
  const ThemePalette(
      this.name, this.primaryColor, this.bgColor, this.boardBgColor,
      {this.textColor = const Color(0xFF38352F),
      this.cardColor = const Color(0xFFF1E5D0),
      this.darkBackground = const Color(0xFF1C1914),
      this.darkCard = const Color(0xFF343027)});

  Color get secondaryColor => textColor.withValues(alpha: .72);
  Color get borderColor => textColor.withValues(alpha: .18);
  Color get gridColor => textColor.withValues(alpha: .38);
  List<Color> get blackStoneGrad1 =>
      const [Color(0xFF565652), Color(0xFF262725)];
  List<Color> get blackStoneGrad2 => blackStoneGrad1;
  List<Color> get whiteStoneGrad1 =>
      const [Color(0xFFFFFDF8), Color(0xFFDCDAD3)];
  List<Color> get whiteStoneGrad2 => whiteStoneGrad1;

  static const all = [
    ThemePalette(
        '奶油米白', Color(0xFF957035), Color(0xFFFFFDF3), Color(0xFFE3CDA6)),
    ThemePalette('雾松绿', Color(0xFF3F7957), Color(0xFFE0EBE3), Color(0xFFB9D4BD),
        cardColor: Color(0xFFF6FCF5),
        darkBackground: Color(0xFF15221B),
        darkCard: Color(0xFF2A3C30)),
    ThemePalette('雨空蓝', Color(0xFF3E73A2), Color(0xFFDFEAF5), Color(0xFFB7CFE4),
        cardColor: Color(0xFFF7FBFF),
        darkBackground: Color(0xFF16212D),
        darkCard: Color(0xFF2B3B4D)),
    ThemePalette('浅藤紫', Color(0xFF8259A1), Color(0xFFEBE1F2), Color(0xFFD3BCE2),
        cardColor: Color(0xFFFFF8FF),
        darkBackground: Color(0xFF241C2B),
        darkCard: Color(0xFF3E304A)),
    ThemePalette('陶土粉', Color(0xFFAC6450), Color(0xFFF3E1D8), Color(0xFFE3BCAA),
        cardColor: Color(0xFFFFF9F5),
        darkBackground: Color(0xFF2B1E19),
        darkCard: Color(0xFF48332A)),
  ];

  static ThemePalette resolve(BuildContext context, int index) {
    final p = all[index.clamp(0, all.length - 1)];
    final scheme = Theme.of(context).colorScheme;
    if (scheme.brightness == Brightness.light) return p;
    return ThemePalette(
        p.name, scheme.primary, scheme.surface, scheme.surfaceContainerHigh,
        textColor: scheme.onSurface);
  }

  ThemeData materialTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    ).copyWith(
      surface: brightness == Brightness.light ? bgColor : darkBackground,
      surfaceContainerLow:
          brightness == Brightness.light ? cardColor : darkCard,
      surfaceContainerHigh: brightness == Brightness.light
          ? Color.lerp(cardColor, primaryColor, .1)
          : Color.lerp(darkCard, primaryColor, .15),
    );
    return ThemeData(
      fontFamily: kIsWeb ? 'JidiuSans' : null,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme:
          AppBarTheme(backgroundColor: scheme.surface, centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: .1),
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
      ),
      dividerTheme:
          DividerThemeData(color: scheme.outlineVariant.withValues(alpha: .5)),
    );
  }
}
