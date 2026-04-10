import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../domain/ble_device_model.dart';

final bleConnectorProvider = Provider<BleConnector>((ref) {
  return BleConnector();
});

class BleNotification {
  final String deviceId;
  final List<int> value;

  const BleNotification({required this.deviceId, required this.value});
}

class BleGattInfo {
  final String? serviceUuid;
  final String? writeUuid;
  final String? notifyUuid;

  const BleGattInfo({
    this.serviceUuid,
    this.writeUuid,
    this.notifyUuid,
  });
}

class BleConnector {
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, StreamSubscription> _connectionSubs = {};
  final Map<String, StreamSubscription> _notifySubs = {};
  final Map<String, BluetoothCharacteristic> _writeCharacteristics = {};
  final Map<String, BluetoothCharacteristic> _notifyCharacteristics = {};
  final Map<String, String> _firmwareSessionIdByDevice = {};
  final _stateController =
      StreamController<Map<String, BleConnectionStatus>>.broadcast();
  final _notificationController =
      StreamController<BleNotification>.broadcast();
  final Map<String, BleConnectionStatus> _deviceStates = {};
  final Map<String, int> _reconnectAttempts = {};
  final Set<String> _manualDisconnects = {};
  final Map<String, Future<bool>> _connectInFlight = {};
  final Map<String, BleGattInfo> _gattInfoByDevice = {};

  Stream<Map<String, BleConnectionStatus>> get connectionStates =>
      _stateController.stream;

  Stream<BleNotification> get notifications => _notificationController.stream;

  Map<String, BleConnectionStatus> get currentStates =>
      Map.unmodifiable(_deviceStates);

  List<String> get connectedDeviceIds => _connectedDevices.keys.toList();
  BleGattInfo? getGattInfo(String deviceId) => _gattInfoByDevice[deviceId];
  String? getFirmwareSessionId(String deviceId) =>
      _firmwareSessionIdByDevice[deviceId];

  /// Connect to a device by its BluetoothDevice reference.
  Future<bool> connect(BluetoothDevice device,
      {bool autoReconnect = true}) async {
    final deviceId = device.remoteId.str;
    final current = _deviceStates[deviceId];
    if (current == BleConnectionStatus.connected) return true;
    if (_connectInFlight.containsKey(deviceId)) {
      return _connectInFlight[deviceId]!;
    }

    _manualDisconnects.remove(deviceId);
    appLogger.i('BLE: Connecting to ${device.platformName} ($deviceId)');

    _updateState(deviceId, BleConnectionStatus.connecting);

    final fut = _connectInternal(device, autoReconnect: autoReconnect);
    _connectInFlight[deviceId] = fut;
    try {
      return await fut;
    } finally {
      _connectInFlight.remove(deviceId);
    }
  }

