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
    await _secureStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    final profile = await _remoteSource.getProfile();
    if (profile.id != null) {
      await _secureStorage.saveUserId(profile.id!);
    }
    return profile;
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

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _remoteSource.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }
}
