import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/active_session_model.dart';
import '../../services/sessions_socket.dart';

/// The org-wide live-session feed — the single source of truth for which
/// sessions are running, on mobile as on the web. Backed by the backend
/// `GET /sessions/active/:org` snapshot, the `/sessions` socket lifecycle
/// events, and a 1s active-poll for per-device timing + sun/moon (all values
/// taken verbatim from the backend; nothing is computed on-device).
///
/// Holds MULTIPLE concurrent sessions, each with its full list of devices.
final liveSessionsProvider =
    StateNotifierProvider<LiveSessionsNotifier, List<ActiveSession>>((ref) {
  final notifier = LiveSessionsNotifier(ref);
  ref.onDispose(notifier.stop);
  return notifier;
});

class LiveSessionsNotifier extends StateNotifier<List<ActiveSession>> {
  final Ref _ref;
  io.Socket? _socket;
  Timer? _pollTimer;
  String? _orgId;

  /// Consecutive failed active-fetches. After a couple in a row we drop any
  /// cached sessions (web parity: the web clears its list whenever the fetch
  /// fails) so a device can't stay "in use" forever when the `/sessions/active`
  /// poll starts failing (e.g. 401) — while still tolerating a single transient
  /// blip so a genuinely-live run doesn't flicker on the 1s poll.
  int _consecutiveFetchFailures = 0;

  /// Backend session ids this phone started (it owns the live engine). Used to
  /// flag sessions `isOwn` so the UI can gate control (own / foreign-WiFi /
  /// foreign-BLE). Survives refetches.
  final Set<String> _ownedSessionIds = <String>{};

  LiveSessionsNotifier(this._ref) : super(const []);

  /// Begin tracking live sessions for [orgId]: initial fetch + socket + poll.
  /// Safe to call repeatedly; restarts cleanly if the org changes.
  Future<void> start(String orgId) async {
    if (orgId.isEmpty) return;
    if (_orgId == orgId && _socket != null) return;
    appLogger.i('LiveSessions: start(org=$orgId)');
    await stop(clearOwned: false);
    _orgId = orgId;
    await _fetchActive();
    _connectSocket();
    _startPolling();
  }

  /// Tear down socket + poll and clear state. [clearOwned] keeps the owned-set
  /// across an org restart but clears it on a full logout.
  Future<void> stop({bool clearOwned = true}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _socket?.dispose();
    _socket = null;
    _orgId = null;
    _consecutiveFetchFailures = 0;
    if (clearOwned) _ownedSessionIds.clear();
    if (mounted) state = const [];
  }

  /// Mark a backend session as owned by this phone (called from the launch
  /// flow once the backend sessionId is known). Re-flags any matching session
  /// already in state.
  void markOwned(String sessionId) {
    if (sessionId.isEmpty) return;
    _ownedSessionIds.add(sessionId);
    if (!mounted) return;
    state = [
      for (final s in state) s.id == sessionId ? s.copyWith(isOwn: true) : s,
    ];
  }

