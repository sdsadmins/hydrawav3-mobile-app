import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';

final padPlacementRemoteSourceProvider =
    Provider<PadPlacementRemoteSource>((ref) {
  return PadPlacementRemoteSource(ref.read(nodeDioProvider));
});

/// Calls the RAG pad-placement endpoint (parity with hydrawav3-ai
/// `getRagPadPlacement` → `POST ai-padplacement/placement-session`). The Node
/// Dio's auth interceptor supplies the token.
class PadPlacementRemoteSource {
  final Dio _dio;
  PadPlacementRemoteSource(this._dio);

  /// [payload] is the `AssessmentPayload` — `{ state, learningCases, persist }`.
  /// Returns the pad-placement result map (unwrapping a `{ data: … }` wrapper
  /// if the backend nests it).
  Future<Map<String, dynamic>> placementSession(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.padPlacementSession,
        data: payload,
      );
      final data = res.data;
      final map = data is Map && data['data'] is Map ? data['data'] : data;
      if (map is Map) return Map<String, dynamic>.from(map);
      return {'result': map};
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data is Map
            ? (e.response?.data['message']?.toString() ??
                'Pad placement failed')
            : 'Pad placement failed',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
