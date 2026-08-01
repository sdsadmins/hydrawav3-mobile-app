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
    ref: ref,
  );
});

class SessionRepository {
  final AppDatabase _db;
  final Dio _nodeDio;
  final Ref _ref;

  /// Session ids already POSTed to the backend in this app run. The backend
  /// inserts a new intake on every POST (no upsert), so a session must be
  /// finalized (POSTed) at most once. Only ids with a SUCCESSFUL POST are added
  /// — a failed POST leaves the id absent so a later retry can proceed.
  /// Static so it survives provider re-creation and is shared app-wide.
  static final Set<String> _handledSessionIds = {};

  /// Session ids saved as a local draft this run (avoids redundant re-writes
  /// when the live card is re-opened before completion).
  static final Set<String> _draftedSessionIds = {};

  SessionRepository({
    required AppDatabase db,
    required Dio nodeDio,
    required Ref ref,
  })  : _db = db,
        _nodeDio = nodeDio,
        _ref = ref;

  bool get _isOnline => _ref.read(isOnlineProvider);

  LocalSessionsCompanion _companion(SessionRecord record, {required bool synced}) {
    return LocalSessionsCompanion(
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
      synced: Value(synced),
      completedAt: Value(record.completedAt),
    );
  }

  /// Save a session as a LOCAL-ONLY draft at start — no backend POST. The
  /// `/intake` POST is deferred to [finalizeSession] once the user has answered
  /// the post-session questions (or skipped), so the record is written to the
  /// backend exactly once, with the outcome data.
  Future<void> saveSessionDraft(SessionRecord record) async {
    if (_handledSessionIds.contains(record.id)) return; // already finalized
    if (!_draftedSessionIds.add(record.id)) return; // already drafted this run

    final existing = await _db.getLocalSession(record.id);
    if (existing?.synced ?? false) return; // finalized in a previous run

    await _db.upsertSession(_companion(record, synced: false));
    appLogger.i('Session draft saved locally: ${record.id}');
  }

  /// Finalize a completed session: persist the enriched record locally and POST
  /// it to `/intake` exactly once. Returns true when the backend has the record
  /// (either just POSTed, or already synced); false when the POST failed (so the
  /// caller can keep it queued for retry). Legacy alias: [saveSession].
  Future<bool> finalizeSession(SessionRecord record) async {
    // Already POSTed this run, or in a previous run → treat as done.
    if (_handledSessionIds.contains(record.id)) return true;
    final existing = await _db.getLocalSession(record.id);
    if (existing?.synced ?? false) {
      _handledSessionIds.add(record.id);
      return true;
    }

    // Persist the enriched record locally (still unsynced until the POST lands).
    await _db.upsertSession(_companion(record, synced: false));

    if (!_isOnline) {
      appLogger.i('Session ${record.id} finalized offline; awaiting sync');
      return false;
    }
    return _syncSession(record);
  }

  /// Legacy one-shot save (draft + immediate finalize). Retained for any caller
  /// that isn't part of the post-session outcomes flow.
  Future<void> saveSession(SessionRecord record) async {
    await saveSessionDraft(record);
    await finalizeSession(record);
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

  Future<bool> _syncSession(SessionRecord record) async {
    try {
      final body = record.toIntakeJson();
      appLogger.i('Intake POST protocols → ${body['protocols']}');
      await _nodeDio.post(
        ApiEndpoints.intake,
        data: body,
      );
      await _db.markSessionSynced(record.id);
      _handledSessionIds.add(record.id);
      appLogger.i('Session synced: ${record.id}');
      return true;
    } catch (e) {
      appLogger.e('Failed to sync session: $e');
      return false;
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
