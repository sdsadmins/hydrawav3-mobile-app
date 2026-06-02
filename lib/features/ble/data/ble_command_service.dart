import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_connector.dart';
import 'ble_repository.dart';

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
