import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/session_history_model.dart';

final historyRemoteSourceProvider = Provider<HistoryRemoteSource>((ref) {
  return HistoryRemoteSource(ref.read(nodeDioProvider));
});

class HistoryRemoteSource {
  final Dio _dio;

  HistoryRemoteSource(this._dio);

  Future<List<SessionHistoryItem>> getClientHistory(
    String clientId, {
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.intakeByClient(clientId),
        queryParameters: {'page': page, 'perPage': perPage},
      );
      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);
      return items
          .map((e) =>
              SessionHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch history',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<DashboardStats> getDashboard(String orgId) async {
    try {
      final response = await _dio.get(ApiEndpoints.intakeDashboard(orgId));
      return DashboardStats.fromJson(response.data);
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch dashboard',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
