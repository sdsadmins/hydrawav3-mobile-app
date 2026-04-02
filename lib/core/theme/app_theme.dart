import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/theme_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => darkTheme; // dark-only app

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ThemeConstants.background,
      colorScheme: const ColorScheme.dark(
        primary: ThemeConstants.accent,
        secondary: ThemeConstants.accentLight,
        surface: ThemeConstants.surface,
        error: ThemeConstants.error,
        onPrimary: Colors.white,
        onSurface: ThemeConstants.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ThemeConstants.background,
        foregroundColor: ThemeConstants.textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: ThemeConstants.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          side: const BorderSide(color: ThemeConstants.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeConstants.accent,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          side: const BorderSide(color: ThemeConstants.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ThemeConstants.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.error),
        ),
        hintStyle: const TextStyle(color: ThemeConstants.textTertiary),
        labelStyle: const TextStyle(color: ThemeConstants.textSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: ThemeConstants.border,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: ThemeConstants.textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ThemeConstants.textPrimary, letterSpacing: -0.3),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ThemeConstants.textPrimary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeConstants.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: ThemeConstants.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeConstants.textSecondary, letterSpacing: 0.5),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
