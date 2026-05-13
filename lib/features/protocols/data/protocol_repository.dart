import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/storage/local_db.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../domain/protocol_model.dart';
import 'protocol_remote_source.dart';

final protocolRepositoryProvider = Provider<ProtocolRepository>((ref) {
  final auth = ref.watch(authStateProvider);
  final selectedOrgId = auth.selectedOrgId?.trim();
  final userOrgId = auth.user?.organizationId?.trim();
  final resolvedOrgId = selectedOrgId != null && selectedOrgId.isNotEmpty
      ? selectedOrgId
      : (userOrgId != null && userOrgId.isNotEmpty ? userOrgId : null);

  return ProtocolRepository(
    remoteSource: ref.read(protocolRemoteSourceProvider),
    db: ref.read(databaseProvider),
    isOnline: ref.read(isOnlineProvider),
    orgId: resolvedOrgId,
  );
});

class ProtocolRepository {
  final ProtocolRemoteSource _remoteSource;
  final AppDatabase _db;
  final bool _isOnline;
  final String? _orgId;

  ProtocolRepository({
    required ProtocolRemoteSource remoteSource,
    required AppDatabase db,
    required bool isOnline,
    required String? orgId,
  })  : _remoteSource = remoteSource,
        _db = db,
        _isOnline = isOnline,
        _orgId = orgId;

  Future<List<Protocol>> getProtocols({
    int page = 1,
    int perPage = 50,
    String? orgId,
  }) async {
    List<CachedProtocol> cached = [];
    try {
      cached = await _db.getAllCachedProtocols();
    } catch (_) {
      // DB may fail on web; continue without cache.
    }

    final hasMissingDeviceId =
        cached.any((protocol) => protocol.deviceId?.isEmpty ?? true);
    final isCacheStale = cached.isEmpty ||
        hasMissingDeviceId ||
        cached.first.cachedAt.isBefore(
          DateTime.now().subtract(AppConstants.protocolCacheStaleness),
        );

    if (_isOnline && isCacheStale) {
      try {
        final protocols = await _remoteSource.getProtocols(
          page: page,
          perPage: perPage,
          orgId: orgId ?? _orgId,
        );

        for (final protocol in protocols) {
          try {
            await _db.upsertProtocol(
              CachedProtocolsCompanion(
                id: Value(protocol.id),
                templateName: Value(protocol.templateName),
                sessions: Value(protocol.sessions),
                cyclesJson: Value(
                  jsonEncode(protocol.cycles.map((c) => c.toJson()).toList()),
                ),
                hotdrop: Value(protocol.hotdrop),
                colddrop: Value(protocol.colddrop),
                vibmin: Value(protocol.vibmin),
                vibmax: Value(protocol.vibmax),
                cycle1: Value(protocol.cycle1),
                cycle5: Value(protocol.cycle5),
                edgecycleduration: Value(protocol.edgecycleduration),
                sessionPause: Value(protocol.sessionPause),
                description: Value(protocol.description),
                deviceId: Value(protocol.deviceId),
                cachedAt: Value(DateTime.now()),
              ),
            );
          } catch (_) {}
        }
        return protocols;
      } catch (_) {
        // Network failed; fall through to cache.
      }
    }

    final protocols = cached.map(_cachedToProtocol).toList();
    protocols.sort((a, b) => a.templateName.compareTo(b.templateName));
    return protocols;
  }

  Future<List<ProtocolSelectionOption>> getProtocolsForGoalTag(
    String goalTagId, {
    String? orgId,
  }) async {
    if (!_isOnline) {
      throw Exception('Goal-tag filtered protocols are unavailable offline');
    }

    return _remoteSource.getProtocolsWithGoalTag(
      goalTagId,
      orgId: orgId ?? _orgId,
    );
  }

  Future<List<GoalTagOption>> getGoalTags({
    int page = 1,
    int perPage = 100,
  }) async {
    if (!_isOnline) {
      return const [];
    }

    return _remoteSource.getGoalTags(page: page, perPage: perPage);
  }

  Future<Protocol> getProtocol(String id) async {
    if (_isOnline) {
      try {
        return await _remoteSource.getProtocol(
          id,
          orgId: _orgId,
        );
      } catch (_) {}
    }

    try {
      final cached = await _db.getCachedProtocol(id);
      if (cached != null) {
        return _cachedToProtocol(cached);
      }
    } catch (_) {}

    throw Exception('Protocol not found');
  }

  Protocol _cachedToProtocol(CachedProtocol cached) {
    final cyclesList = jsonDecode(cached.cyclesJson) as List<dynamic>;
    return Protocol(
      id: cached.id,
      templateName: cached.templateName,
      sessions: cached.sessions,
      cycles: cyclesList
          .map((e) => ProtocolCycle.fromJson(e as Map<String, dynamic>))
          .toList(),
      hotdrop: cached.hotdrop,
      colddrop: cached.colddrop,
      vibmin: cached.vibmin,
      vibmax: cached.vibmax,
      cycle1: cached.cycle1,
      cycle5: cached.cycle5,
      edgecycleduration: cached.edgecycleduration,
      sessionPause: cached.sessionPause,
      description: cached.description,
      deviceId: cached.deviceId,
    );
  }
}
