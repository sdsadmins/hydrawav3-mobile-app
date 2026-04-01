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
        e.response?.data?['message'] ?? 'Failed to fetch devices',
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
        e.response?.data?['message'] ?? 'Failed to fetch devices',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<DeviceInfo> registerDevice({
    required String name,
    required String macAddress,
    required List<int> organizationIds,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.sensors,
        data: {
          'name': name,
          'macAddress': macAddress,
          'organizationIds': organizationIds,
        },
      );
      return DeviceInfo.fromJson(response.data);
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to register device',
        statusCode: e.response?.statusCode,
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
        e.response?.data?['message'] ?? 'Failed to update device',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
