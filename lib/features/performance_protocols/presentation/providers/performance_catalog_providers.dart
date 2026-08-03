import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/performance_remote_source.dart';
import '../../domain/performance_models.dart';
import 'performance_session_provider.dart';

/// The catalogue's three metadata calls. Cheap, cacheable, ungated — so these
/// are plain FutureProviders and Riverpod's cache is the only cache we need.
/// `/chain` is deliberately NOT here: it returns pads and runs the safety guard,
/// so it is always called fresh through the remote source.

final disciplinesProvider = FutureProvider<List<Discipline>>((ref) async {
  final sessionId = ref.read(performanceSessionIdProvider);
  return ref
      .read(performanceRemoteSourceProvider)
      .listDisciplines(sessionId: sessionId);
});

final rolesProvider =
    FutureProvider.family<List<RoleOption>, String>((ref, discipline) async {
  final sessionId = ref.read(performanceSessionIdProvider);
  return ref
      .read(performanceRemoteSourceProvider)
      .listRoles(discipline, sessionId: sessionId);
});

/// Chains for a (discipline, role, subtype). A MENU — unranked, no scores.
class ChainsQuery {
  final String discipline;
  final String role;
  final String? subtype;

  const ChainsQuery(this.discipline, this.role, {this.subtype});

  @override
  bool operator ==(Object other) =>
      other is ChainsQuery &&
      other.discipline == discipline &&
      other.role == role &&
      other.subtype == subtype;

  @override
  int get hashCode => Object.hash(discipline, role, subtype);
}

final chainsProvider =
    FutureProvider.family<List<ChainSummary>, ChainsQuery>((ref, q) async {
  final sessionId = ref.read(performanceSessionIdProvider);
  return ref.read(performanceRemoteSourceProvider).listChains(
        q.discipline,
        q.role,
        subtype: q.subtype,
        sessionId: sessionId,
      );
});
