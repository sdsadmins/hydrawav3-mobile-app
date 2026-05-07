import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/logger.dart';
import '../domain/active_session_model.dart';

final activeSessionRepositoryProvider =
    Provider<ActiveSessionRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

class ActiveSessionRepository {
  final SharedPreferences _prefs;
  final Uuid _uuid = const Uuid();
  static const _activeSessionsKey = 'active_sessions';

  ActiveSessionRepository(this._prefs);

  Future<List<ActiveSession>> getActiveSessions() async {
    try {
      final sessionsJson = _prefs.getString(_activeSessionsKey) ?? '[]';
      if (sessionsJson.isNotEmpty) {
        final List<dynamic> sessionsList = jsonDecode(sessionsJson);
        final sessions = sessionsList
            .map((json) => ActiveSession.fromJson(json as Map<String, dynamic>))
            .toList();
        appLogger.i('Loaded ${sessions.length} active sessions from storage');
        return sessions;
      }
      return [];
    } catch (e) {
      appLogger.e('Failed to load active sessions: $e');
      return [];
    }
  }

  Future<void> saveActiveSessions(List<ActiveSession> sessions) async {
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

    final currentSessions = await getActiveSessions();
    final updatedSessions = [...currentSessions, newSession];
    await saveActiveSessions(updatedSessions);

    appLogger.i(
        'Created new active session: $sessionId with ${deviceIds.length} devices');
    return sessionId;
  }

  Future<void> updateSessionStatus(
      String sessionId, SessionStatus status) async {
    final sessions = await getActiveSessions();
    final sessionIndex = sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession = sessions[sessionIndex].copyWith(status: status);
    sessions[sessionIndex] = updatedSession;
    await saveActiveSessions(sessions);
  }

  Future<void> updateDeviceStatuses(
      String sessionId, Map<String, SessionStatus> deviceStatuses) async {
    final sessions = await getActiveSessions();
    final sessionIndex = sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        sessions[sessionIndex].copyWith(deviceStatuses: deviceStatuses);
    sessions[sessionIndex] = updatedSession;
    await saveActiveSessions(sessions);
  }

  Future<void> updateDeviceNames(
      String sessionId, Map<String, String> deviceNames) async {
    final sessions = await getActiveSessions();
    final sessionIndex = sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        sessions[sessionIndex].copyWith(deviceNames: deviceNames);
    sessions[sessionIndex] = updatedSession;
    await saveActiveSessions(sessions);
  }

  Future<void> updateSessionProgress(
      String sessionId, int elapsedSeconds) async {
    final sessions = await getActiveSessions();
    final sessionIndex = sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedSession =
        sessions[sessionIndex].copyWith(elapsedSeconds: elapsedSeconds);
    sessions[sessionIndex] = updatedSession;
    await saveActiveSessions(sessions);
  }

  Future<void> removeSession(String sessionId) async {
    final sessions = await getActiveSessions();
    final updatedSessions = sessions.where((s) => s.id != sessionId).toList();
    await saveActiveSessions(updatedSessions);
    appLogger.i('Removed active session: $sessionId');
  }

  Future<List<String>> getBusyDevices() async {
    final sessions = await getActiveSessions();
    final busyDevices = <String>{};
    for (final session in sessions) {
      if (session.status == SessionStatus.running ||
          session.status == SessionStatus.paused) {
        busyDevices.addAll(session.deviceIds);
      }
    }
    return busyDevices.toList();
  }

  Future<bool> isDeviceBusy(String deviceId) async {
    final busyDevices = await getBusyDevices();
    return busyDevices.contains(deviceId);
  }

  Future<ActiveSession?> getSessionById(String sessionId) async {
    final sessions = await getActiveSessions();
    try {
      return sessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  Future<List<ActiveSession>> getActiveRunningSessions() async {
    final sessions = await getActiveSessions();
    return sessions
        .where((s) =>
            s.status == SessionStatus.running ||
            s.status == SessionStatus.paused)
        .toList();
  }
}