  Future<void> _fetchActive() async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final dio = _ref.read(nodeDioProvider);
      final resp =
          await dio.get<Map<String, dynamic>>(ApiEndpoints.sessionsActive(orgId));
      _consecutiveFetchFailures = 0;
      // Treat a missing/odd payload as "no active sessions" (web parity: the web
      // replaces its list with whatever the fetch returns), NOT as a reason to
      // keep stale sessions around.
      final sessions = resp.data?['sessions'] as List<dynamic>?;
      final mapped = <ActiveSession>[];
      for (final raw in (sessions ?? const <dynamic>[])) {
        if (raw is! Map) continue;
        final s = _mapSession(raw.cast<String, dynamic>());
        if (s != null) mapped.add(s);
      }
      // Avoid needless rebuilds (nav badge / History list / timer screen all
      // watch this): when there's nothing live and nothing changed, don't emit.
      if (mapped.isEmpty && state.isEmpty) return;
      if (mounted) state = mapped;
    } catch (e) {
      appLogger.d('LiveSessions: active fetch failed: $e');
      _consecutiveFetchFailures++;
      // The web clears its session list on any failed fetch. Mirror that intent
      // here, but only after a couple of consecutive failures so a single
      // transient blip doesn't flicker a genuinely-live run on the 1s poll —
      // otherwise stale sessions keep devices wrongly marked "In use".
      if (_consecutiveFetchFailures >= 2 && state.isNotEmpty && mounted) {
        appLogger.w('LiveSessions: clearing stale sessions after '
            '$_consecutiveFetchFailures consecutive fetch failures');
        state = const [];
      }
    }
  }

  void _connectSocket() {
    unawaited(_doConnectSocket());
  }

  Future<void> _doConnectSocket() async {
    try {
      final token = await _ref.read(secureStorageProvider).getAccessToken();
      final socket =
          SessionsSocket.buildSocket(token: token, namespace: '/sessions');
      _socket = socket;

      socket.onConnect((_) {
        SessionsSocket.subscribeOrganization(socket, _orgId);
        appLogger.i('LiveSessions: socket connected, subscribed org-$_orgId');
      });
      socket.onDisconnect((r) => appLogger.w('LiveSessions: disconnected ($r)'));
      socket.onConnectError(
          (e) => appLogger.e('LiveSessions: connect error: $e'));

      socket.on('session-event', (data) {
        if (data is! Map) return;
        final type = data['type']?.toString();
        switch (type) {
          case 'SESSION_STARTED':
            // The event carries only sessionId; the active endpoint has the
            // full device/protocol/timing data — refetch.
            unawaited(_fetchActive());
            break;
          case 'SESSION_STOPPED':
            final sid = data['sessionId']?.toString();
            if (sid != null && mounted) {
              state = state.where((s) => s.id != sid).toList();
            }
            break;
          case 'SESSION_PAUSED':
          case 'SESSION_RESUMED':
            final sid = data['sessionId']?.toString();
            if (sid != null && mounted) {
              final next = type == 'SESSION_PAUSED'
                  ? SessionStatus.paused
                  : SessionStatus.running;
              state = [
                for (final s in state)
                  s.id == sid ? s.copyWith(status: next) : s,
              ];
            }
            break;
          case 'SESSION_UPDATED':
            _applySessionUpdated(data.cast<String, dynamic>());
            break;
        }
      });

      socket.connect();
    } catch (e) {
      appLogger.e('LiveSessions: socket setup failed: $e');
    }
  }

  /// Apply per-device sun/moon from a SESSION_UPDATED event onto the matching
  /// session's devices (matched by macAddress / slotId / deviceName).
  void _applySessionUpdated(Map<String, dynamic> data) {
    if (!mounted) return;
    final sid = data['sessionId']?.toString();
    final devices = data['devices'] as List<dynamic>?;
    if (sid == null || devices == null) return;

    String? sunFor(LiveDeviceState d) {
      for (final dev in devices) {
        if (dev is! Map) continue;
        final m = dev.cast<String, dynamic>();
        if (_matchesDevice(d, m)) return m['sun']?.toString();
      }
      return null;
    }

    String? moonFor(LiveDeviceState d) {
      for (final dev in devices) {
        if (dev is! Map) continue;
        final m = dev.cast<String, dynamic>();
        if (_matchesDevice(d, m)) return m['moon']?.toString();
      }
      return null;
    }

    state = [
      for (final s in state)
        if (s.id != sid)
          s
        else
          s.copyWith(
            liveDevices: [
              for (final d in s.liveDevices)
                LiveDeviceState(
                  deviceId: d.deviceId,
                  deviceName: d.deviceName,
                  bodyPart: d.bodyPart,
                  protocol: d.protocol,
                  slotId: d.slotId,
                  status: d.status,
                  remainingSeconds: d.remainingSeconds,
                  elapsedSeconds: d.elapsedSeconds,
                  totalDurationSeconds: d.totalDurationSeconds,
                  sun: sunFor(d) ?? d.sun,
                  moon: moonFor(d) ?? d.moon,
                  transport: d.transport,
                ),
            ],
          ),
    ];
  }

  bool _matchesDevice(LiveDeviceState d, Map<String, dynamic> backend) {
    final mac = backend['macAddress']?.toString();
    final slot = backend['slotId']?.toString();
    final name = backend['deviceName']?.toString();
    return (mac != null && mac == d.deviceId) ||
        (slot != null && slot.isNotEmpty && slot == d.slotId) ||
        (name != null && name.isNotEmpty && name == d.deviceName);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _scheduleNextPoll();
  }

  /// Self-rescheduling poll with an adaptive interval: 1s while a session is
  /// live (so timers + sun/moon stay smooth), but a relaxed 5s when idle so the
  /// app isn't hitting the network and rebuilding every second for nothing.
  /// New sessions still appear instantly via the socket SESSION_STARTED event.
  void _scheduleNextPoll() {
    final interval =
        state.isEmpty ? const Duration(seconds: 5) : const Duration(seconds: 1);
    _pollTimer = Timer(interval, () async {
      await _fetchActive();
      if (_orgId != null && mounted) _scheduleNextPoll();
    });
  }

  ActiveSession? _mapSession(Map<String, dynamic> json) {
    final sessionId = json['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) return null;
    final rawDevices = json['devices'] as List<dynamic>? ?? const [];

    final liveDevices = <LiveDeviceState>[];
    final deviceIds = <String>[];
    final deviceStatuses = <String, SessionStatus>{};
    final deviceNames = <String, String>{};
    var anyBle = false;

    for (final raw in rawDevices) {
      if (raw is! Map) continue;
      final d = raw.cast<String, dynamic>();
      final bluetoothId = d['bluetoothId']?.toString();
      final mac = d['macAddress']?.toString();
      final isBle = bluetoothId != null && bluetoothId.isNotEmpty;
      if (isBle) anyBle = true;
      final deviceId = (isBle ? bluetoothId : mac) ?? mac ?? bluetoothId ?? '';
      if (deviceId.isEmpty) continue;
      final status = _statusFromString(d['status']?.toString());
      final name = d['deviceName']?.toString();
      deviceIds.add(deviceId);
      deviceStatuses[deviceId] = status;
      if (name != null && name.isNotEmpty) deviceNames[deviceId] = name;
      liveDevices.add(LiveDeviceState(
        deviceId: deviceId,
        deviceName: name,
        bodyPart: d['bodyPart']?.toString(),
        protocol: d['protocol']?.toString(),
        slotId: d['slotId']?.toString(),
        status: status,
        remainingSeconds: (d['remainingSeconds'] as num?)?.toInt() ?? 0,
        elapsedSeconds: (d['elapsedSeconds'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (d['totalDurationSeconds'] as num?)?.toInt() ?? 0,
        sun: d['sun']?.toString(),
        moon: d['moon']?.toString(),
        transport: isBle ? 'ble' : 'wifi',
      ));
    }

    final startTime = DateTime.tryParse(json['startTime']?.toString() ?? '') ??
        DateTime.now();
    final protocolName = liveDevices.isNotEmpty
        ? (liveDevices.first.protocol ?? 'Protocol')
        : (json['clientName']?.toString() ?? 'Session');

    return ActiveSession(
      id: sessionId,
      protocolId: '',
      protocolName: protocolName,
      deviceIds: deviceIds,
      transport: anyBle ? 'ble' : 'wifi',
      createdAt: startTime,
      status: _statusFromString(json['status']?.toString()),
      deviceStatuses: deviceStatuses,
      deviceNames: deviceNames,
      liveDevices: liveDevices,
      isOwn: _ownedSessionIds.contains(sessionId),
    );
  }

  SessionStatus _statusFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'running':
        return SessionStatus.running;
      case 'paused':
        return SessionStatus.paused;
      case 'stopped':
        return SessionStatus.stopped;
      case 'completed':
        return SessionStatus.completed;
      default:
        return SessionStatus.running;
    }
  }
}
