import 'package:flutter/material.dart';

class ThemeConstants {
  ThemeConstants._();

  // Brand Colors
  static const Color primaryColor = Color(0xFF0066FF);
  static const Color primaryLight = Color(0xFF4D94FF);
  static const Color primaryDark = Color(0xFF004ACC);
  static const Color secondaryColor = Color(0xFF00D4AA);
  static const Color accentColor = Color(0xFF6C63FF);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);

  // BLE Status Colors
  static const Color bleConnected = Color(0xFF4CAF50);
  static const Color bleDiscovered = Color(0xFFFF9800);
  static const Color bleDisconnected = Color(0xFF9E9E9E);

  // Neutral Colors
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color divider = Color(0xFFE5E7EB);

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

  // Tablet breakpoint
  static const double tabletBreakpoint = 600.0;
  static const double desktopBreakpoint = 1024.0;
}
