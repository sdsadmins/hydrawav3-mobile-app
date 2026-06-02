import 'dart:async';

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
    await _safeWrite(_accessTokenKey, cleanAccessToken);
    await _safeWrite(_refreshTokenKey, cleanRefreshToken);
  }

  /// Reads a key without ever hanging or throwing.
  ///
  /// With `encryptedSharedPreferences`, a read is backed by the Android
  /// Keystore. On some devices (notably Samsung) a bad/invalidated master key
  /// can make `read()` block indefinitely or throw — which, in the auth
  /// interceptor, would freeze a request before it starts (Dio's timeouts only
  /// cover the network call), producing an infinite login spinner with no error.
  ///
  /// So we cap every read with a timeout and swallow failures, returning null.
  /// A genuine corruption *exception* (not a transient timeout) also triggers a
  /// best-effort reset so the store becomes writable again and the user can log
  /// in fresh without uninstalling. A timeout never wipes anything.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage
          .read(key: key)
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      print('SECURE STORAGE READ TIMED OUT for $key (proceeding without it)');
      return null;
    } catch (e) {
      print('SECURE STORAGE READ FAILED for $key: $e');
      unawaited(_recoverFromCorruption());
      return null;
    }
  }

  /// Writes a key without ever hanging the caller. Same keystore-hang risk as
  /// reads: a write that blocks would freeze the login flow *after* a successful
  /// network sign-in (saving the fresh tokens). We cap it with a timeout and
  /// swallow failures — the login flow re-verifies the token afterwards and
  /// surfaces a real error if persistence truly failed, instead of spinning
  /// forever. A genuine error self-heals the store.
  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage
          .write(key: key, value: value)
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      print('SECURE STORAGE WRITE TIMED OUT for $key');
    } catch (e) {
      print('SECURE STORAGE WRITE FAILED for $key: $e');
      unawaited(_recoverFromCorruption());
    }
  }

  /// Deletes a key without ever hanging or throwing.
  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key).timeout(const Duration(seconds: 4));
    } on TimeoutException {
      print('SECURE STORAGE DELETE TIMED OUT for $key');
    } catch (e) {
      print('SECURE STORAGE DELETE FAILED for $key: $e');
    }
  }

  /// Best-effort wipe of a corrupted store so future writes succeed. Guarded so
  /// it can never throw or hang the caller. Only invoked on real read errors.
  Future<void> _recoverFromCorruption() async {
    try {
      await _storage.deleteAll().timeout(const Duration(seconds: 4));
      print('SECURE STORAGE: reset after corruption');
    } catch (_) {
      // Nothing more we can safely do here.
    }
  }

  Future<String?> getAccessToken() async {
    final token = await _safeRead(_accessTokenKey);
    final normalizedToken = token?.withoutBearerPrefix;
    print('GET TOKEN FROM STORAGE: $normalizedToken');
    return normalizedToken;
  }

  Future<String?> getRefreshToken() async {
    final token = await _safeRead(_refreshTokenKey);
    return token?.withoutBearerPrefix;
  }

  Future<void> clearTokens() async {
    await _safeDelete(_accessTokenKey);
    await _safeDelete(_refreshTokenKey);
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null;
  }

  Future<void> setBiometricEnabled(bool enabled) =>
      _safeWrite(_biometricEnabledKey, enabled.toString());

  Future<bool> isBiometricEnabled() async {
    final value = await _safeRead(_biometricEnabledKey);
    return value == 'true';
  }

  Future<void> saveUserId(String userId) => _safeWrite(_userIdKey, userId);

  Future<String?> getUserId() => _safeRead(_userIdKey);

  Future<void> saveSelectedOrganization(String orgId, String orgName) async {
    await Future.wait([
      _safeWrite(_selectedOrgIdKey, orgId),
      _safeWrite(_selectedOrgNameKey, orgName),
    ]);
  }

  Future<String?> getSelectedOrgId() => _safeRead(_selectedOrgIdKey);

  Future<String?> getSelectedOrgName() => _safeRead(_selectedOrgNameKey);

  Future<void> clearSelectedOrganization() async {
    await Future.wait([
      _safeDelete(_selectedOrgIdKey),
      _safeDelete(_selectedOrgNameKey),
    ]);
  }

  Future<void> clearAll() async {
    try {
      await _storage.deleteAll().timeout(const Duration(seconds: 4));
    } on TimeoutException {
      print('SECURE STORAGE clearAll TIMED OUT');
    } catch (e) {
      print('SECURE STORAGE clearAll FAILED: $e');
    }
  }
}
