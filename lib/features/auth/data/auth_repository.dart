import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../domain/auth_models.dart';
import 'auth_remote_source.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    remoteSource: ref.read(authRemoteSourceProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
});

class AuthRepository {
  final AuthRemoteSource _remoteSource;
  final SecureStorageService _secureStorage;

  AuthRepository({
    required AuthRemoteSource remoteSource,
    required SecureStorageService secureStorage,
  })  : _remoteSource = remoteSource,
        _secureStorage = secureStorage;

  Future<UserProfile> login(LoginRequest request) async {
    final tokens = await _remoteSource.login(request);
    print("LOGIN TOKEN RAW: ${tokens.accessToken}");

    final cleanAccessToken = tokens.accessToken.replaceFirst("Bearer ", "");
    final cleanRefreshToken = tokens.refreshToken.replaceFirst("Bearer ", "");

    // Reset any stale auth state before writing the fresh session.
    await _secureStorage.clearTokens();
    await _secureStorage.saveTokens(
      accessToken: cleanAccessToken,
      refreshToken: cleanRefreshToken,
    );

    final profile = await _loadProfileAfterLogin(
      accessToken: cleanAccessToken,
      refreshToken: cleanRefreshToken,
    );

    if (profile.id != null) {
      await _secureStorage.saveUserId(profile.id!);
    }

    return profile;
  }

  Future<UserProfile> _loadProfileAfterLogin({
    required String accessToken,
    required String refreshToken,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      final delayMs = attempt == 0 ? 500 : 1000;
      await Future<void>.delayed(Duration(milliseconds: delayMs));

      final storedToken = await _secureStorage.getAccessToken();
      print("TOKEN AFTER SAVE [attempt ${attempt + 1}]: $storedToken");

      if (storedToken == null || storedToken.isEmpty) {
        print("TOKEN MISSING AFTER SAVE, REWRITING TOKENS");
        await _secureStorage.clearTokens();
        await _secureStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
        continue;
      }

      try {
        return await _remoteSource.getProfile();
      } catch (e) {
        lastError = e;
        print("PROFILE FETCH FAILED AFTER LOGIN [attempt ${attempt + 1}]: $e");

        if (attempt == 0) {
          await _secureStorage.clearTokens();
          await _secureStorage.saveTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
        }
      }
    }

    throw lastError ?? Exception('Failed to load profile after login');
  }

  Future<void> logout() async {
    await _secureStorage.clearAll();
  }

  Future<bool> isLoggedIn() async {
    return await _secureStorage.hasTokens();
  }

  Future<UserProfile> getProfile() async {
    return await _remoteSource.getProfile();
  }

  Future<UserProfile> updateProfile(Map<String, dynamic> data) async {
    return await _remoteSource.updateProfile(data);
  }

  Future<List<Map<String, dynamic>>> getOrganizations() async {
    final response = await _remoteSource.getOrganizations();
    return response;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _remoteSource.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  Future<void> forgotPassword(String id) {
    return _remoteSource.forgotPassword(id);
  }

  Future<void> saveSelectedOrganization(String orgId, String orgName) async {
    await _secureStorage.saveSelectedOrganization(orgId, orgName);
  }

  Future<String?> getSelectedOrgId() async {
    return await _secureStorage.getSelectedOrgId();
  }

  Future<String?> getSelectedOrgName() async {
    return await _secureStorage.getSelectedOrgName();
  }

  Future<void> clearSelectedOrganization() async {
    await _secureStorage.clearSelectedOrganization();
  }
}
