import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/ble_command.dart';
import 'ble_connector.dart';

final bleTreatmentWriterProvider = Provider<BleTreatmentWriter>((ref) {
  return BleTreatmentWriter(
    connector: ref.read(bleConnectorProvider),
    deviceDio: ref.read(deviceDioProvider),
    djangoDio: ref.read(djangoDioProvider),
  );
});

/// Writes treatment commands to devices via BLE (primary),
/// HTTP fallback, or MQTT fallback.
class BleTreatmentWriter {
  final BleConnector _connector;
  final Dio _deviceDio;
  final Dio _djangoDio;

  BleTreatmentWriter({
    required BleConnector connector,
    required Dio deviceDio,
    required Dio djangoDio,
  })  : _connector = connector,
        _deviceDio = deviceDio,
        _djangoDio = djangoDio;

  /// Send command using the fallback chain:
  /// 1. BLE write → 2. HTTP send_treatment2.php → 3. MQTT publish
  /// Returns true if any method succeeded.
  Future<bool> sendCommand(BleCommand command) async {
    // 1. Try BLE first
    if (_connector.isConnected(command.macAddress)) {
      final success = await _sendViaBle(command);
      if (success) return true;
      appLogger.w('BLE write failed, trying HTTP fallback...');
    }

    // 2. Try HTTP fallback
    final httpSuccess = await _sendViaHttp(command);
    if (httpSuccess) return true;
    appLogger.w('HTTP fallback failed, trying MQTT...');

    // 3. Try MQTT fallback
    final mqttSuccess = await _sendViaMqtt(command);
    if (mqttSuccess) return true;

    appLogger.e('All command delivery methods failed for ${command.macAddress}');
    return false;
  }

  /// Send to all connected devices simultaneously.
  Future<Map<String, bool>> sendToAll(
    CommandType type, {
    Map<String, dynamic>? payload,
  }) async {
    final results = <String, bool>{};
    final deviceIds = _connector.connectedDeviceIds;

    await Future.wait(
      deviceIds.map((deviceId) async {
        final command = BleCommand(
          macAddress: deviceId,
          type: type,
          payload: payload,
        );
        results[deviceId] = await sendCommand(command);
      }),
    );

    return results;
  }

  Future<bool> _sendViaBle(BleCommand command) async {
    try {
      return await _connector.writeToDevice(
        command.macAddress,
        command.toBytes(),
      );
    } catch (e) {
      appLogger.e('BLE write error: $e');
      return false;
    }
  }

  Future<bool> _sendViaHttp(BleCommand command) async {
    try {
      await _deviceDio.post(
        ApiEndpoints.sendTreatment,
        data: command.toHttpPayload(),
      );
      appLogger.i('HTTP command sent successfully');
      return true;
    } catch (e) {
      appLogger.e('HTTP command error: $e');
      return false;
    }
  }

  Future<bool> _sendViaMqtt(BleCommand command) async {
    try {
      await _djangoDio.post(
        ApiEndpoints.mqttPublish,
        data: command.toMqttPayload(),
      );
      appLogger.i('MQTT command sent successfully');
      return true;
    } catch (e) {
      appLogger.e('MQTT command error: $e');
      return false;
    }
  }
}
