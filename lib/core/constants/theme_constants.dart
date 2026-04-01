import 'package:flutter/material.dart';

class ThemeConstants {
  ThemeConstants._();

  // ─── Hydrawav3 Brand Colors ───
  static const Color darkTeal = Color(0xFF132A35);
  static const Color teal = Color(0xFF233D47);
  static const Color tanDark = Color(0xFFC59D84);
  static const Color tanLight = Color(0xFFDDBEA8);
  static const Color cream = Color(0xFFF9F5F1);
  static const Color copper = Color(0xFFD17D5D);
  static const Color practitionerPrimary = Color(0xFFB56545);

  // Primary = Dark Teal (main brand)
  static const Color primaryColor = darkTeal;
  static const Color primaryLight = teal;
  static const Color primaryDark = Color(0xFF0A1E27);
  // Accent = Copper/Tan
  static const Color accentColor = copper;
  static const Color accentLight = tanLight;
  static const Color accentDark = practitionerPrimary;

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF135BEC);

  // BLE Status
  static const Color bleConnected = success;
  static const Color bleDiscovered = warning;
  static const Color bleDisconnected = Color(0xFF9E9E9E);

  // Neutral
  static const Color backgroundLight = cream;
  static const Color backgroundDark = Color(0xFF0F1115);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1A2E35);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF575757);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color divider = Color(0xFFE2E8F0);

  // Glassmorphism
  static const Color glassLight = Color(0x33FFFFFF);
  static const Color glassDark = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const double glassBlur = 20.0;

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;

  // Border Radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  // Elevation
  static const double elevationSm = 2.0;
  static const double elevationMd = 4.0;
  static const double elevationLg = 8.0;

  // Breakpoints
  static const double tabletBreakpoint = 600.0;
  static const double desktopBreakpoint = 1024.0;
}
