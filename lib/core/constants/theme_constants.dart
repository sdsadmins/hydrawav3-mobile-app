import 'package:flutter/material.dart';

class ThemeConstants {
  ThemeConstants._();

  // ─── Dark Theme Palette (from reference design) ───
  static const Color background = Color(0xFF1A2332);
  static const Color surface = Color(0xFF212D3B);
  static const Color surfaceVariant = Color(0xFF2A3A4A);
  static const Color accent = Color(0xFFD97A3A);
  static const Color accentLight = Color(0xFFE89B5E);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8B95A5);
  static const Color textTertiary = Color(0xFF5A6577);

  // Borders
  static const Color border = Color(0xFF2D3B4D);
  static const Color borderLight = Color(0xFF3A4A5C);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // BLE Status
  static const Color bleConnected = success;
  static const Color bleDiscovered = warning;
  static const Color bleDisconnected = Color(0xFF5A6577);

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
