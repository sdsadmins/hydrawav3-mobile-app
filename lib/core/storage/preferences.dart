import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final preferencesProvider = Provider<PreferencesService>((ref) {
  return PreferencesService(ref.read(sharedPreferencesProvider));
});

class PreferencesService {
  static const _lastProtocolIdKey = 'last_protocol_id';
  static const _lastDeviceIdKey = 'last_device_id';
  static const _themeModeKey = 'theme_mode';
  static const _onboardingCompletedKey = 'onboarding_completed';
  static const _discomfortTrackingKey = 'discomfort_tracking_enabled';
  static const _lastOrgIdKey = 'last_organization_id';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  // Last selected protocol
  String? get lastProtocolId => _prefs.getString(_lastProtocolIdKey);
  Future<void> setLastProtocolId(String id) =>
      _prefs.setString(_lastProtocolIdKey, id);

  // Last connected device
  String? get lastDeviceId => _prefs.getString(_lastDeviceIdKey);
  Future<void> setLastDeviceId(String id) =>
      _prefs.setString(_lastDeviceIdKey, id);

  // Theme mode: 'light', 'dark', 'system'
  String get themeMode => _prefs.getString(_themeModeKey) ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString(_themeModeKey, mode);

  // Onboarding
  bool get onboardingCompleted =>
      _prefs.getBool(_onboardingCompletedKey) ?? false;
  Future<void> setOnboardingCompleted(bool completed) =>
      _prefs.setBool(_onboardingCompletedKey, completed);

  // Discomfort tracking
  bool get discomfortTrackingEnabled =>
      _prefs.getBool(_discomfortTrackingKey) ?? true;
  Future<void> setDiscomfortTrackingEnabled(bool enabled) =>
      _prefs.setBool(_discomfortTrackingKey, enabled);

  // Organization
  String? get lastOrganizationId => _prefs.getString(_lastOrgIdKey);
  Future<void> setLastOrganizationId(String id) =>
      _prefs.setString(_lastOrgIdKey, id);
}
