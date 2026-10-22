import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/models/theme_notifier.dart';
import 'package:gomuku/services/storage_service.dart';

void main() {
  test('five palettes each provide genuine light and dark Material 3 themes',
      () {
    expect(ThemePalette.all.length, 5);
    expect(ThemePalette.all.first.bgColor, const Color(0xFFFFFDF3));
    for (final palette in ThemePalette.all) {
      final light = palette.materialTheme(Brightness.light);
      final dark = palette.materialTheme(Brightness.dark);
      expect(light.useMaterial3, true);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    }
  });
  test('palette and all display modes persist and restore', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    final n = ThemeNotifier();
    expect(n.themeMode, ThemeMode.system);
    for (final mode in ThemeMode.values) {
      n.setThemeMode(mode);
      n.setThemeIndex(4);
      await Future<void>.delayed(Duration.zero);
      final restored = ThemeNotifier();
      expect(restored.chosenThemeIndex, 4);
      expect(restored.themeMode, mode);
    }
    n.setThemeIndex(99);
    expect(n.chosenThemeIndex, 4);
    n.dispose();
  });
}
