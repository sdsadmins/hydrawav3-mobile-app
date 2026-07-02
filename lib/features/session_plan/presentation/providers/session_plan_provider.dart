import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/session_plan_remote_source.dart';
import '../../domain/session_plan.dart';

/// Body-part names for the Session Plan area picker (web parity: getBodyParts →
/// partName). Active parts only.
final sessionPlanBodyPartsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final res = await ref.read(nodeDioProvider).get(ApiEndpoints.bodyParts);
  final data = res.data;
  final list = data is List
      ? data
      : (data is Map && data['data'] is List)
          ? data['data'] as List
          : const [];
  return list
      .whereType<Map>()
      .where((m) => m['isActive'] != false)
      .map((m) => (m['partName'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toList();
});

/// The pad-placement plan for one body part, fetched on demand.
final sessionPlanByBodyPartProvider =
    FutureProvider.autoDispose.family<SessionPlan, String>((ref, bodyPart) {
  return ref.read(sessionPlanRemoteSourceProvider).getByBodyPart(bodyPart);
});

/// Body areas the practitioner has added to the Session Plan (focus areas).
final selectedSessionPlanAreasProvider =
    StateProvider.autoDispose<List<String>>((ref) => const []);
