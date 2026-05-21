import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/extensions.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _userIdKey = 'user_id';
  static const _selectedOrgIdKey = 'selected_org_id';
  static const _selectedOrgNameKey = 'selected_org_name';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final cleanAccessToken = accessToken.withoutBearerPrefix;
    final cleanRefreshToken = refreshToken.withoutBearerPrefix;
    print('SAVED TOKEN: $cleanAccessToken');
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: cleanAccessToken),
      _storage.write(key: _refreshTokenKey, value: cleanRefreshToken),
    ]);
  }

  Future<String?> getAccessToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    final normalizedToken = token?.withoutBearerPrefix;
    print('GET TOKEN FROM STORAGE: $normalizedToken');
    return normalizedToken;
  }

  Future<String?> getRefreshToken() async {
    final token = await _storage.read(key: _refreshTokenKey);
    return token?.withoutBearerPrefix;
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null;
  }

  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _biometricEnabledKey, value: enabled.toString());

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  Future<void> saveUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  Future<void> saveSelectedOrganization(String orgId, String orgName) async {
    await Future.wait([
      _storage.write(key: _selectedOrgIdKey, value: orgId),
      _storage.write(key: _selectedOrgNameKey, value: orgName),
    ]);
  }

  Future<String?> getSelectedOrgId() => _storage.read(key: _selectedOrgIdKey);

  Future<String?> getSelectedOrgName() =>
      _storage.read(key: _selectedOrgNameKey);

  Future<void> clearSelectedOrganization() async {
    await Future.wait([
      _storage.delete(key: _selectedOrgIdKey),
      _storage.delete(key: _selectedOrgNameKey),
    ]);
  }

  Future<void> clearAll() => _storage.deleteAll();
}
