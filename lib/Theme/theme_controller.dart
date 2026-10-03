import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.dark; // the neon look is dark-first

  ThemeMode get mode => _mode;

  // Load saved theme mode
  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeKey);

    switch (saved) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      case 'system':
        _mode = ThemeMode.system;
        break;
      default:
        _mode = ThemeMode.dark;
    }
    notifyListeners();
  }

  // Save theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    switch (mode) {
      case ThemeMode.light:
        await prefs.setString(_themeKey, 'light');
        break;
      case ThemeMode.dark:
        await prefs.setString(_themeKey, 'dark');
        break;
      default:
        await prefs.setString(_themeKey, 'system');
    }
  }

  // Optional helpers
  void useSystem() => setThemeMode(ThemeMode.system);
  void useLight() => setThemeMode(ThemeMode.light);
  void useDark() => setThemeMode(ThemeMode.dark);
}
