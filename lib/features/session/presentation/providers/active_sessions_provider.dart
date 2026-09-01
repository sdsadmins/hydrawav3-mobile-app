import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/storage/preferences.dart';
import '../../domain/active_session_model.dart';
import '../../services/background_session_runtime.dart';
import '../../services/session_engine.dart';

final activeSessionsProvider =
    StateNotifierProvider<ActiveSessionsNotifier, List<ActiveSession>>((ref) {
  return ActiveSessionsNotifier(ref.read(sharedPreferencesProvider));
});

/// Device ids belonging to a local session whose engine has gone terminal but
/// the backend stop hasn't been confirmed yet (see
/// [SessionEngineState.backendStopUnresolved]). The devices list screen must
/// not silently free these into "available" — they need their own tri-state
/// (available / in-use / pending-stop) so the practitioner can see the stop
/// hasn't actually landed and go finish it from the session screen.
final pendingBackendStopDeviceIdsProvider = Provider<Set<String>>((ref) {
  final sessions = ref.watch(activeSessionsProvider);
  final ids = <String>{};
  for (final session in sessions) {
    final unresolved = ref.watch(
      sessionEngineFamilyProvider(session.id)
          .select((s) => s.backendStopUnresolved),
    );
    if (unresolved) ids.addAll(session.deviceIds);
  }
  return ids;
});

class ActiveSessionsNotifier extends StateNotifier<List<ActiveSession>> {
  final Uuid _uuid = const Uuid();
  final SharedPreferences _prefs;
  static const _activeSessionsKey = 'active_sessions';

  ActiveSessionsNotifier(this._prefs) : super([]) {
    _loadActiveSessionsSync();
  }

  void _loadActiveSessionsSync() {
    try {
      final sessionsJson = _prefs.getString(_activeSessionsKey) ?? '[]';
      if (sessionsJson.isNotEmpty) {
        final List<dynamic> sessionsList = jsonDecode(sessionsJson);
        final restoredSessions = sessionsList
            .map((json) => ActiveSession.fromJson(json as Map<String, dynamic>))
            .toList();
        final sessions = _pruneRestoredSessions(restoredSessions);
        state = sessions;
        appLogger.i('Loaded ${sessions.length} active sessions from storage');
      }
    } catch (e) {
      appLogger.e('Failed to load active sessions: $e');
    }
  }

  List<ActiveSession> _pruneRestoredSessions(List<ActiveSession> sessions) {
    if (sessions.isEmpty) return sessions;

    try {
      final snapshotJson = _prefs.getString(liveSessionSnapshotPrefsKey);
      if (snapshotJson == null || snapshotJson.isEmpty) {
        if (sessions.isNotEmpty) {
          appLogger.i(
              'Dropping stale restored active sessions with no live snapshot');
          unawaited(_prefs.remove(_activeSessionsKey));
        }
        return const [];
      }

      final snapshot = LiveSessionSnapshot.fromJson(
        jsonDecode(snapshotJson) as Map<String, dynamic>,
      );
      if (snapshot.transport == 'ble') {
        appLogger.i(
          'Dropping restored BLE active sessions after cold launch '
          '(session=${snapshot.sessionId})',
        );
        unawaited(_prefs.remove(_activeSessionsKey));
        unawaited(_prefs.remove(liveSessionSnapshotPrefsKey));
        return const [];
      }
      final filtered = sessions
          .where((session) => session.id == snapshot.sessionId)
          .toList();
      if (filtered.length != sessions.length) {
        appLogger.i(
          'Pruned restored active sessions to snapshot-backed session=${snapshot.sessionId}',
        );
        unawaited(_saveSessionsList(filtered));
      }
      return filtered;
    } catch (e) {
      appLogger.w('Failed to reconcile restored active sessions: $e');
      return const [];
    }
  }

  Future<void> _saveActiveSessions() async {
    await _saveSessionsList(state);
  }

