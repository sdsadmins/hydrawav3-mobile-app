import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../domain/protocol_model.dart';
import 'protocol_remote_source.dart';

final protocolRepositoryProvider = Provider<ProtocolRepository>((ref) {
  return ProtocolRepository(
    remoteSource: ref.read(protocolRemoteSourceProvider),
    db: ref.read(databaseProvider),
    isOnline: ref.read(isOnlineProvider),
  );
});

class ProtocolRepository {
  final ProtocolRemoteSource _remoteSource;
  final AppDatabase _db;
  final bool _isOnline;

  ProtocolRepository({
    required ProtocolRemoteSource remoteSource,
    required AppDatabase db,
    required bool isOnline,
  })  : _remoteSource = remoteSource,
        _db = db,
        _isOnline = isOnline;

  Future<List<Protocol>> getProtocols({int page = 1, int perPage = 50}) async {
    appLogger.i('🗄️  Repository: Getting protocols (online=$_isOnline)...');

    // Try cache first
    List<CachedProtocol> cached = [];
    try {
      cached = await _db.getAllCachedProtocols();
      appLogger
          .i('💾 Repository: Cache hit - ${cached.length} cached protocols');
    } catch (e) {
      appLogger.w('💾 Repository: Cache read failed: $e');
      // DB may fail on web — continue without cache
    }

    final isCacheStale = cached.isEmpty ||
        cached.first.cachedAt.isBefore(
            DateTime.now().subtract(AppConstants.protocolCacheStaleness));

    appLogger.i(
        '📋 Repository: Cache stale? $isCacheStale (empty=${cached.isEmpty})');

    if (_isOnline && isCacheStale) {
      try {
        appLogger.i('🌐 Repository: Fetching from API (cache stale)...');
        final protocols = await _remoteSource.getProtocols(
          page: page,
          perPage: perPage,
        );
        appLogger.i('✅ Repository: Got ${protocols.length} protocols from API');

        // Update cache (ignore errors)
        for (final protocol in protocols) {
          try {
            appLogger.d('💾 Repository: Caching protocol ${protocol.id}');
            await _db.upsertProtocol(CachedProtocolsCompanion(
              id: Value(protocol.id),
              templateName: Value(protocol.templateName),
              sessions: Value(protocol.sessions),
              cyclesJson: Value(
                  jsonEncode(protocol.cycles.map((c) => c.toJson()).toList())),
              hotdrop: Value(protocol.hotdrop),
              colddrop: Value(protocol.colddrop),
              vibmin: Value(protocol.vibmin),
              vibmax: Value(protocol.vibmax),
              cycle1: Value(protocol.cycle1),
              cycle5: Value(protocol.cycle5),
              edgecycleduration: Value(protocol.edgecycleduration),
              sessionPause: Value(protocol.sessionPause),
              description: Value(protocol.description),
              cachedAt: Value(DateTime.now()),
            ));
          } catch (e) {
            appLogger
                .w('❌ Repository: Failed to cache protocol ${protocol.id}: $e');
          }
        }
        appLogger.i(
            '✅ Repository: Returning ${protocols.length} fresh protocols from API');
        return protocols;
      } catch (e) {
        appLogger
            .e('❌ Repository: API fetch failed: $e. Falling back to cache...');
        // Network failed — fall through to cache
      }
    }

    // Return cached data
    appLogger.i('💾 Repository: Returning ${cached.length} cached protocols');
    return cached.map(_cachedToProtocol).toList();
  }

  Future<Protocol> getProtocol(String id) async {
    appLogger
        .i('🔍 Repository: Getting protocol by id=$id (online=$_isOnline)');
    if (_isOnline) {
      try {
        appLogger.i('🌐 Repository: Fetching protocol $id from API');
        return await _remoteSource.getProtocol(id);
      } catch (e) {
        appLogger
            .w('❌ Repository: API fetch for $id failed: $e. Trying cache...');
      }
    }

    try {
      final cached = await _db.getCachedProtocol(id);
      if (cached != null) {
        appLogger.i('✅ Repository: Found cached protocol $id');
        return _cachedToProtocol(cached);
      }
      appLogger.w('❌ Repository: Protocol $id not found in cache');
    } catch (e) {
      appLogger.e('❌ Repository: Cache lookup failed for $id: $e');
    }

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
    );
  }
}
