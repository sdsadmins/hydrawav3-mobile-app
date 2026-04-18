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

  // Future<UserProfile> login(LoginRequest request) async {
  //   final tokens = await _remoteSource.login(request);
  //   print("LOGIN TOKEN RAW: ${tokens.accessToken}");
  //   await _secureStorage.saveTokens(
  //     accessToken: tokens.accessToken.replaceAll('Bearer ', ''), // ✅ FIX: Remove 'Bearer ' prefix
  //     refreshToken: tokens.refreshToken.replaceAll('Bearer ', ''), // ✅ FIX: Remove 'Bearer ' prefix
  //   );
  //   print("LOGIN TOKEN: ${tokens.accessToken}");
  //   final profile = await _remoteSource.getProfile();
  //   if (profile.id != null) {
  //     await _secureStorage.saveUserId(profile.id!);
  //   }
  //   return profile;
  // }
  Future<UserProfile> login(LoginRequest request) async {
  final tokens = await _remoteSource.login(request);

  // ✅ DEBUG
  print("LOGIN TOKEN RAW: ${tokens.accessToken}");

  // ✅ REMOVE "Bearer " BEFORE SAVING
  final cleanAccessToken = tokens.accessToken.replaceFirst("Bearer ", "");
  final cleanRefreshToken = tokens.refreshToken.replaceFirst("Bearer ", "");

  await _secureStorage.saveTokens(
    accessToken: cleanAccessToken,
    refreshToken: cleanRefreshToken,
  );

  // ✅ VERIFY SAVE
  final storedToken = await _secureStorage.getAccessToken();
  print("TOKEN AFTER SAVE: $storedToken");

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
  // forgot password
  Future<void> forgotPassword(String id) {
  return _remoteSource.forgotPassword(id);
}
}
