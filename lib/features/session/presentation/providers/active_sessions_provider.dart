import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/storage/preferences.dart';
import '../../domain/active_session_model.dart';

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
        final sessions = sessionsList
            .map((json) => ActiveSession.fromJson(json as Map<String, dynamic>))
            .toList();
        state = sessions;
        appLogger.i('Loaded ${sessions.length} active sessions from storage');
      }
    } catch (e) {
      appLogger.e('Failed to load active sessions: $e');
    }
  }

  Future<void> _saveActiveSessions() async {
    try {
      final sessionsJson = jsonEncode(
        state.map((session) => session.toJson()).toList(),
      );
      await _prefs.setString(_activeSessionsKey, sessionsJson);
      appLogger.i('Saved ${state.length} active sessions to storage');
    } catch (e) {
      appLogger.e('Failed to save active sessions: $e');
    }
  }

  Future<String> createSession({
    required String protocolId,
    required String protocolName,
    required List<String> deviceIds,
    required String transport,
  }) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();

    final newSession = ActiveSession(
      id: sessionId,
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
        'Created new active session: $sessionId with ${deviceIds.length} devices');
    return sessionId;
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
