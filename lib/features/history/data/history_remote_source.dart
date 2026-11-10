import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/session_history_model.dart';

final historyRemoteSourceProvider = Provider<HistoryRemoteSource>((ref) {
  return HistoryRemoteSource(ref.read(nodeDioProvider));
});

/// One page of `/intake/allByorg/:organizationId`, with the backend's own
/// pagination metadata (`{data: [...], pagination: {total, hasNextPage, ...}}`)
/// so callers know when to stop paging without guessing from page size.
class IntakePage {
  final List<SessionHistoryItem> items;
  final bool hasNextPage;
  final int total;
  final int totalPages;

  const IntakePage({
    required this.items,
    required this.hasNextPage,
    required this.total,
    required this.totalPages,
  });
}

class HistoryRemoteSource {
  final Dio _dio;

  HistoryRemoteSource(this._dio);

  /// One page of saved intakes/sessions for an organization
  /// (`GET /intake/allByorg/:organizationId?page=&perPage=`), for scroll
  /// pagination.
  Future<IntakePage> getAllIntakes(
    String organizationId, {
    int page = 1,
    int perPage = 10,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.intakeAll(organizationId),
        queryParameters: {'page': page, 'perPage': perPage},
      );
      final data = response.data;
      final List<dynamic> rawItems = data is List ? data : (data['data'] ?? []);
      final items = rawItems
          .map((e) => SessionHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final pagination = data is Map ? data['pagination'] : null;
      // Falls back to inferring from page size if the backend ever omits
      // `pagination` (e.g. an older server build) rather than getting stuck.
      final hasNextPage = pagination is Map
          ? pagination['hasNextPage'] == true
          : items.length >= perPage;
      final total = pagination is Map
          ? (pagination['total'] as num?)?.toInt() ?? items.length
          : items.length;
      final totalPages = pagination is Map
          ? (pagination['totalPages'] as num?)?.toInt() ?? 1
          : (hasNextPage
              ? 2
              : 1); // unknown — caller keeps paging til a short page
      return IntakePage(
        items: items,
        hasNextPage: hasNextPage,
        total: total,
        totalPages: totalPages,
      );
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch sessions',
        statusCode: e.response?.statusCode,
      );
    }
  }

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
      final sessions = items
          .map((e) => SessionHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return await _includeRecentCoachSessions(clientId, sessions);
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch history',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<SessionHistoryItem>> _includeRecentCoachSessions(
    String clientId,
    List<SessionHistoryItem> history,
  ) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.recentSessionCoachByClient(clientId),
        queryParameters: {'limit': 50},
      );
      final data = response.data;
      final records = data is List
          ? data
          : data is Map && data['data'] is List
              ? data['data'] as List
              : data is Map
                  ? [data]
                  : const [];
      final merged = [...history];
      final indexById = {
        for (var i = 0; i < merged.length; i++)
          if (merged[i].id != null) merged[i].id!: i,
      };
      for (final raw in records.whereType<Map>()) {
        final recent =
            SessionHistoryItem.fromJson(Map<String, dynamic>.from(raw));
        if (!recent.isSessionCoach || recent.id == null) continue;
        final index = indexById[recent.id];
        if (index == null) {
          indexById[recent.id!] = merged.length;
          merged.add(recent);
        } else {
          merged[index] = merged[index].copyWith(
            sessionType: 'session_coach',
            sessionCoach: recent.sessionCoach,
            protocols: recent.protocols.isNotEmpty ? recent.protocols : null,
          );
        }
      }
      return merged;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        appLogger.w(
            'Recent Session Coach history endpoint is unavailable; showing the client history without coach details.');
        return history;
      }
      rethrow;
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
