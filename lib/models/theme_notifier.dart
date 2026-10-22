import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'theme_model.dart';

class ThemeNotifier extends ChangeNotifier {
  int _index = StorageService().themeIndex;
  ThemeMode _mode = StorageService().themeMode;
  int get chosenThemeIndex => _index;
  ThemeMode get themeMode => _mode;
  ThemeData theme(Brightness brightness) =>
      ThemePalette.all[_index].materialTheme(brightness);

  void setThemeIndex(int index) {
    if (index < 0 || index >= ThemePalette.all.length) return;
    _index = index;
    StorageService().saveThemeIndex(index);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _mode = mode;
    StorageService().saveThemeMode(mode);
    notifyListeners();
  }
}
