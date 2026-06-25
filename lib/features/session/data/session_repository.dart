import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../../intake/domain/intake_models.dart';
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

  /// Session ids that have already been saved/synced (or are being saved) in
  /// this app run. The backend inserts a new intake on every POST (no upsert),
  /// so opening the live session card repeatedly must not create duplicates.
  /// Static so it survives provider re-creation and is shared app-wide.
  static final Set<String> _handledSessionIds = {};

  SessionRepository({
    required AppDatabase db,
    required Dio nodeDio,
    required bool isOnline,
  })  : _db = db,
        _nodeDio = nodeDio,
        _isOnline = isOnline;

  /// Save a completed session locally and sync to backend if online.
  Future<void> saveSession(SessionRecord record) async {
    // Claim this session id synchronously (before any await). If it's already
    // claimed, another save for the same session is in progress or done — skip
    // so we never POST the same intake twice (e.g. re-opening the live card).
    if (!_handledSessionIds.add(record.id)) {
      appLogger.i(
          'Session ${record.id} already handled this run, skipping duplicate save');
      return;
    }

    // Also skip if a previous app run already synced it to the backend.
    final existing = await _db.getLocalSession(record.id);
    final alreadySynced = existing?.synced ?? false;
    if (alreadySynced) {
      appLogger.i('Session ${record.id} already synced, skipping duplicate save');
      return;
    }

    // Always save locally first. Preserve the existing synced flag so we never
    // downgrade a synced row back to unsynced.
    await _db.upsertSession(LocalSessionsCompanion(
      id: Value(record.id),
      protocolId: Value(record.protocolId),
      protocolName: Value(record.protocolName),
      deviceIds: Value(jsonEncode(record.deviceIds)),
      durationSeconds: Value(record.totalDurationSeconds),
      elapsedSeconds: Value(record.elapsedSeconds),
      discomfortBefore: Value(record.discomfortBefore),
      discomfortAfter: Value(record.discomfortAfter),
      notes: Value(record.notes),
      clientType: Value(record.clientType),
      clientId: Value(record.clientId),
      intakeJson: Value(
        record.intake == null ? null : jsonEncode(record.intake!.toJson()),
      ),
      synced: Value(record.synced),
      completedAt: Value(record.completedAt),
    ));

    appLogger.i('Session saved locally: ${record.id}');

    // Attempt to sync to backend (only when not already synced).
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
        GuidedAssessmentData? intake;
        if (session.intakeJson != null && session.intakeJson!.isNotEmpty) {
          try {
            intake = GuidedAssessmentData.fromJson(
                jsonDecode(session.intakeJson!) as Map<String, dynamic>);
          } catch (_) {
            intake = null;
          }
        }
        final record = SessionRecord(
          id: session.id,
          protocolId: session.protocolId,
          protocolName: session.protocolName,
          deviceIds:
              (jsonDecode(session.deviceIds) as List<dynamic>).cast<String>(),
          totalDurationSeconds: session.durationSeconds,
          elapsedSeconds: session.elapsedSeconds,
          discomfortBefore: session.discomfortBefore,
          discomfortAfter: session.discomfortAfter,
          notes: session.notes,
          clientType: session.clientType,
          clientId: session.clientId,
          intake: intake,
          createdAt: session.completedAt,
          updatedAt: session.completedAt,
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
      final body = record.toIntakeJson();
      appLogger.i('Intake POST protocols → ${body['protocols']}');
      await _nodeDio.post(
        ApiEndpoints.intake,
        data: body,
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
