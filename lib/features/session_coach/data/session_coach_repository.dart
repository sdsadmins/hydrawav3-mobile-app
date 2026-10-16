import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../domain/session_coach_models.dart';

/// Reads the Session Coach plans the admin authors on the website
/// (Node `session-coach` module). Read-only from the app.
class SessionCoachRepository {
  final Dio _dio;
  SessionCoachRepository(this._dio);

  /// Active body parts with their ids (`GET /body-part`). The endpoint pages
  /// (10 per page by default), so every page is read.
  Future<List<CoachBodyPart>> bodyParts() async {
    final list = <dynamic>[];
    for (var page = 1; page <= 20; page++) {
      final res = await _dio.get(ApiEndpoints.bodyParts,
          queryParameters: {'page': page, 'perPage': 100});
      final data = res.data;
      list.addAll(data is List
          ? data
          : (data is Map && data['data'] is List)
              ? data['data'] as List
              : const []);
      final paging = data is Map ? data['pagination'] : null;
      if (paging is! Map || paging['hasNextPage'] != true) break;
    }
    return list
        .whereType<Map>()
        .where((m) => m['isActive'] != false)
        .map((m) => CoachBodyPart(
              id: (m['_id'] ?? m['id'] ?? '').toString(),
              name: (m['partName'] ?? '').toString(),
            ))
        .where((b) => b.id.isNotEmpty && b.name.isNotEmpty)
        .toList();
  }

  /// Active coaches for one body part, newest first (server order). A body
  /// part with none returns an empty list.
  Future<List<SessionCoach>> byBodyPart(String bodyPartId) async {
    try {
      final res =
          await _dio.get(ApiEndpoints.sessionCoachByBodyPart(bodyPartId));
      final data = res.data;
      final list = data is List
          ? data
          : (data is Map && data['data'] is List)
              ? data['data'] as List
              : const [];
      return list
          .whereType<Map>()
          .map((m) => SessionCoach.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
  }
}

final sessionCoachRepositoryProvider = Provider<SessionCoachRepository>(
  (ref) => SessionCoachRepository(ref.read(nodeDioProvider)),
);

final coachBodyPartsProvider =
    FutureProvider.autoDispose<List<CoachBodyPart>>((ref) {
  return ref.read(sessionCoachRepositoryProvider).bodyParts();
});

final sessionCoachesByBodyPartProvider = FutureProvider.autoDispose
    .family<List<SessionCoach>, String>((ref, bodyPartId) {
  return ref.read(sessionCoachRepositoryProvider).byBodyPart(bodyPartId);
});
