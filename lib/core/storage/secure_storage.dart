import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  // Token management
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    print("SAVED TOKEN: $accessToken");
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  // Future<String?> getAccessToken() =>
  //     _storage.read(key: _accessTokenKey);
  //     print("GET TOKEN: $token");
  Future<String?> getAccessToken() async {
    final token = await _storage.read(key: 'access_token');
    print("GET TOKEN FROM STORAGE: $token"); // ✅ ADD
    return token;
  }

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

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

  // Biometric preference
  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _biometricEnabledKey, value: enabled.toString());

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  // User ID
  Future<void> saveUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  // Organization selection
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

  // Clear all
  Future<void> clearAll() => _storage.deleteAll();
}
