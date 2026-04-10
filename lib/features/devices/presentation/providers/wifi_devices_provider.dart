import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/device_repository.dart';
import '../../domain/device_model.dart';

/// WiFi/Cloud devices (sensors) for the logged-in user's organization.
///
/// These are NOT BLE devices; they are the backend-registered devices that can
/// receive commands via MQTT/API.
final wifiDevicesByOrgProvider = FutureProvider<List<DeviceInfo>>((ref) async {
  final auth = ref.watch(authStateProvider);
  String? orgId = auth.user?.organizationId;

  // Fallback: if profile doesn't include organization id, fetch orgs and pick
  // the first one (matches your `/api/v1/admin/organizations` output).
  if (orgId == null || orgId.isEmpty) {
    try {
      final dio = ref.read(djangoDioProvider);
      final resp = await dio.get(ApiEndpoints.organizations);
      final data = resp.data;
      final List<dynamic> list = data is List ? data : (data['data'] ?? []);
      if (list.isNotEmpty) {
        final first = list.first as Map<String, dynamic>;
        orgId = first['id']?.toString();
      }
    } on DioException catch (e) {
      // Treat common “not available” statuses as empty list.
      final s = e.response?.statusCode;
      if (s == 401 || s == 403 || s == 404 || s == 204) {
        return const <DeviceInfo>[];
      }
      rethrow;
    }
  }

  if (orgId == null || orgId.isEmpty) return const <DeviceInfo>[];

  final repo = ref.read(deviceRepositoryProvider);
  return repo.getDevicesByOrg(orgId);
});

