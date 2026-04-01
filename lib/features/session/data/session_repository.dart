import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../domain/session_model.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(
    db: ref.read(databaseProvider),
    nodeDio: ref.read(nodeDioProvider),
    isOnline: ref.read(isOnlineProvider),
  );
});

class SessionRepository {
  final AppDatabase _db;
  final Dio _nodeDio;
  final bool _isOnline;

  SessionRepository({
    required AppDatabase db,
    required Dio nodeDio,
    required bool isOnline,
  })  : _db = db,
        _nodeDio = nodeDio,
        _isOnline = isOnline;

  /// Save a completed session locally and sync to backend if online.
  Future<void> saveSession(SessionRecord record) async {
    // Always save locally first
    await _db.insertSession(LocalSessionsCompanion(
      id: Value(record.id),
      protocolId: Value(record.protocolId),
      protocolName: Value(record.protocolName),
      deviceIds: Value(jsonEncode(record.deviceIds)),
      durationSeconds: Value(record.totalDurationSeconds),
      elapsedSeconds: Value(record.elapsedSeconds),
      discomfortBefore: Value(record.discomfortBefore),
      discomfortAfter: Value(record.discomfortAfter),
      notes: Value(record.notes),
      synced: const Value(false),
      completedAt: Value(record.completedAt),
    ));

    appLogger.i('Session saved locally: ${record.id}');

    // Attempt to sync to backend
    if (_isOnline) {
      await _syncSession(record);
    }
  }

  /// Sync all unsynced sessions to the backend.
  Future<void> syncAllSessions() async {
    if (!_isOnline) return;

    final unsynced = await _db.getUnsyncedSessions();
    appLogger.i('Syncing ${unsynced.length} sessions...');

    for (final session in unsynced) {
      try {
        final record = SessionRecord(
          id: session.id,
          protocolId: session.protocolId,
          protocolName: session.protocolName,
          deviceIds: (jsonDecode(session.deviceIds) as List<dynamic>)
              .cast<String>(),
          totalDurationSeconds: session.durationSeconds,
          elapsedSeconds: session.elapsedSeconds,
          discomfortBefore: session.discomfortBefore,
          discomfortAfter: session.discomfortAfter,
          notes: session.notes,
          completedAt: session.completedAt,
        );
        await _syncSession(record);
      } catch (e) {
        appLogger.e('Failed to sync session ${session.id}: $e');
      }
    }
  }

  Future<void> _syncSession(SessionRecord record) async {
    try {
      await _nodeDio.post(
        ApiEndpoints.intake,
        data: record.toIntakeJson(),
      );
      await _db.markSessionSynced(record.id);
      appLogger.i('Session synced: ${record.id}');
    } catch (e) {
      appLogger.e('Failed to sync session: $e');
    }
  }

  /// Get all local sessions.
  Stream<List<LocalSession>> watchSessions() => _db.watchLocalSessions();

  /// Get session count.
  Future<int> getSessionCount() async {
    final sessions = await _db.getAllLocalSessions();
    return sessions.length;
  }
}
