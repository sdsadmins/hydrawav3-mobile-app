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

  /// Active body parts with their ids (`GET /body-part`).
  Future<List<CoachBodyPart>> bodyParts() async {
    final res = await _dio.get(ApiEndpoints.bodyParts);
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['data'] is List)
            ? data['data'] as List
            : const [];
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
