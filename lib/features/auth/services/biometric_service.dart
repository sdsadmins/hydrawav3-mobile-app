import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/storage/secure_storage.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService(ref.read(secureStorageProvider));
});

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final SecureStorageService _secureStorage;

  BiometricService(this._secureStorage);

  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticate() async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to access Hydrawav3',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _secureStorage.isBiometricEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      await _secureStorage.setBiometricEnabled(enabled);
    } catch (_) {
      // Ignore on web
    }
  }
}
