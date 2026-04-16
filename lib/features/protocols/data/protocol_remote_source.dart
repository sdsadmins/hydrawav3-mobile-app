import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/protocol_model.dart';

final protocolRemoteSourceProvider = Provider<ProtocolRemoteSource>((ref) {
  return ProtocolRemoteSource(ref.read(nodeDioProvider));
});

class ProtocolRemoteSource {
  final Dio _dio;

  ProtocolRemoteSource(this._dio);

  Future<List<Protocol>> getProtocols({
    int page = 1,
    int perPage = 50,
    String? orgId, // ✅ ADDED
  }) async {
    try {
      appLogger.i(
          '🔄 Protocol: Fetching protocols from API (page=$page, perPage=$perPage)...');
      final response = await _dio.get(
        ApiEndpoints.protocols,
        queryParameters: {
          'page': page,
          'perPage': perPage,
          if (orgId != null) 'orgId': orgId, // ✅ ADDED
        },
      );

      final data = response.data;
      final List<dynamic> items =
          data is List ? data : (data['data'] ?? []);

      return items
          .map((e) =>
              Protocol.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      appLogger.e('❌ Protocol: API error (status: ${e.response?.statusCode})');
      appLogger.e('   Message: ${e.response?.data?['message'] ?? e.message}');
      appLogger.e('   Full error: ${e.response?.data}');
      throw ServerException(
        e.response?.data?['message'] ??
            'Failed to fetch protocols',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      appLogger.e('❌ Protocol: Parsing error: $e');
      rethrow;
    }
  }

  Future<Protocol> getProtocol(
    String id, {
    String? orgId, // ✅ ADDED
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.protocolById(id),
        queryParameters: {
          if (orgId != null) 'orgId': orgId, // ✅ ADDED
        },
      );

      return Protocol.fromJson(response.data);
    } on DioException catch (e) {
      appLogger.e(
          '❌ Protocol: Failed to fetch protocol $id (status: ${e.response?.statusCode})');
      throw ServerException(
        e.response?.data?['message'] ??
            'Failed to fetch protocol',
        statusCode: e.response?.statusCode,
      );
    }
  }
}