  Future<bool> _connectInternal(
    BluetoothDevice device, {
    required bool autoReconnect,
  }) async {
    final deviceId = device.remoteId.str;
    try {
      // Scan can interfere with some BLE stacks during CCCD/service discovery.
      // We want a quiet radio while connecting.
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {
        // Ignore: scan might not be running.
      }

      // NOTE: `autoConnect` is unreliable across platforms and can cause
      // confusing states. Prefer explicit connects + our own reconnect loop.
      await device.connect(
        timeout: BleConstants.connectionTimeout,
        autoConnect: false,
      );

      // Many UART-style bridges are flaky if you immediately discover services.
      // This matches the strict flow requested for Hydra devices.
      if (BleConstants.strictHydraGattProfile) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // Request MTU
      if (device.isConnected) {
        await device.requestMtu(BleConstants.requestedMtu);
      }

      // Discover services
      final services = await device.discoverServices();

      // In practice, some Android stacks / plugins may turn on notifications for
      // Bluetooth SIG system characteristics (e.g. Service Changed 0x2A05)
      // during connect / CCCD setup.
      //
      // We explicitly disable those so the only notifications we keep
      // active are the strict Hydra GATT channels we select below.
      if (BleConstants.strictHydraGattProfile) {
        for (final s in services) {
          for (final c in s.characteristics) {
            final normUuid = BleConstants.normalizeUuid(c.uuid.str);
            final canNotify = c.properties.notify || c.properties.indicate;
            if (canNotify && BleConstants.isSystemCharacteristic(normUuid)) {
              appLogger.w(
                'BLE: Disabling system notify for $deviceId char=${c.uuid.str}',
              );
              try {
                await c.setNotifyValue(false);
              } catch (e) {
                // Disabling may fail on some stacks; we still proceed and rely
                // on our strict preferred characteristic binding + logs.
                appLogger.w(
                  'BLE: Failed to disable system notify for $deviceId '
                  'char=${c.uuid.str}: $e',
                );
              }
            }
          }
        }
      }

      // Give the BLE stack time to settle CCCD state before enabling our
      // strict preferred notify characteristic.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _findCharacteristics(deviceId, services);

      _connectedDevices[deviceId] = device;
      _updateState(deviceId, BleConnectionStatus.connected);
      _reconnectAttempts[deviceId] = 0;

      // Listen for disconnection
      _connectionSubs[deviceId]?.cancel();
      _connectionSubs[deviceId] =
          device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          appLogger.w('BLE: Device $deviceId disconnected');
          _updateState(deviceId, BleConnectionStatus.disconnected);
          _writeCharacteristics.remove(deviceId);
          _notifyCharacteristics.remove(deviceId);
          _notifySubs[deviceId]?.cancel();
          _notifySubs.remove(deviceId);
          _connectedDevices.remove(deviceId);
          _gattInfoByDevice.remove(deviceId);
          _firmwareSessionIdByDevice.remove(deviceId);

          if (!autoReconnect) return;
          if (_manualDisconnects.contains(deviceId)) return;

          final attempts = (_reconnectAttempts[deviceId] ?? 0);
          if (attempts < BleConstants.maxReconnectAttempts) {
            _attemptReconnect(deviceId, device);
          }
        }
      });

      // Enable notifications if available
      final notifyChar = _notifyCharacteristics[deviceId];
      if (notifyChar != null) {
        if (BleConstants.strictHydraGattProfile &&
            BleConstants.preferredNotifyCharacteristicUuid != null) {
          String n(String s) => s.toLowerCase().replaceAll('-', '');
          final expected = n(BleConstants.preferredNotifyCharacteristicUuid!);
          final actual = n(notifyChar.uuid.str);

          appLogger.d(
            'BLE: Strict notify binding check for $deviceId '
            '(expected=$expected, actual=${notifyChar.uuid.str})',
          );

          if (actual != expected) {
            throw Exception(
              'BLE: Strict profile enabled, but notify UUID mismatch '
              '(expected=$expected actual=${notifyChar.uuid.str})',
            );
          }
        }

        appLogger.i(
          'BLE: FINAL NOTIFY UUID = ${notifyChar.uuid.str} '
          '(deviceId=$deviceId)',
        );

        // Android may "re-enable" system notifications right after we start
        // writing CCCDs. Defensive: disable them again just before enabling
        // the preferred notify.
        if (BleConstants.strictHydraGattProfile) {
          for (final s in services) {
            for (final c in s.characteristics) {
              final normUuid = BleConstants.normalizeUuid(c.uuid.str);
              final canNotify = c.properties.notify || c.properties.indicate;
              if (canNotify &&
                  BleConstants.isSystemCharacteristic(normUuid) &&
                  c.uuid.str != notifyChar.uuid.str) {
                try {
                  await c.setNotifyValue(false);
                } catch (_) {
                  // Ignore; disabling is best-effort.
                }
              }
            }
          }
        }

        // Enable notify on the strict preferred characteristic.
        await notifyChar.setNotifyValue(true);
        // Let the bridge/firmware + Android BLE stack finish CCCD setup.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _notifySubs[deviceId]?.cancel();
        _notifySubs[deviceId] = notifyChar.onValueReceived.listen((value) {
          _notificationController.add(
            BleNotification(deviceId: deviceId, value: value),
          );
          _tryCaptureFirmwareSessionId(deviceId, value);
          appLogger.d('BLE: Notification from $deviceId: $value');
        }, onError: (e) {
          appLogger.e('BLE: Notification stream error for $deviceId: $e');
        });
      } else {
        if (BleConstants.strictHydraGattProfile &&
            BleConstants.preferredNotifyCharacteristicUuid != null) {
          throw Exception(
            'BLE: Strict profile enabled, but no NOTIFY characteristic found '
            'for $deviceId (expected=${BleConstants.preferredNotifyCharacteristicUuid})',
          );
        }
      }

      appLogger.i('BLE: Connected to ${device.platformName}');
      return true;
    } catch (e) {
      appLogger.e('BLE: Connection failed for $deviceId: $e');
      _updateState(deviceId, BleConnectionStatus.error);
      return false;
    }
  }

  /// Disconnect a specific device.
  Future<void> disconnect(String deviceId) async {
    final device = _connectedDevices[deviceId];
    if (device != null) {
      _manualDisconnects.add(deviceId);
      _reconnectAttempts[deviceId] = BleConstants.maxReconnectAttempts;
      await _connectionSubs[deviceId]?.cancel();
      _connectionSubs.remove(deviceId);
      await _notifySubs[deviceId]?.cancel();
      _notifySubs.remove(deviceId);
      await device.disconnect();
      _connectedDevices.remove(deviceId);
      _writeCharacteristics.remove(deviceId);
      _notifyCharacteristics.remove(deviceId);
      _gattInfoByDevice.remove(deviceId);
      _firmwareSessionIdByDevice.remove(deviceId);
      _updateState(deviceId, BleConnectionStatus.disconnected);
      appLogger.i('BLE: Disconnected from $deviceId');
    }
  }

  void _tryCaptureFirmwareSessionId(String deviceId, List<int> value) {
    if (_firmwareSessionIdByDevice.containsKey(deviceId)) return;

    // Heuristic: many UART bridges send ASCII/JSON. Try to parse:
    // 1) {"deviceId":"64Fd...=="} or {"id":"64Fd...=="} or similar
    // 2) {"64Fd...==": {...}} (the "Map key" format)
    try {
      final s = utf8.decode(value, allowMalformed: true).trim();
      if (s.isEmpty) return;

      final decoded = jsonDecode(s);
      if (decoded is Map) {
        // Map-key format: {"64Fd...==": {...}}
        if (decoded.length == 1) {
          final k = decoded.keys.first;
          if (k is String && k.contains('==') && k.length >= 10) {
            _firmwareSessionIdByDevice[deviceId] = k;
            appLogger.i('BLE: [$deviceId] Captured firmware deviceId (map key) = $k');
            return;
          }
        }

        // Field format: {"deviceId":"64Fd...=="}
        for (final field in const ['deviceId', 'id', 'device_id']) {
          final v = decoded[field];
          if (v is String && v.contains('==') && v.length >= 10) {
            _firmwareSessionIdByDevice[deviceId] = v;
            appLogger.i('BLE: [$deviceId] Captured firmware deviceId ($field) = $v');
            return;
          }
        }
      }
    } catch (_) {
      // Ignore: not JSON / not UTF8.
    }
  }

  /// Disconnect all devices.
  Future<void> disconnectAll() async {
    final ids = _connectedDevices.keys.toList();
    for (final id in ids) {
      await disconnect(id);
    }
  }

  /// Write data to a device's write characteristic.
  Future<bool> writeToDevice(String deviceId, List<int> data) async {
    final characteristic = _writeCharacteristics[deviceId];
    if (characteristic == null) {
      appLogger.e('BLE: No write characteristic for $deviceId');
      return false;
    }

    // Log writes at INFO so they're visible even when debug logs are filtered.
    // Include UUID + small preview to make it obvious a write really happened.
    final previewLen = data.length < 80 ? data.length : 80;
    final preview = data.take(previewLen).toList();
    appLogger.i(
      'BLE: Writing ${data.length} bytes to $deviceId '
      '(char=${characteristic.uuid.str}, preview=$preview${data.length > previewLen ? '…' : ''})',
    );

    Future<void> sendInChunks(bool withoutResponse) async {
      // UART-style BLE bridges are usually stable with 20-byte chunks.
      // Keep small pacing delay to prevent RX buffer overflow.
      const chunkSize = 20;
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        final chunk = data.sublist(i, end);
        await characteristic.write(chunk, withoutResponse: withoutResponse);
        // Pacing delay is critical for some firmwares.
        if (end < data.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    final primaryMode = BleConstants.preferWriteWithoutResponse;
    try {
      await sendInChunks(primaryMode);
      appLogger.i(
        'BLE: Wrote ${data.length} bytes to $deviceId '
        '(withoutResponse=$primaryMode)',
      );
      return true;
    } catch (e) {
      appLogger.w(
        'BLE: Write failed for $deviceId (withoutResponse=$primaryMode): $e',
      );
      if (!BleConstants.retryWithOppositeWriteModeOnFailure) {
        return false;
      }
      final fallbackMode = !primaryMode;
      try {
        await sendInChunks(fallbackMode);
        appLogger.i(
          'BLE: Write retry succeeded for $deviceId '
          '(withoutResponse=$fallbackMode)',
        );
        return true;
      } catch (e2) {
        appLogger.e(
          'BLE: Write retry failed for $deviceId '
          '(withoutResponse=$fallbackMode): $e2',
        );
        return false;
      }
    }
  }

  /// Check if a device is connected.
  bool isConnected(String deviceId) =>
      _deviceStates[deviceId] == BleConnectionStatus.connected;

  void _findCharacteristics(
      String deviceId, List<BluetoothService> services) {
    // Prevent stale UUID matches from a previous connection attempt.
    _writeCharacteristics.remove(deviceId);
    _notifyCharacteristics.remove(deviceId);
    _gattInfoByDevice.remove(deviceId);

    String? selectedServiceUuid;
    String? selectedWriteUuid;
    String? selectedNotifyUuid;
    String n(String s) => s.toLowerCase().replaceAll('-', '');
    final preferredService =
        BleConstants.preferredServiceUuid == null
            ? null
            : n(BleConstants.preferredServiceUuid!);
    final preferredWrite =
        BleConstants.preferredWriteCharacteristicUuid == null
            ? null
            : n(BleConstants.preferredWriteCharacteristicUuid!);
    final preferredNotify =
        BleConstants.preferredNotifyCharacteristicUuid == null
            ? null
            : n(BleConstants.preferredNotifyCharacteristicUuid!);

    // -------------------------------------------------------------------------
    // [GATT DUMP] — logged at INFO so it is always visible in the console.
    // Read these lines to find the correct write / notify UUIDs, then set
    // BleConstants.preferredWriteCharacteristicUuid and
    // BleConstants.preferredNotifyCharacteristicUuid accordingly.
    // -------------------------------------------------------------------------
    appLogger.i('BLE: [$deviceId] ════════════ [GATT DUMP START] ════════════');
    appLogger.i('BLE: [$deviceId] Total services discovered: ${services.length}');
    for (final s in services) {
      appLogger.i('BLE: [$deviceId] ┌─ SERVICE: ${s.uuid.str}');
      for (final c in s.characteristics) {
        final canWrite =
            c.properties.write || c.properties.writeWithoutResponse;
        if (canWrite) {
          // TEMP: explicit listing of write-capable characteristics so you
          // can manually test which WRITE UUID actually works.
          appLogger.i('BLE: [$deviceId] 🔥 TEST WRITE CHAR: ${c.uuid.str}');
        }
        final canNotify = c.properties.notify || c.properties.indicate;
        final normUuid = c.uuid.str.toLowerCase().replaceAll('-', '');
        final isSystem = BleConstants.isSystemCharacteristic(normUuid);
        final flags = [
          if (canWrite) 'WRITE',
          if (c.properties.writeWithoutResponse) 'WRITE_NO_RSP',
          if (canNotify) 'NOTIFY',
          if (c.properties.indicate) 'INDICATE',
          if (c.properties.read) 'READ',
          if (isSystem) '⚠️ SYSTEM — will be skipped in fallback',
        ].join(' | ');
        appLogger.i(
          'BLE: [$deviceId] │   CHAR: ${c.uuid.str}  [$flags]',
        );
      }
      appLogger.i('BLE: [$deviceId] └───────────────────────────────────────');
    }
    appLogger.i('BLE: [$deviceId] ════════════ [GATT DUMP END] ══════════════');

    // Prefer exact UUID matches when provided.
    if (preferredService != null ||
        preferredWrite != null ||
        preferredNotify != null) {
      for (final service in services) {
        final serviceUuid = n(service.uuid.str);
        if (preferredService != null && serviceUuid != preferredService) continue;
        for (final char in service.characteristics) {
          final charUuid = n(char.uuid.str);
          if (preferredWrite != null && charUuid == preferredWrite) {
            _writeCharacteristics[deviceId] = char;
            selectedServiceUuid = service.uuid.str;
            selectedWriteUuid = char.uuid.str;
            appLogger.d('BLE: Found preferred write characteristic for $deviceId');
          }
          if (preferredNotify != null && charUuid == preferredNotify) {
            final canNotify = char.properties.notify || char.properties.indicate;
            if (!canNotify) {
              appLogger.w(
                'BLE: Preferred notify UUID matched but is not notifiable: ${char.uuid.str}',
              );
            } else {
              _notifyCharacteristics[deviceId] = char;
              selectedServiceUuid ??= service.uuid.str;
              selectedNotifyUuid = char.uuid.str;
              appLogger.d('BLE: Found preferred notify characteristic for $deviceId');
            }
          }
        }
      }
    }

    // STRICT MODE: no fallback selection. Fail fast if exact UUIDs not found.
    if (BleConstants.strictHydraGattProfile) {
      final missing = <String>[];
      if (preferredService == null) missing.add('preferredServiceUuid');
      if (preferredWrite == null) missing.add('preferredWriteCharacteristicUuid');
      if (preferredNotify == null) missing.add('preferredNotifyCharacteristicUuid');
      if (missing.isNotEmpty) {
        throw Exception(
          'BLE: Strict GATT profile is enabled but missing constants: ${missing.join(', ')}',
        );
      }

      final hasWrite = _writeCharacteristics.containsKey(deviceId);
      final hasNotify = _notifyCharacteristics.containsKey(deviceId);
      if (!hasWrite || !hasNotify) {
        throw Exception(
          'BLE: Strict GATT profile mismatch for $deviceId. '
          'Expected service=${BleConstants.preferredServiceUuid}, '
          'write=${BleConstants.preferredWriteCharacteristicUuid}, '
          'notify=${BleConstants.preferredNotifyCharacteristicUuid}. '
          'Found write=$selectedWriteUuid notify=$selectedNotifyUuid',
        );
      }

      _gattInfoByDevice[deviceId] = BleGattInfo(
        serviceUuid: selectedServiceUuid,
        writeUuid: selectedWriteUuid,
        notifyUuid: selectedNotifyUuid,
      );
      appLogger.i(
        'BLE: [$deviceId] Selected GATT UUIDs (strict): '
        'service=$selectedServiceUuid write=$selectedWriteUuid notify=$selectedNotifyUuid',
      );
      return;
    }

    // Fallback: if no specific service matched, try to find any writable char.
    // ⚠️  Skip Bluetooth SIG system characteristics (e.g. 0x2A05 Service
    //     Changed) — writing to them achieves nothing and masks the real bug.
    if (!_writeCharacteristics.containsKey(deviceId)) {
      for (final service in services) {
        for (final char in service.characteristics) {
          final normUuid = char.uuid.str.toLowerCase().replaceAll('-', '');
          if (BleConstants.isSystemCharacteristic(normUuid)) {
            appLogger.w(
              'BLE: [$deviceId] Fallback skipping SYSTEM char ${char.uuid.str}',
            );
            continue;
          }
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeCharacteristics[deviceId] = char;
            selectedServiceUuid ??= service.uuid.str;
            selectedWriteUuid = char.uuid.str;
            appLogger.i(
              'BLE: [$deviceId] Fallback selected WRITE char: ${char.uuid.str}',
            );
            break;
          }
        }
        if (_writeCharacteristics.containsKey(deviceId)) break;
      }
    }

    // Fallback: pick first notifiable/indicatable characteristic.
    // ⚠️  Same system-char guard applies here.
    if (!_notifyCharacteristics.containsKey(deviceId)) {
      for (final service in services) {
        for (final char in service.characteristics) {
          final normUuid = char.uuid.str.toLowerCase().replaceAll('-', '');
          if (BleConstants.isSystemCharacteristic(normUuid)) {
            appLogger.w(
              'BLE: [$deviceId] Fallback skipping SYSTEM char ${char.uuid.str}',
            );
            continue;
          }
          if (char.properties.notify || char.properties.indicate) {
            _notifyCharacteristics[deviceId] = char;
            selectedServiceUuid ??= service.uuid.str;
            selectedNotifyUuid = char.uuid.str;
            appLogger.i(
              'BLE: [$deviceId] Fallback selected NOTIFY char: ${char.uuid.str}',
            );
            break;
          }
        }
        if (_notifyCharacteristics.containsKey(deviceId)) break;
      }
    }

    if (!_writeCharacteristics.containsKey(deviceId)) {
      appLogger.w('BLE: No writable characteristic discovered for $deviceId');
    }

    _gattInfoByDevice[deviceId] = BleGattInfo(
      serviceUuid: selectedServiceUuid,
      writeUuid: selectedWriteUuid,
      notifyUuid: selectedNotifyUuid,
    );
    appLogger.i(
      'BLE: [$deviceId] Selected GATT UUIDs: '
      'service=$selectedServiceUuid write=$selectedWriteUuid notify=$selectedNotifyUuid',
    );
  }

  Future<void> _attemptReconnect(String deviceId, BluetoothDevice device) async {
    final next = (_reconnectAttempts[deviceId] ?? 0) + 1;
    _reconnectAttempts[deviceId] = next;
    appLogger.i(
        'BLE: Reconnect attempt $next/${BleConstants.maxReconnectAttempts} for $deviceId');

    await Future.delayed(
      BleConstants.reconnectDelay * next,
    );

    if (_manualDisconnects.contains(deviceId)) return;
    if ((_reconnectAttempts[deviceId] ?? 0) < BleConstants.maxReconnectAttempts) {
      await connect(device, autoReconnect: true);
    }
  }

  void _updateState(String deviceId, BleConnectionStatus status) {
    _deviceStates[deviceId] = status;
    _stateController.add(Map.from(_deviceStates));
  }

  void dispose() {
    for (final sub in _connectionSubs.values) {
      sub.cancel();
    }
    for (final sub in _notifySubs.values) {
      sub.cancel();
    }
    _stateController.close();
    _notificationController.close();
  }
}
