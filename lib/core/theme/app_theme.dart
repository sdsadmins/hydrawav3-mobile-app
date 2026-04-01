import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/theme_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ThemeConstants.darkTeal,
        brightness: Brightness.light,
        primary: ThemeConstants.darkTeal,
        secondary: ThemeConstants.copper,
        tertiary: ThemeConstants.tanLight,
        error: ThemeConstants.error,
        surface: ThemeConstants.surfaceLight,
      ),
      scaffoldBackgroundColor: ThemeConstants.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ThemeConstants.darkTeal,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.darkTeal,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: ThemeConstants.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusLg),
          side: BorderSide(
            color: ThemeConstants.divider.withValues(alpha: 0.5),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.darkTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeConstants.darkTeal,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
          side: const BorderSide(color: ThemeConstants.darkTeal, width: 1.5),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
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
            color: ThemeConstants.darkTeal,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.error),
        ),
        hintStyle: const TextStyle(
          color: ThemeConstants.textTertiary,
          fontFamily: 'Inter',
        ),
        labelStyle: const TextStyle(
          color: ThemeConstants.textSecondary,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: ThemeConstants.darkTeal.withValues(alpha: 0.1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ThemeConstants.darkTeal,
            );
          }
          return const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: ThemeConstants.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: ThemeConstants.darkTeal,
              size: 24,
            );
          }
          return const IconThemeData(
            color: ThemeConstants.textTertiary,
            size: 24,
          );
        }),
        elevation: 0,
        height: 70,
      ),
      dividerTheme: DividerThemeData(
        color: ThemeConstants.divider.withValues(alpha: 0.5),
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: ThemeConstants.darkTeal,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.darkTeal,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.darkTeal,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.textPrimary,
          letterSpacing: -0.2,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: ThemeConstants.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: ThemeConstants.textSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: ThemeConstants.textTertiary,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.darkTeal,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ThemeConstants.cream,
        selectedColor: ThemeConstants.darkTeal.withValues(alpha: 0.1),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
          side: BorderSide(color: ThemeConstants.divider.withValues(alpha: 0.5)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ThemeConstants.darkTeal,
        brightness: Brightness.dark,
        primary: ThemeConstants.tanDark,
        secondary: ThemeConstants.copper,
        tertiary: ThemeConstants.tanLight,
        error: ThemeConstants.error,
        surface: ThemeConstants.surfaceDark,
      ),
      scaffoldBackgroundColor: ThemeConstants.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ThemeConstants.tanLight,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.tanLight,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: ThemeConstants.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusLg),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.copper,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ThemeConstants.surfaceDark,
        indicatorColor: ThemeConstants.tanDark.withValues(alpha: 0.15),
        elevation: 0,
        height: 70,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ThemeConstants.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
          borderSide: const BorderSide(color: ThemeConstants.tanDark, width: 2),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: ThemeConstants.tanLight,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.tanLight,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.tanLight,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.2,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          color: Colors.white70,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: Colors.white54,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: Colors.white38,
        ),
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
