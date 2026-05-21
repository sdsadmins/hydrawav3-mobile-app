import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/device_model.dart';

final deviceRemoteSourceProvider = Provider<DeviceRemoteSource>((ref) {
  return DeviceRemoteSource(ref.read(djangoDioProvider));
});

class DeviceRemoteSource {
  final Dio _dio;

  DeviceRemoteSource(this._dio);

  String _extractErrorMessage(
    DioException error,
    String fallbackMessage,
  ) {
    final data = error.response?.data;

    if (data is Map<String, dynamic>) {
      final message = data['message'] ?? data['error'] ?? data['detail'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      return fallbackMessage;
    }

    if (data is String && data.trim().isNotEmpty) {
      return data;
    }

    return error.message ?? fallbackMessage;
  }

  Future<List<DeviceInfo>> getDevices() async {
    try {
      final response = await _dio.get(ApiEndpoints.sensors);
      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);
      return items
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        _extractErrorMessage(e, 'Failed to fetch devices'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<DeviceInfo>> getDevicesByOrg(String orgId) async {
    try {
      final response = await _dio.get(ApiEndpoints.sensorsByOrg(orgId));
      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);
      return items
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        _extractErrorMessage(e, 'Failed to fetch devices'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> registerDevice({
    required String name,
    required String macAddress,
    required List<int> organizationIds,
  }) async {
    final payload = {
      'name': name,
      'macAddress': macAddress,
      'organizationIds': organizationIds,
    };

    try {
      print('REGISTER DEVICE REQUEST STARTING: payload=$payload');
      final response = await _dio
          .post(
            ApiEndpoints.sensors,
            data: payload,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
                'Device registration timed out after 30 seconds'),
          );
      print(
          'REGISTER DEVICE SUCCESS: status=${response.statusCode} response=${response.data}');
    } on TimeoutException catch (e) {
      print('REGISTER DEVICE TIMEOUT: $e');
      throw ServerException(
        'Device registration timed out. Please try again.',
        statusCode: 408,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final responseData = e.response?.data;
      print(
          'REGISTER DEVICE FAILED: status=$status payload=$payload response=$responseData error=${e.message}');
      final message = _extractErrorMessage(e, 'Failed to register device');
      throw ServerException(
        message,
        statusCode: status,
      );
    }
  }

  Future<DeviceInfo> updateDevice({
    required String sensorId,
    String? name,
    String? macAddress,
    List<int>? addOrgIds,
    List<int>? removeOrgIds,
  }) async {
    try {
      final response = await _dio.put(
        ApiEndpoints.sensorById(sensorId),
        data: {
          if (name != null) 'name': name,
          if (macAddress != null) 'macAddress': macAddress,
          if (addOrgIds != null) 'addOrganisationIds': addOrgIds,
          if (removeOrgIds != null) 'removeOrganisationIds': removeOrgIds,
        },
      );
      return DeviceInfo.fromJson(response.data);
    } on DioException catch (e) {
      throw ServerException(
        _extractErrorMessage(e, 'Failed to update device'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> publishMqttPayload(Map<String, dynamic> payload) async {
    try {
      await _dio.post(
        ApiEndpoints.mqttPublish,
        data: {
          'topic': 'HydraWav3Pro/config',
          'payload': jsonEncode(payload),
        },
      );
    } on DioException catch (e) {
      throw ServerException(
        _extractErrorMessage(e, 'Failed to publish MQTT payload'),
        statusCode: e.response?.statusCode,
      );
    }
  }
}