  Future<void> _saveSessionsList(List<ActiveSession> sessions) async {
    try {
      final sessionsJson = jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      );
      await _prefs.setString(_activeSessionsKey, sessionsJson);
      appLogger.i('Saved ${sessions.length} active sessions to storage');
    } catch (e) {
      appLogger.e('Failed to save active sessions: $e');
    }
  }

  bool _isLiveStatus(SessionStatus status) {
    return status == SessionStatus.running || status == SessionStatus.paused;
  }

  bool _hasLiveDeviceStatuses(Map<String, SessionStatus> deviceStatuses) {
    return deviceStatuses.values.any(_isLiveStatus);
  }

  bool _shouldKeepSession(ActiveSession session) {
    return _isLiveStatus(session.status) ||
        _hasLiveDeviceStatuses(session.deviceStatuses);
  }

  List<String> _liveDeviceIds(Map<String, SessionStatus> deviceStatuses) {
    return deviceStatuses.entries
        .where((entry) => _isLiveStatus(entry.value))
        .map((entry) => entry.key)
        .toList();
  }

  Future<String> createSession({
    String? sessionId,
    required String protocolId,
    required String protocolName,
    required List<String> deviceIds,
    required String transport,
    List<Map<String, String>> protocolPlusBindings = const [],
    // The session's real, delay/cycle-adjusted total duration. THIS WAS
    // NEVER ACTUALLY SET ANYWHERE — every ActiveSession silently defaulted
    // to totalDurationSeconds=0, which meant nothing that reads this field
    // to decide "is this session overdue" (the outcome-gate watchdog) could
    // ever fire, for any session, ever. Pass the real value from the caller.
    int totalDurationSeconds = 0,
  }) async {
    if (sessionId != null) {
      for (final session in state) {
        if (session.id == sessionId) {
          appLogger.i('Session already exists for ID, returning: $sessionId');
          // A caller that now has the real duration (and the earlier
          // creator didn't) should still get it recorded — e.g. the
          // launch-time call races the screen's own bootstrap call.
          if (totalDurationSeconds > 0 &&
              session.totalDurationSeconds <= 0) {
            state = [
              for (final s in state)
                if (s.id == sessionId)
                  s.copyWith(totalDurationSeconds: totalDurationSeconds)
                else
                  s,
            ];
            unawaited(_saveActiveSessions());
          }
          return sessionId;
        }
      }
    }

    final newSessionId = sessionId ?? _uuid.v4();
    final now = DateTime.now();

    final newSession = ActiveSession(
      id: newSessionId,
      protocolId: protocolId,
      protocolName: protocolName,
      deviceIds: deviceIds,
      transport: transport,
      createdAt: now,
      status: SessionStatus.running,
      deviceStatuses: {for (final id in deviceIds) id: SessionStatus.running},
      deviceNames: {},
      protocolPlusBindings: protocolPlusBindings,
      totalDurationSeconds: totalDurationSeconds,
    );

    state = [...state, newSession];
    await _saveActiveSessions();

    appLogger.i(
        'Created new active session: $newSessionId with ${deviceIds.length} devices '
        '(totalDurationSeconds=$totalDurationSeconds)');
    return newSessionId;
  }

  Future<void> updateSessionStatus(
      String sessionId, SessionStatus status) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession = state[sessionIndex].copyWith(status: status);
    if (!_shouldKeepSession(updatedSession)) {
      state = state.where((s) => s.id != sessionId).toList();
      await _saveActiveSessions();
      appLogger.i('Removed terminal active session: $sessionId');
      return;
    }

    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
  }

  Future<void> updateDeviceStatuses(
      String sessionId, Map<String, SessionStatus> deviceStatuses) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        state[sessionIndex].copyWith(deviceStatuses: deviceStatuses);
    if (!_shouldKeepSession(updatedSession)) {
      state = state.where((s) => s.id != sessionId).toList();
      await _saveActiveSessions();
      appLogger.i('Removed terminal active session: $sessionId');
      return;
    }

    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
  }

  /// Persist the Protocol Plus socket bindings onto an existing session. The
  /// session screen now opens before server registration completes, so the
  /// bindings (needed to re-attach the socket / stop the server schedule when
  /// re-opening from history) are written in once they're known. No-op if the
  /// session isn't tracked yet.
  Future<void> updateProtocolPlusBindings(
      String sessionId, List<Map<String, String>> bindings) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        state[sessionIndex].copyWith(protocolPlusBindings: bindings);
    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
    appLogger.i(
        'Updated Protocol Plus bindings (${bindings.length}) for $sessionId');
  }

  Future<void> updateDeviceNames(
      String sessionId, Map<String, String> deviceNames) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        state[sessionIndex].copyWith(deviceNames: deviceNames);
    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
  }

  Future<void> updateSessionProgress(
      String sessionId, int elapsedSeconds) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        state[sessionIndex].copyWith(elapsedSeconds: elapsedSeconds);
    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
  }

  Future<void> removeSession(String sessionId) async {
    state = state.where((s) => s.id != sessionId).toList();
    await _saveActiveSessions();
    appLogger.i('Removed active session: $sessionId');
  }

  List<String> getBusyDevices() {
    final busyDevices = <String>{};
    for (final session in state) {
      if (session.status == SessionStatus.running ||
          session.status == SessionStatus.paused) {
        busyDevices.addAll(_liveDeviceIds(session.deviceStatuses));
      }
    }
    return busyDevices.toList();
  }

  bool isDeviceBusy(String deviceId) {
    return getBusyDevices().contains(deviceId);
  }

  ActiveSession? getSessionById(String sessionId) {
    try {
      return state.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  List<ActiveSession> getActiveSessions() {
    return state
        .where((s) =>
            s.status == SessionStatus.running ||
            s.status == SessionStatus.paused)
        .toList();
  }
}
