import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/session_plan.dart';

final sessionPlanRemoteSourceProvider =
    Provider<SessionPlanRemoteSource>((ref) {
  return SessionPlanRemoteSource(ref.read(nodeDioProvider));
});

/// Talks to the Node treatment-plan endpoint (web parity:
/// getTreatmentPlanByBodyPart).
class SessionPlanRemoteSource {
  final Dio _dio;

  SessionPlanRemoteSource(this._dio);

  /// `GET treatment-plans/body-part/:bodyPartName`.
  Future<SessionPlan> getByBodyPart(String bodyPartName) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.treatmentPlanByBodyPart(bodyPartName),
      );
      final data = res.data;
      return SessionPlan.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : const {},
      );
    } on DioException catch (e) {
      throw ServerException(
        _message(e, 'Failed to load session plan'),
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
