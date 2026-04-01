import 'package:flutter/material.dart';

import '../constants/theme_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ThemeConstants.primaryColor,
        brightness: Brightness.light,
        primary: ThemeConstants.primaryColor,
        secondary: ThemeConstants.secondaryColor,
        error: ThemeConstants.error,
        surface: ThemeConstants.surfaceLight,
      ),
      scaffoldBackgroundColor: ThemeConstants.backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: ThemeConstants.surfaceLight,
        foregroundColor: ThemeConstants.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: ThemeConstants.surfaceLight,
        elevation: ThemeConstants.elevationSm,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeConstants.primaryColor,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          side: const BorderSide(color: ThemeConstants.primaryColor),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ThemeConstants.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ThemeConstants.spacingMd,
          vertical: ThemeConstants.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(
            color: ThemeConstants.primaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.error),
        ),
        hintStyle: const TextStyle(color: ThemeConstants.textTertiary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: ThemeConstants.surfaceLight,
        selectedItemColor: ThemeConstants.primaryColor,
        unselectedItemColor: ThemeConstants.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: ThemeConstants.divider,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: ThemeConstants.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: ThemeConstants.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: ThemeConstants.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: ThemeConstants.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: ThemeConstants.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.primaryColor,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ThemeConstants.primaryColor,
        brightness: Brightness.dark,
        primary: ThemeConstants.primaryLight,
        secondary: ThemeConstants.secondaryColor,
        error: ThemeConstants.error,
        surface: ThemeConstants.surfaceDark,
      ),
      scaffoldBackgroundColor: ThemeConstants.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: ThemeConstants.surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: ThemeConstants.surfaceDark,
        elevation: ThemeConstants.elevationSm,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.primaryLight,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeConstants.primaryLight,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          side: const BorderSide(color: ThemeConstants.primaryLight),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ThemeConstants.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ThemeConstants.spacingMd,
          vertical: ThemeConstants.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(
            color: ThemeConstants.primaryLight,
            width: 2,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: ThemeConstants.surfaceDark,
        selectedItemColor: ThemeConstants.primaryLight,
        unselectedItemColor: Colors.grey.shade500,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
