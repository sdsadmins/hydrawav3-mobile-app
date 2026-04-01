import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/protocol_model.dart';

final protocolRemoteSourceProvider = Provider<ProtocolRemoteSource>((ref) {
  return ProtocolRemoteSource(ref.read(nodeDioProvider));
});

class ProtocolRemoteSource {
  final Dio _dio;

  ProtocolRemoteSource(this._dio);

  Future<List<Protocol>> getProtocols({int page = 1, int perPage = 50}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.protocols,
        queryParameters: {'page': page, 'perPage': perPage},
      );
      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);
      return items
          .map((e) => Protocol.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch protocols',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Protocol> getProtocol(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.protocolById(id));
      return Protocol.fromJson(response.data);
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch protocol',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
