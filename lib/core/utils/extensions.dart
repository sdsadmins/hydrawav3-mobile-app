import 'package:flutter/material.dart';

import '../constants/theme_constants.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isTablet => screenWidth >= ThemeConstants.tabletBreakpoint;

  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? ThemeConstants.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

extension StringExtensions on String {
  String get capitalize =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';

  String truncate(int maxLength) =>
      length <= maxLength ? this : '${substring(0, maxLength)}...';

  /// Some APIs return `Bearer <jwt>`; we store the raw JWT and add Bearer in interceptors.
  String get withoutBearerPrefix {
    final t = trim();
    if (t.length > 7 && t.toLowerCase().startsWith('bearer ')) {
      return t.substring(7).trim();
    }
    return t;
  }
}

/// Natural ("human") order comparison so protocol names sort 1, 2, 3 … 10, 11
/// instead of the lexicographic 1, 10, 11, 2. Splits each string into runs of
/// digits and non-digits and compares digit runs numerically (leading zeros
/// ignored), everything else case-insensitively.
int naturalCompare(String a, String b) {
  final lowerA = a.toLowerCase();
  final lowerB = b.toLowerCase();
  int i = 0, j = 0;
  final lenA = lowerA.length, lenB = lowerB.length;

  bool isDigit(int c) => c >= 0x30 && c <= 0x39;

  while (i < lenA && j < lenB) {
    final ca = lowerA.codeUnitAt(i);
    final cb = lowerB.codeUnitAt(j);

    if (isDigit(ca) && isDigit(cb)) {
      // Consume full digit runs on both sides and compare as numbers.
      final startA = i;
      while (i < lenA && isDigit(lowerA.codeUnitAt(i))) {
        i++;
      }
      final startB = j;
      while (j < lenB && isDigit(lowerB.codeUnitAt(j))) {
        j++;
      }
      // Strip leading zeros before comparing length, then value.
      var numA = lowerA.substring(startA, i).replaceFirst(RegExp(r'^0+'), '');
      var numB = lowerB.substring(startB, j).replaceFirst(RegExp(r'^0+'), '');
      if (numA.length != numB.length) {
        return numA.length - numB.length;
      }
      final cmp = numA.compareTo(numB);
      if (cmp != 0) return cmp;
    } else {
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  return (lenA - i) - (lenB - j);
}

extension DurationExtensions on Duration {
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
