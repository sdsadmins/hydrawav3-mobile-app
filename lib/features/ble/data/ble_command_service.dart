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
    final success = await _bleRepository.writeJsonToDevice(
      deviceId,
      {
        'type': 'RENAME',
        'name': name,
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

    Future<bool> tryWriteOnce() async {
      try {
        await ensureConnected();
      } catch (_) {
        return false;
      }
      return _bleRepository.writeJsonToDevice(deviceId, payload);
    }

    // Attempt write up to 2 times. If first fails, reconnect then retry.
    var writeOk = await tryWriteOnce();
    if (!writeOk) {
      try {
        await _bleRepository.disconnectDevice(deviceId);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      writeOk = await tryWriteOnce();
    }
    if (!writeOk) return false;

    // Many firmwares disconnect immediately after receiving WiFi creds.
    // ACK timeout is NOT considered a failure if the write succeeded.
    try {
      await _connector.waitForConfigAck(deviceId, timeout: timeout);
    } catch (_) {
      // Ignore: disconnections/timeouts after send are expected.
    }
    return true;
  }

  Future<String?> resolveHardwareMac(
    String deviceId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
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

      final resolved = await completer.future.timeout(
        timeout,
        onTimeout: () => _extractMacFromText(deviceId),
      );
      return resolved ?? _extractMacFromText(deviceId);
    } finally {
      await sub.cancel();
    }
  }
}
