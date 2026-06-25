import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/client_model.dart';

final clientRemoteSourceProvider = Provider<ClientRemoteSource>((ref) {
  return ClientRemoteSource(ref.read(nodeDioProvider));
});

/// Talks to the Node-Nest client endpoints (parity with the web `action.ts`
/// GetClients / addClient / getClientById).
class ClientRemoteSource {
  final Dio _dio;

  ClientRemoteSource(this._dio);

  /// `GET /clients/:organizationId` — all clients for the organization.
  Future<List<Client>> getClients(String organizationId) async {
    try {
      final response = await _dio.get(ApiEndpoints.clientsByOrg(organizationId));
      final data = response.data;
      // The endpoint may return a bare array or `{ data: [...] }`.
      final list = data is List
          ? data
          : (data is Map && data['data'] is List)
              ? data['data'] as List
              : (data is Map && data['clients'] is List)
                  ? data['clients'] as List
                  : const [];
      return list
          .whereType<Map>()
          .map((e) => Client.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to load clients'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `GET /clients/clientDetails/:clientId`.
  Future<Client> getById(String clientId) async {
    try {
      final response = await _dio.get(ApiEndpoints.clientById(clientId));
      final data = response.data;
      final map = data is Map && data['data'] is Map
          ? data['data']
          : data;
      return Client.fromJson(Map<String, dynamic>.from(map as Map));
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to load client'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `POST /clients`.
  Future<Client> create(CreateClientRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.clients,
        data: request.toJson(),
      );
      final data = response.data;
      final map = data is Map && data['data'] is Map
          ? data['data']
          : data;
      return Client.fromJson(Map<String, dynamic>.from(map as Map));
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to create client'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final m = data['message'];
      if (m is String && m.trim().isNotEmpty) return m;
      if (m is List && m.isNotEmpty) return m.first.toString();
    }
    return fallback;
  }
}
