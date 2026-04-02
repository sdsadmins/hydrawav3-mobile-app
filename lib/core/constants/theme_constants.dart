import 'package:flutter/material.dart';

class ThemeConstants {
  ThemeConstants._();

  // ─── Navy / Copper / Beige palette (from hydrawav3-prototype) ───
  static const Color background = Color(0xFF0A192F);   // navy-900
  static const Color backgroundDeep = Color(0xFF050B14); // navy-950
  static const Color surface = Color(0xFF112240);       // navy-800
  static const Color surfaceVariant = Color(0xFF233554); // navy-700

  // Copper accent
  static const Color accent = Color(0xFFB87333);        // copper-500
  static const Color accentDark = Color(0xFF8B5A2B);    // copper-600
  static const Color accentLight = Color(0xFFCD7F32);   // copper-400
  static const Color accentLighter = Color(0xFFE09F58); // copper-300

  // Text — beige tones instead of pure white
  static const Color textPrimary = Color(0xFFF5F5F0);   // beige-100
  static const Color textBright = Color(0xFFFCFCF9);    // beige-50
  static const Color textSecondary = Color(0xFF8892B0);  // metallic-500
  static const Color textTertiary = Color(0xFF64748B);   // metallic-600

  // Metallic mid-tone
  static const Color metallic400 = Color(0xFFA8B2D1);   // metallic-400

  // Borders
  static const Color border = Color(0xFF233554);         // navy-700
  static const Color borderLight = Color(0xFF233554);    // navy-700 (same)

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
