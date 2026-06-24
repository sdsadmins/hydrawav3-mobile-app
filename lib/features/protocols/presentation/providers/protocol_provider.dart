import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/preferences.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';

String? _resolvedOrgIdFromAuth(AuthState auth) {
  final selectedOrgId = auth.selectedOrgId?.trim();
  if (selectedOrgId != null && selectedOrgId.isNotEmpty) {
    return selectedOrgId;
  }

  final userOrgId = auth.user?.organizationId?.trim();
  if (userOrgId != null && userOrgId.isNotEmpty) {
    return userOrgId;
  }

  return null;
}

Future<String?> _resolveOrgId(Ref ref) async {
  final auth = ref.read(authStateProvider);
  final authOrgId = _resolvedOrgIdFromAuth(auth);
  if (authOrgId != null) {
    return authOrgId;
  }

  try {
    final dio = ref.read(djangoDioProvider);
    final response = await dio.get(ApiEndpoints.organizations);
    final data = response.data;
    final List<dynamic> items = data is List ? data : (data['data'] ?? []);
    if (items.isEmpty) {
      return null;
    }

    final first = items.first;
    if (first is Map<String, dynamic>) {
      final orgId = first['id']?.toString().trim();
      if (orgId != null && orgId.isNotEmpty) {
        return orgId;
      }
    }
  } catch (_) {}

  return null;
}

Future<List<Protocol>> _enrichProtocolsWithGoalTagNames(
  ProtocolRepository repository,
  List<Protocol> protocols, {
  required String? orgId,
}) async {
  final missingGoalTagIds = protocols
      .where((protocol) => protocol.goalTagName?.trim().isEmpty ?? true)
      .map((protocol) => protocol.id)
      .toSet();

  if (missingGoalTagIds.isEmpty) {
    return protocols;
  }

  List<GoalTagOption> goalTags;
  try {
    goalTags = await repository.getGoalTags();
  } catch (_) {
    return protocols;
  }

  final activeGoalTags = goalTags.where((goal) => goal.isActive).toList();
  if (activeGoalTags.isEmpty) {
    return protocols;
  }

  final protocolGoalTagNames = <String, String>{};
  final goalProtocolLists = await Future.wait(
    activeGoalTags.map((goalTag) async {
      try {
        return await repository.getProtocolsForGoalTag(
          goalTag.id,
          orgId: orgId,
        );
      } catch (_) {
        return const <ProtocolSelectionOption>[];
      }
    }),
  );

  for (final goalProtocols in goalProtocolLists) {
    for (final protocol in goalProtocols) {
      final goalTagName = protocol.goalTagName?.trim();
      if (goalTagName != null && goalTagName.isNotEmpty) {
        protocolGoalTagNames.putIfAbsent(protocol.id, () => goalTagName);
      }
    }
  }

  if (protocolGoalTagNames.isEmpty) {
    return protocols;
  }

  return protocols.map((protocol) {
    if (protocol.goalTagName?.trim().isNotEmpty ?? false) {
      return protocol;
    }

    final fallbackGoalTagName = protocolGoalTagNames[protocol.id];
    if (fallbackGoalTagName == null || fallbackGoalTagName.isEmpty) {
      return protocol;
    }

    return protocol.copyWith(goalTagName: fallbackGoalTagName);
  }).toList();
}

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  // Re-run whenever the auth/org selection changes. Without this watch, picking
  // a different organization left the list (and its per-protocol lock state)
  // stale, because the backend gates protocols by the org's plan.
  ref.watch(authStateProvider);
  final repository = ref.read(protocolRepositoryProvider);
  final orgId = await _resolveOrgId(ref);
  // NOTE: We intentionally skip goal-tag enrichment here. It issued one request
  // per goal tag just to populate a label the list card no longer shows, which
  // made the list slow to load. Fetch protocols in a single request instead.
  return orgId != null
      ? repository.getProtocols(orgId: orgId)
      : repository.getProtocols();
});

final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  final repository = ref.read(protocolRepositoryProvider);
  return repository.getProtocol(id);
});

final protocolSelectionOptionsProvider =
    FutureProvider.family<List<ProtocolSelectionOption>, String?>(
        (ref, goalTagId) async {
  final repository = ref.read(protocolRepositoryProvider);
  ref.watch(authStateProvider);
  final orgId = await _resolveOrgId(ref);
  final trimmedGoalTagId = goalTagId?.trim();

  if (trimmedGoalTagId != null && trimmedGoalTagId.isNotEmpty) {
    return repository.getProtocolsForGoalTag(
      trimmedGoalTagId,
      orgId: orgId,
    );
  }

  final protocols = orgId != null
      ? await repository.getProtocols(orgId: orgId)
      : await repository.getProtocols();
  final enrichedProtocols = await _enrichProtocolsWithGoalTagNames(
    repository,
    protocols,
    orgId: orgId,
  );

  return enrichedProtocols.map(ProtocolSelectionOption.fromProtocol).toList();
});

final goalTagListProvider = FutureProvider<List<GoalTagOption>>((ref) async {
  final repository = ref.read(protocolRepositoryProvider);
  return repository.getGoalTags();
});

/// Recently used protocol ids (most-recent first), persisted across launches.
final recentProtocolIdsProvider =
    StateNotifierProvider<RecentProtocolIdsController, List<String>>((ref) {
  return RecentProtocolIdsController(ref.read(preferencesProvider));
});

class RecentProtocolIdsController extends StateNotifier<List<String>> {
  static const int _maxRecents = 8;
  final PreferencesService _preferences;

  RecentProtocolIdsController(this._preferences)
      : super(_preferences.recentProtocolIds);

  /// Record [protocolId] as the most recently used, de-duplicating and
  /// capping the list at [_maxRecents].
  Future<void> recordUsed(String protocolId) async {
    if (protocolId.trim().isEmpty) return;
    final reordered = <String>[
      protocolId,
      ...state.where((id) => id != protocolId),
    ];
    final trimmed = reordered.length > _maxRecents
        ? reordered.sublist(0, _maxRecents)
        : reordered;
    state = trimmed;
    await _preferences.setRecentProtocolIds(trimmed);
  }
}
