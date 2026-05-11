import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.read(preferencesProvider));
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  final PreferencesService _preferences;

  ThemeModeController(this._preferences)
      : super(_loadInitialMode(_preferences));

  static ThemeMode _loadInitialMode(PreferencesService preferences) {
    return switch (preferences.themeMode) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _preferences.setThemeMode(mode.name);
  }

  Future<void> toggleDarkMode(bool enabled) {
    return setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }
}
