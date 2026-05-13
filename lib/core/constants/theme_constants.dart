import 'package:flutter/material.dart';

class ThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color accent;
  final Color accentLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderLight;

  const ThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.accent,
    required this.accentLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderLight,
  });
}

class ThemeConstants {
  ThemeConstants._();

  static const ThemePalette _lightPalette = ThemePalette(
    background: Color(0xFFF9F5F1),
    surface: Color(0xFFF5EBDD),
    surfaceVariant: Color(0xFFE8D9C4),
    accent: Color(0xFFC69E83),
    accentLight: Color(0xFFD6B39D),
    textPrimary: Color(0xFF141414),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF7A7A7A),
    border: Color(0xFFD7C6AE),
    borderLight: Color(0xFFE0D2BF),
  );

  static const ThemePalette _darkPalette = ThemePalette(
    background: Color(0xFF0D1A2D),
    surface: Color(0xFF243756),
    surfaceVariant: Color(0xFF172845),
    accent: Color(0xFFC79E84),
    accentLight: Color(0xFF2D4470),
    textPrimary: Color(0xFFF7F4EE),
    textSecondary: Color(0xFFB3BED4),
    textTertiary: Color(0xFF8390AC),
    border: Color(0xFF4D638C),
    borderLight: Color(0xFFA9B7D3),
  );

  static ThemePalette _activePalette = _lightPalette;

  static void useBrightness(Brightness brightness) {
    _activePalette =
        brightness == Brightness.dark ? _darkPalette : _lightPalette;
  }

  static ThemePalette paletteFor(Brightness brightness) {
    return brightness == Brightness.dark ? _darkPalette : _lightPalette;
  }

  static Color get background => _activePalette.background;
  static Color get surface => _activePalette.surface;
  static Color get surfaceVariant => _activePalette.surfaceVariant;
  static Color get accent => _activePalette.accent;
  static Color get accentLight => _activePalette.accentLight;
  static Color get textPrimary => _activePalette.textPrimary;
  static Color get textSecondary => _activePalette.textSecondary;
  static Color get textTertiary => _activePalette.textTertiary;
  static Color get border => _activePalette.border;
  static Color get borderLight => _activePalette.borderLight;

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static Color get bleConnected => success;
  static Color get bleDiscovered => warning;
  static Color get bleDisconnected => textTertiary;

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  static const double tabletBreakpoint = 600.0;
}
