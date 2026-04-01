import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/advanced_settings_model.dart';

final advancedSettingsProvider =
    StateNotifierProvider<AdvancedSettingsNotifier, AdvancedSettings>((ref) {
  return AdvancedSettingsNotifier();
});

class AdvancedSettingsNotifier extends StateNotifier<AdvancedSettings> {
  AdvancedSettingsNotifier() : super(const AdvancedSettings());

  void updateHotPwm(double value) =>
      state = state.copyWith(hotPwm: value);

  void updateColdPwm(double value) =>
      state = state.copyWith(coldPwm: value);

  void updateVibMin(double value) =>
      state = state.copyWith(vibMin: value);

  void updateVibMax(double value) =>
      state = state.copyWith(vibMax: value);

  void updateLightIntensity(double value) =>
      state = state.copyWith(lightIntensity: value);

  void updateCyclePause(double value) =>
      state = state.copyWith(customCyclePause: value);

  void toggleOverride(bool value) =>
      state = state.copyWith(overrideProtocolDefaults: value);

  void loadFromJson(String jsonStr) =>
      state = AdvancedSettings.decode(jsonStr);

  void reset() => state = const AdvancedSettings();
}
