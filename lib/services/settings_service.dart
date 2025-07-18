import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Notifiers to allow the UI to react to changes
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));
final ValueNotifier<double> fontSizeNotifier = ValueNotifier(1.0);

class SettingsService {
  // Keys for storing data in SharedPreferences
  static const String _themeKey = 'app_theme';
  static const String _languageKey = 'app_language';
  static const String _fontSizeKey = 'app_font_size';

  /// Loads all user settings from local storage and updates the notifiers.
  /// This should be called once when the app starts.
  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Theme
    final themeString = prefs.getString(_themeKey) ?? 'system';
    themeNotifier.value = _themeModeFromString(themeString);

    // Load Language
    final languageCode = prefs.getString(_languageKey) ?? 'en';
    localeNotifier.value = Locale(languageCode);

    // Load Font Size
    fontSizeNotifier.value = prefs.getDouble(_fontSizeKey) ?? 1.0; // 1.0 is default
  }

  /// Saves the theme preference.
  static Future<void> saveTheme(ThemeMode mode) async {
    themeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, _themeModeToString(mode));
  }

  /// Saves the language preference.
  static Future<void> saveLanguage(String languageCode) async {
    localeNotifier.value = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }

  /// Saves the font size preference.
  static Future<void> saveFontSize(double scale) async {
    fontSizeNotifier.value = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, scale);
  }

  // Helper methods for theme conversion
  static ThemeMode _themeModeFromString(String theme) {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }
}
