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

  // Web-parity role tokens (Hydra brand). The web UI has a dark slate nav,
  // dark/light segmented toggles, and warm icon squares — roles the base
  // palette above doesn't cover.
  final Color navBackground; // bottom-nav / dark chrome (web --darkTeal)
  final Color onNav; // icon/label color on navBackground (web --cream)
  final Color segmentActiveBg; // selected toggle segment (dark)
  final Color segmentInactiveBg; // unselected toggle segment (light)
  final Color iconSurface; // warm square behind icons (web --secondary-nude)

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
    required this.navBackground,
    required this.onNav,
    required this.segmentActiveBg,
    required this.segmentInactiveBg,
    required this.iconSurface,
  });
}

class ThemeConstants {
  ThemeConstants._();

  // Light palette — Hydra web brand (values sourced from Hydrawav3-ai
  // app/globals.css): cream canvas, white cards, tan accent, dark slate nav.
  static const ThemePalette _lightPalette = ThemePalette(
    background: Color(0xFFF9F5F1), // --cream
    surface: Color(0xFFFFFFFF), // --white (cards)
    surfaceVariant: Color(0xFFF3F4F6), // --background-light
    accent: Color(0xFFC59D84), // --tanDark
    accentLight: Color(0xFFDDBEA8), // --tanLight
    textPrimary: Color(0xFF1A1A1A), // --text-light-primary
    textSecondary: Color(0xFF575757), // --text-light-secondary
    textTertiary: Color(0xFF64748B), // --text-subtle
    border: Color(0xFFDDBEA8), // --tanLight (tan stroke)
    borderLight: Color(0xFFE0E0E0), // --border-light
    navBackground: Color(0xFF132A35), // --darkTeal
    onNav: Color(0xFFF9F5F1), // --cream
    segmentActiveBg: Color(0xFF132A35), // --darkTeal
    segmentInactiveBg: Color(0xFFF3F4F6), // --background-light
    iconSurface: Color(0xFFE5D9D2), // --secondary-nude
  );

  // Dark palette — branded dark derived from the web's dark brand tones
  // (--black/--darkTeal/--teal) instead of the previous generic blue.
  static const ThemePalette _darkPalette = ThemePalette(
    background: Color(0xFF0F1115), // --black
    surface: Color(0xFF132A35), // --darkTeal (cards)
    surfaceVariant: Color(0xFF233D47), // --teal
    accent: Color(0xFFC59D84), // --tanDark
    accentLight: Color(0xFFDDBEA8), // --tanLight
    textPrimary: Color(0xFFF9F5F1), // --cream
    textSecondary: Color(0xFFB9C2C7), // derived
    textTertiary: Color(0xFF8A969C), // derived
    border: Color(0xFF2A3F49), // derived
    borderLight: Color(0xFF3A4C56), // derived
    navBackground: Color(0xFF0E2129), // derived (deeper than darkTeal)
    onNav: Color(0xFFF9F5F1), // --cream
    // Selected toggle = tan accent in dark mode, matching the protocol goal
    // chip (_GoalFilterChip). A dark-teal segment was nearly invisible on the
    // dark-teal cards; the tan pops and keeps toggles consistent everywhere.
    segmentActiveBg: Color(0xFFC59D84), // --tanDark (== dark accent)
    segmentInactiveBg: Color(0xFF182A33), // derived
    iconSurface: Color(0xFF233D47), // --teal
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
  static Color get navBackground => _activePalette.navBackground;
  static Color get onNav => _activePalette.onNav;
  static Color get segmentActiveBg => _activePalette.segmentActiveBg;
  static Color get segmentInactiveBg => _activePalette.segmentInactiveBg;
  static Color get iconSurface => _activePalette.iconSurface;

  // Text/icon color to place on the tan accent. The accent is the same light
  // tan in both palettes, so this stays a fixed dark in both modes (cream
  // text on tan would be unreadable in dark mode).
  static const Color onAccent = Color(0xFF1A1A1A);

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
