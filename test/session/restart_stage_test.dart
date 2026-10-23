// [R4-42] "Restart this stage" fails.
//
// SessionScreen._restartStage (lib/features/session/presentation/screens/
// session_screen.dart:3283) awaits ProtocolPlusController.restartCurrentProtocol
// and, when it returns false, shows the red SnackBar
// `'Could not restart $stageLabel — try again'`; the local engine is never
// touched on that path (the device write + timer resync only ever arrive via
// the server's START_PROTOCOL event on SUCCESS), so the session stays running
// and the stage timer is not reset.
//
// SessionScreen needs a live SessionEngine, BLE/MQTT and the Plus socket, so
// this pins the controller contract the screen relies on: a failed restart
// resolves to `false` (never throws, never changes engine state) and the
// screen's message is built from that. Bindings can only be installed by
// `connectAll`, which opens the `/sessions` socket, so the reachable failure
// here is the unbound-device one; the HTTP 500 branch returns the same false.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/network/dio_client.dart';
import 'package:hydrawav3/core/storage/secure_storage.dart';
import 'package:hydrawav3/features/session/services/protocol_plus_controller.dart';

import '../helpers/fake_http.dart';

class _FakeStorage implements SecureStorageService {
  @override
  Future<String?> getAccessToken() async => 'Bearer t';
  @override
  Future<String?> getUserId() async => '7';
  @override
  Future<String?> getSelectedOrgId() async => '1';
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('[R4-42] restart stage failure', () {
    test('[R4-42] a failed restart resolves false and sends nothing further',
        () async {
      final server = FakeHttp()
        ..onStatus('POST', RegExp(r'protocol-plus/.*/restart$'), 500);
      final container = ProviderContainer(overrides: [
        nodeDioProvider.overrideWithValue(server.dio()),
        secureStorageProvider.overrideWithValue(_FakeStorage()),
      ]);
      addTearDown(container.dispose);

      final controller = container.read(protocolPlusControllerProvider);

      // No exception reaches the screen — it gets a plain `false` to show the
      // "Could not restart" SnackBar from.
      final ok = await controller.restartCurrentProtocol('AA:BB:CC:DD:EE:01');
      expect(ok, isFalse);

      // Nothing was written to the device path on failure: no PLAY/config
      // re-send goes through the API from this call, so the running timer is
      // left alone.
      expect(
        server.requests.where((r) => !r.path.contains('/restart')),
        isEmpty,
      );
    });
  });
}
