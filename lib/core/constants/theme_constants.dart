import 'package:flutter/material.dart';

class ThemeConstants {
  ThemeConstants._();

  // ─── Light / Cream Palette ───
  static const Color background = Color(0xFFF9F5F1); // light warm off-white
  static const Color surface = Color(0xFFF5EBDD); // warm surface
  static const Color surfaceVariant = Color(0xFFE8D9C4); // deeper warm tint
  static const Color accent = Color(0xFFC69E83);
  static const Color accentLight = Color(0xFFD6B39D);

  // Text
  static const Color textPrimary = Color(0xFF141414);
  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color textTertiary = Color(0xFF7A7A7A);

  // Borders
  static const Color border = Color(0xFFD7C6AE);
  static const Color borderLight = Color(0xFFE0D2BF);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // BLE Status
  static const Color bleConnected = success;
  static const Color bleDiscovered = warning;
  static const Color bleDisconnected = textTertiary;

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Border Radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  // Breakpoints
  static const double tabletBreakpoint = 600.0;
}
