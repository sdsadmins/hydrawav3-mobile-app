import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_connector.dart';
import 'ble_repository.dart';

/// Raised when a lease BLE command cannot proceed for a device-identity
/// reason (wrong device, or the firmware MAC could not be resolved). Carries a
/// user-facing [message] the lease UI can show verbatim.
class LeaseCommandException implements Exception {
  final String message;
  const LeaseCommandException(this.message);

  @override
  String toString() => message;
}

final bleCommandServiceProvider = Provider<BleCommandService>((ref) {
  return BleCommandService(
    bleRepository: ref.read(bleRepositoryProvider),
    connector: ref.read(bleConnectorProvider),
  );
});

class BleCommandService {
  final BleRepository _bleRepository;
  final BleConnector _connector;

  BleCommandService({
    required BleRepository bleRepository,
    required BleConnector connector,
  })  : _bleRepository = bleRepository,
        _connector = connector;

  static final RegExp _macRegex =
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
  static final RegExp _macSearchRegex =
      RegExp(r'([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}');

  String? _extractMacFromText(String text) {
    final trimmed = text.trim();
    if (_macRegex.hasMatch(trimmed)) {
      return trimmed.toUpperCase();
    }

    final inlineMatch = _macSearchRegex.firstMatch(trimmed);
    if (inlineMatch != null) {
      return inlineMatch.group(0)?.toUpperCase();
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        for (final key in const ['mac', 'macAddress', 'deviceMac']) {
          final raw = decoded[key];
          if (raw is String) {
            final value = raw.trim();
            if (_macRegex.hasMatch(value)) {
              return value.toUpperCase();
            }
            final nestedMatch = _macSearchRegex.firstMatch(value);
            if (nestedMatch != null) {
              return nestedMatch.group(0)?.toUpperCase();
            }
          }
        }
      }
    } catch (_) {
      // Ignore malformed/non-JSON notification payloads.
    }

