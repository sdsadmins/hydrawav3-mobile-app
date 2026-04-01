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
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    return canCheck && isSupported;
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    return await _auth.getAvailableBiometrics();
  }

  Future<bool> authenticate() async {
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
    return await _secureStorage.isBiometricEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    await _secureStorage.setBiometricEnabled(enabled);
  }
}
