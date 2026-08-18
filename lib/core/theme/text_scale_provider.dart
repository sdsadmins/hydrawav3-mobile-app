import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences.dart';

/// Bounds for the user-adjustable app-wide text scale.
const double kMinTextScale = 0.85;
const double kMaxTextScale = 1.4;

final textScaleProvider =
    StateNotifierProvider<TextScaleController, double>((ref) {
  return TextScaleController(ref.read(preferencesProvider));
});

class TextScaleController extends StateNotifier<double> {
  final PreferencesService _preferences;

  TextScaleController(this._preferences) : super(_preferences.textScale);

  Future<void> setScale(double scale) async {
    final clamped = scale.clamp(kMinTextScale, kMaxTextScale);
    state = clamped;
    await _preferences.setTextScale(clamped);
  }
}
