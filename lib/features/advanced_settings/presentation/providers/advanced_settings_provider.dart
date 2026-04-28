import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/advanced_settings_model.dart';

final advancedSettingsProvider =
    StateNotifierProvider<AdvancedSettingsNotifier, AdvancedSettings>((ref) {
  return AdvancedSettingsNotifier();
});

class AdvancedSettingsNotifier extends StateNotifier<AdvancedSettings> {
  AdvancedSettingsNotifier() : super(const AdvancedSettings());

  void setLights(bool value) => state = state.copyWith(lights: value);

  void setVibrationMode(String mode) =>
      state = state.copyWith(vibrationMode: mode);

  void setVibrationSweepMin(double value) =>
      state = state.copyWith(vibrationSweepMin: value);
  void setVibrationSweepMax(double value) =>
      state = state.copyWith(vibrationSweepMax: value);
  void setVibrationSingleHz(double value) =>
      state = state.copyWith(vibrationSingleHz: value);

  void setHotLevel(int level) => state = state.copyWith(hotLevel: level);
  void setColdLevel(int level) => state = state.copyWith(coldLevel: level);
  void setHotPack(bool value) => state = state.copyWith(hotPack: value);
  void setColdPack(bool value) => state = state.copyWith(coldPack: value);

  void setHotDrop(double value) => state = state.copyWith(hotDrop: value);
  void setColdDrop(double value) => state = state.copyWith(coldDrop: value);

  void setCycle1(bool value) => state = state.copyWith(cycle1Initiation: value);
  void setCycle5(bool value) => state = state.copyWith(cycle5Completion: value);

  void setStartDelay(int seconds) => state = state.copyWith(startDelay: seconds);
  void setFlipSettings(bool value) =>
      state = state.copyWith(flipSettings: value);

  void setVibMin(double value) => state = state.copyWith(vibMin: value);
  void setVibMax(double value) => state = state.copyWith(vibMax: value);

  void loadFromJson(String jsonStr) =>
      state = AdvancedSettings.decode(jsonStr);

  void reset() => state = const AdvancedSettings();
}
