import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/ai_report_models.dart';

final aiReportRemoteSourceProvider = Provider<AiReportRemoteSource>((ref) {
  return AiReportRemoteSource(ref.read(nodeDioProvider));
});

/// Node-Nest AI report endpoints (parity with web `hydrawav3-api.ts` +
/// `action.ts`). Generation is queued: analyze returns a job id, poll for the
/// result, then persist.
class AiReportRemoteSource {
  final Dio _dio;

  AiReportRemoteSource(this._dio);

  /// `POST ai/analyze` — enqueue a job; returns `{ id, status, ... }`.
  Future<AnalysisStatus> analyze(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post(ApiEndpoints.aiReportAnalyze, data: body);
      return AnalysisStatus.fromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to start AI analysis'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `GET ai/analyze/:id` — poll job status/result.
  Future<AnalysisStatus> status(String id) async {
    try {
      final response =
          await _dio.get(ApiEndpoints.aiReportAnalyzeStatus(id));
      return AnalysisStatus.fromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to fetch analysis status'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `POST ai-reports` — persist the completed report. Returns the saved report.
  Future<Map<String, dynamic>> persist(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post(ApiEndpoints.aiReports, data: body);
      final data = response.data;
      final map = data is Map && data['report'] is Map
          ? data['report']
          : data;
      return _asMap(map);
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to save AI report'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `GET ai-reports/all?userId=&organizationId=&page=&limit=` — paginated
  /// history. Returns the list of report objects.
  Future<List<Map<String, dynamic>>> list({
    String? userId,
    int? organizationId,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.aiReportsAll,
        queryParameters: {
          if (userId != null) 'userId': userId,
          if (organizationId != null) 'organizationId': organizationId,
          'page': page,
          'limit': limit,
        },
      );
      final data = response.data;
      // Shape can be { reports: [...] } or { data: [...] } or a bare array.
      final raw = data is Map
          ? (data['reports'] ?? data['data'] ?? data['report'])
          : data;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to load reports'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `GET ai-reports/:id` — a single report.
  Future<Map<String, dynamic>?> getById(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.aiReportById(id));
      final data = response.data;
      final report = data is Map ? (data['report'] ?? data) : data;
      return report is Map ? Map<String, dynamic>.from(report) : null;
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to load report'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// `GET ai-reports/recent?userId=&organizationId=` — latest report.
  Future<Map<String, dynamic>?> recent({
    String? userId,
    int? organizationId,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.aiReportsRecent,
        queryParameters: {
          if (userId != null) 'userId': userId,
          if (organizationId != null) 'organizationId': organizationId,
        },
      );
      final data = response.data;
      final report = data is Map ? data['report'] : null;
      return report is Map ? Map<String, dynamic>.from(report) : null;
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to fetch recent report'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
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
