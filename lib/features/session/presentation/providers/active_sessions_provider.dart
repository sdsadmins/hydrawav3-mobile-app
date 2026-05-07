import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/storage/preferences.dart';
import '../../domain/active_session_model.dart';
import '../../services/background_session_runtime.dart';

final activeSessionsProvider =
    StateNotifierProvider<ActiveSessionsNotifier, List<ActiveSession>>((ref) {
  return ActiveSessionsNotifier(ref.read(sharedPreferencesProvider));
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

  Future<String> createSession({
    String? sessionId,
    required String protocolId,
    required String protocolName,
    required List<String> deviceIds,
    required String transport,
  }) async {
    if (sessionId != null) {
      for (final session in state) {
        if (session.id == sessionId) {
          appLogger.i('Session already exists for ID, returning: $sessionId');
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
    );

    state = [...state, newSession];
    await _saveActiveSessions();

    appLogger.i(
        'Created new active session: $newSessionId with ${deviceIds.length} devices');
    return newSessionId;
  }

  Future<void> updateSessionStatus(
      String sessionId, SessionStatus status) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession = state[sessionIndex].copyWith(status: status);
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
    state = [
      ...state.sublist(0, sessionIndex),
      updatedSession,
      ...state.sublist(sessionIndex + 1),
    ];
    await _saveActiveSessions();
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
        busyDevices.addAll(session.deviceIds);
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