    return null;
  }

  Future<bool> sendRename(String deviceId, String name) async {
    // Web parity: firmware renames via BLUETOOTH_NAME / bluetoothName
    // (see web useBleSession.setDevicename). A "RENAME"/"name" payload is
    // ignored by the device.
    final bluetoothName = name.startsWith('Hydra-') ? name : 'Hydra-$name';
    final success = await _bleRepository.writeJsonToDevice(
      deviceId,
      {
        'type': 'BLUETOOTH_NAME',
        'bluetoothName': bluetoothName,
      },
    );
    if (!success) return false;

    return _connector.waitForConfigAck(deviceId);
  }

  Future<bool> sendWifiCredentials(
    String deviceId, {
    required String ssid,
    required String password,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final payload = {
      'type': 'SET_WIFI',
      'ssid': ssid,
      'password': password,
    };

    // Web parity: ensure connection is active right before sending.
    // On Android, GATT 133 can happen if we write too quickly after connect.
    Future<void> ensureConnected() async {
      if (_connector.isConnected(deviceId)) return;
      final ok = await _bleRepository.connectDevice(
        BluetoothDevice(remoteId: DeviceIdentifier(deviceId)),
        cachePairedDevice: false,
      );
      if (!ok) {
        throw Exception('BLE connect failed for $deviceId');
      }
      // Let the stack settle after service discovery / CCCD changes.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    try {
      await ensureConnected();
    } catch (_) {
      return false;
    }

    // Web parity (useBleSession.setWifi / handleUpdateWifi): the device almost
    // always drops the BLE link the instant it accepts the credentials
    // (GATT 133 / LINK_SUPERVISION_TIMEOUT). The web app treats that disconnect
    // as a SUCCESS — the creds were delivered and the device is switching to
    // WiFi. So we disable the GATT-133 reconnect recovery (it would just waste
    // ~12s reconnecting to a device that has left BLE) and interpret a
    // post-write disconnect as success.
    final writeOk = await _bleRepository.writeJsonToDevice(
      deviceId,
      payload,
      recoverOnGatt133: false,
    );

    if (writeOk) {
      // ACK timeout is NOT a failure — many firmwares never ACK before leaving.
      try {
        await _connector.waitForConfigAck(deviceId, timeout: timeout);
      } catch (_) {}
      return true;
    }

    // The write reported failure — but the device almost always drops the BLE
    // link the instant it accepts the credentials (GATT 133 /
    // LINK_SUPERVISION_TIMEOUT), and that disconnect event can arrive a few
    // hundred ms AFTER the write throws. So poll briefly: if the device leaves
    // BLE, the creds were delivered and we treat it as success (web parity).
    for (var i = 0; i < 8; i++) {
      if (!_connector.isConnected(deviceId)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    return false;
  }

  /// Load a lease ID onto the connected device (web parity: `setLeaseId`).
  ///
  /// Sends `{cmd:"setLeaseID", id:<leaseId>}`. When [expectedMac] is provided,
  /// the device's firmware-reported MAC must match first (same-device safety).
  /// Resolving the MAC via [resolveHardwareMac] — not the BLE id — is what makes
  /// this work on iOS, where the BLE identifier is an opaque UUID.
  ///
  /// Confirmation is BEST-EFFORT: some Hydra firmware builds accept the command
  /// silently and never send a `leaseSet` frame (confirmed on Hydra-56 — the
  /// 60-byte write completes with no GATT error, then nothing on either notify
  /// channel). So a successful write is treated as success; the ack, when it
  /// arrives, is a fast-path confirmation only. Mirrors [sendWifiCredentials],
  /// which the firmware also doesn't reliably ACK. Throws [LeaseCommandException]
  /// only on a MAC mismatch so the UI can show a precise "wrong device" message.
  Future<bool> setLeaseId(
    String deviceId,
    String leaseId, {
    String? expectedMac,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _verifyDeviceMac(deviceId, expectedMac);

    final writeOk = await _bleRepository.writeJsonToDevice(
      deviceId,
      {'cmd': 'setLeaseID', 'id': leaseId},
    );
    if (!writeOk) return false;

    // Give the firmware a brief window to confirm, but don't fail if it stays
    // silent — the write already reached the device.
    await _connector.waitForLeaseAck(
      deviceId,
      tokens: const {'leaseset', 'lease_set'},
      timeout: const Duration(milliseconds: 2500),
    );
    return true;
  }

  /// Clear a lease ID from the connected device (web parity: `clearLeaseId`).
  ///
  /// Sends `{cmd:"clearLeaseID", id:<leaseId>}`. Best-effort confirmation and
  /// same [expectedMac] safety rule as [setLeaseId].
  Future<bool> clearLeaseId(
    String deviceId,
    String leaseId, {
    String? expectedMac,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _verifyDeviceMac(deviceId, expectedMac);

    final writeOk = await _bleRepository.writeJsonToDevice(
      deviceId,
      {'cmd': 'clearLeaseID', 'id': leaseId},
    );
    if (!writeOk) return false;

    await _connector.waitForLeaseAck(
      deviceId,
      tokens: const {'leasecleared', 'lease_cleared'},
      timeout: const Duration(milliseconds: 2500),
    );
    return true;
  }

  /// Ensure the connected device is the one the lease was registered against.
  /// No-op when [expectedMac] is null/empty. Tolerates the Hydra "BLE MAC ±1"
  /// quirk (the advertised/BLE address differs from the firmware MAC by one on
  /// the last octet). Throws [LeaseCommandException] on a real mismatch, or when
  /// the firmware MAC can't be resolved (common on iOS if the device never
  /// published its MAC yet).
  Future<void> _verifyDeviceMac(String deviceId, String? expectedMac) async {
    if (expectedMac == null || expectedMac.trim().isEmpty) return;
    final actual = await resolveHardwareMac(deviceId);
    if (actual == null) {
      throw const LeaseCommandException(
        'Could not read the device MAC. Reconnect and try again.',
      );
    }
    if (!_macsEquivalent(actual, expectedMac.trim())) {
      throw LeaseCommandException(
        'This is not the registered device (expected '
        '${expectedMac.toUpperCase()}, found ${actual.toUpperCase()}).',
      );
    }
  }

  /// True if two MACs identify the same Hydra unit: an exact match, or a match
  /// on the first five octets with the last octet differing by at most 1 (the
  /// documented BLE-vs-firmware MAC ±1 offset).
  bool _macsEquivalent(String a, String b) {
    final na = a.toUpperCase().replaceAll('-', ':');
    final nb = b.toUpperCase().replaceAll('-', ':');
    if (na == nb) return true;
    final pa = na.split(':');
    final pb = nb.split(':');
    if (pa.length != 6 || pb.length != 6) return false;
    for (var i = 0; i < 5; i++) {
      if (pa[i] != pb[i]) return false;
    }
    final la = int.tryParse(pa[5], radix: 16);
    final lb = int.tryParse(pb[5], radix: 16);
    if (la == null || lb == null) return false;
    return (la - lb).abs() <= 1;
  }

  Future<String?> resolveHardwareMac(
    String deviceId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Web parity (`getMacFromDevice` / `lastMacRef`): the firmware usually
    // publishes its MAC right after connect — before this call runs. The
    // connector caches any MAC seen on the notify channel, so prefer that.
    // This is what makes iOS work: there the BLE `deviceId` is an opaque UUID,
    // so the `_extractMacFromText(deviceId)` fallback below yields null and the
    // only real source of the MAC is the firmware notification.
    final cached = _connector.getHardwareMac(deviceId);
    if (cached != null && _macRegex.hasMatch(cached)) {
      return cached;
    }

    StreamSubscription<BleNotification>? sub;
    final completer = Completer<String?>();

    void completeIfNeeded(String? mac) {
      if (!completer.isCompleted) {
        completer.complete(mac);
      }
    }

    sub = _connector.notifications.listen((notification) {
      if (notification.deviceId != deviceId || completer.isCompleted) return;
      final payload =
          utf8.decode(notification.value, allowMalformed: true).trim();
      if (payload.isEmpty) return;
      final extracted = _extractMacFromText(payload);
      if (extracted != null) {
        completeIfNeeded(extracted);
      }
    });

    try {
      // Mirror web flow: trigger firmware MAC publish with BLUETOOTH_NAME first.
      final requestedByName = await _bleRepository.writeJsonToDevice(
        deviceId,
        {
          'type': 'BLUETOOTH_NAME',
          'bluetoothName': 'Hydra-Mobile',
        },
      );

      if (!completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      final requestedByInfo = await _bleRepository.writeJsonToDevice(
        deviceId,
        {'type': 'GET_DEVICE_INFO'},
      );

      if (!requestedByName && !requestedByInfo) {
        // Fallback to BLE address when firmware commands cannot be sent.
        completeIfNeeded(_extractMacFromText(deviceId));
      }

      // On timeout, re-check the connector cache (the MAC may have arrived on
      // the notify channel while we were sending the trigger writes), then fall
      // back to the BLE id. That fallback yields a MAC on Android but null on
      // iOS — which is correct: iOS has no usable MAC fallback.
      final resolved = await completer.future.timeout(
        timeout,
        onTimeout: () =>
            _connector.getHardwareMac(deviceId) ??
            _extractMacFromText(deviceId),
      );
      return resolved ??
          _connector.getHardwareMac(deviceId) ??
          _extractMacFromText(deviceId);
    } finally {
      await sub.cancel();
    }
  }
}
