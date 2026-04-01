import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../domain/ble_device_model.dart';

final bleConnectorProvider = Provider<BleConnector>((ref) {
  return BleConnector();
});

class BleConnector {
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, StreamSubscription> _connectionSubs = {};
  final Map<String, BluetoothCharacteristic> _writeCharacteristics = {};
  final Map<String, BluetoothCharacteristic> _notifyCharacteristics = {};
  final _stateController =
      StreamController<Map<String, BleConnectionStatus>>.broadcast();
  final Map<String, BleConnectionStatus> _deviceStates = {};
  int _reconnectAttempts = 0;

  Stream<Map<String, BleConnectionStatus>> get connectionStates =>
      _stateController.stream;

  Map<String, BleConnectionStatus> get currentStates =>
      Map.unmodifiable(_deviceStates);

  List<String> get connectedDeviceIds => _connectedDevices.keys.toList();

  /// Connect to a device by its BluetoothDevice reference.
  Future<bool> connect(BluetoothDevice device,
      {bool autoReconnect = true}) async {
    final deviceId = device.remoteId.str;
    appLogger.i('BLE: Connecting to ${device.platformName} ($deviceId)');

    _updateState(deviceId, BleConnectionStatus.connecting);

    try {
      await device.connect(
        timeout: BleConstants.connectionTimeout,
        autoConnect: autoReconnect,
      );

      // Request MTU
      if (device.isConnected) {
        await device.requestMtu(BleConstants.requestedMtu);
      }

      // Discover services
      final services = await device.discoverServices();
      _findCharacteristics(deviceId, services);

      _connectedDevices[deviceId] = device;
      _updateState(deviceId, BleConnectionStatus.connected);
      _reconnectAttempts = 0;

      // Listen for disconnection
      _connectionSubs[deviceId]?.cancel();
      _connectionSubs[deviceId] =
          device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          appLogger.w('BLE: Device $deviceId disconnected');
          _updateState(deviceId, BleConnectionStatus.disconnected);
          _writeCharacteristics.remove(deviceId);
          _notifyCharacteristics.remove(deviceId);

          if (autoReconnect &&
              _reconnectAttempts < BleConstants.maxReconnectAttempts) {
            _attemptReconnect(device);
          }
        }
      });

      // Enable notifications if available
      final notifyChar = _notifyCharacteristics[deviceId];
      if (notifyChar != null) {
        await notifyChar.setNotifyValue(true);
        notifyChar.onValueReceived.listen((value) {
          appLogger.d('BLE: Notification from $deviceId: $value');
        });
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
      _reconnectAttempts = BleConstants.maxReconnectAttempts; // prevent reconnect
      await _connectionSubs[deviceId]?.cancel();
      _connectionSubs.remove(deviceId);
      await device.disconnect();
      _connectedDevices.remove(deviceId);
      _writeCharacteristics.remove(deviceId);
      _notifyCharacteristics.remove(deviceId);
      _updateState(deviceId, BleConnectionStatus.disconnected);
      appLogger.i('BLE: Disconnected from $deviceId');
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

    try {
      await characteristic.write(data, withoutResponse: false);
      appLogger.d('BLE: Wrote ${data.length} bytes to $deviceId');
      return true;
    } catch (e) {
      appLogger.e('BLE: Write failed for $deviceId: $e');
      return false;
    }
  }

  /// Check if a device is connected.
  bool isConnected(String deviceId) =>
      _deviceStates[deviceId] == BleConnectionStatus.connected;

  void _findCharacteristics(
      String deviceId, List<BluetoothService> services) {
    for (final service in services) {
      // Check if this is the Hydrawav3 service
      final serviceUuid = service.uuid.str.toLowerCase();
      if (serviceUuid.contains(
          BleConstants.serviceUuid.toLowerCase().replaceAll('-', ''))) {
        for (final char in service.characteristics) {
          final charUuid = char.uuid.str.toLowerCase();
          if (charUuid.contains(BleConstants.writeCharacteristicUuid
              .toLowerCase()
              .replaceAll('-', ''))) {
            _writeCharacteristics[deviceId] = char;
            appLogger.d('BLE: Found write characteristic for $deviceId');
          }
          if (charUuid.contains(BleConstants.notifyCharacteristicUuid
              .toLowerCase()
              .replaceAll('-', ''))) {
            _notifyCharacteristics[deviceId] = char;
            appLogger.d('BLE: Found notify characteristic for $deviceId');
          }
        }
      }
    }

    // Fallback: if no specific service matched, try to find any writable char
    if (!_writeCharacteristics.containsKey(deviceId)) {
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeCharacteristics[deviceId] = char;
            appLogger.d(
                'BLE: Using fallback write characteristic for $deviceId');
            break;
          }
        }
        if (_writeCharacteristics.containsKey(deviceId)) break;
      }
    }
  }

  Future<void> _attemptReconnect(BluetoothDevice device) async {
    _reconnectAttempts++;
    appLogger.i(
        'BLE: Reconnect attempt $_reconnectAttempts/${BleConstants.maxReconnectAttempts}');

    await Future.delayed(
      BleConstants.reconnectDelay * _reconnectAttempts,
    );

    if (_reconnectAttempts < BleConstants.maxReconnectAttempts) {
      await connect(device);
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
    _stateController.close();
  }
}
