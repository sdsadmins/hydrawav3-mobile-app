import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/logger.dart';
import '../../../ble/services/ble_connector.dart';
import '../../domain/active_session_model.dart';
import '../../domain/session_model.dart' as session_model;
import '../../services/session_engine.dart';
import '../../services/session_sync_service.dart';
import '../../services/sessions_socket.dart';
import 'active_sessions_provider.dart';
import 'pending_outcomes_provider.dart';

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

/// A session counts as live while the backend feed still carries it and it
/// hasn't been stopped — that includes fully-paused and completed runs, which
/// linger until someone hits Stop All.
bool _isVisibleStatus(SessionStatus status) =>
    status == SessionStatus.running ||
    status == SessionStatus.paused ||
    status == SessionStatus.completed;

bool isVisibleActiveSession(ActiveSession session) {
  if (_isVisibleStatus(session.status)) return true;
  for (final deviceId in session.deviceIds) {
    if (_isVisibleStatus(
        session.deviceStatuses[deviceId] ?? SessionStatus.idle)) {
      return true;
    }
  }
  return false;
}

/// BACKEND session ids of runs THIS phone has already finished but that the feed
/// still carries.
///
/// The backend keeps a session in `GET /sessions/active` until it is explicitly
/// stopped, and a `completed` run deliberately stays on screen until someone
/// hits Stop All. So the feed alone can't tell "still running" from "over" — and
/// every surface that reads it went on claiming a finished run was *running*.
///
/// The local engine is the authority for a run we own: `stopped` / `completed`
/// there means it is over, whatever the feed still says. A run awaiting its
/// post-session review counts as finished too.
///
/// These sessions are NOT hidden — they stay on the banner as the way back into
/// the run (to review it, or to Stop All and clear it). They're just labelled
/// honestly instead of being announced as live.
///
/// Foreign runs (no local mapping) never appear here — the feed is the only
/// thing that knows anything about them.
final finishedOwnSessionIdsProvider = Provider<Set<String>>((ref) {
  final sessions = ref.watch(liveSessionsProvider);
  if (sessions.isEmpty) return const <String>{};

  final backendToLocal = ref.watch(ownBackendToLocalSessionProvider);
  final awaitingReview = <String>{
    for (final e in ref.watch(pendingOutcomesProvider))
      if (e.answers == null) e.sessionId,
  };

  final finished = <String>{};
  for (final session in sessions) {
    final localId = backendToLocal[session.id];
    if (localId == null) continue; // foreign run — the feed is all we have
    if (awaitingReview.contains(localId)) {
      finished.add(session.id);
      continue;
    }
    // `.select` so this doesn't recompute on every timer tick of a live run.
    final status = ref.watch(
      sessionEngineFamilyProvider(localId).select((s) => s.status),
    );
    if (status == session_model.SessionStatus.stopped ||
        status == session_model.SessionStatus.completed) {
      finished.add(session.id);
    }
  }
  return finished;
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

  /// Consecutive polls an OWNED session has been missing from the feed.
  /// [_reconcileOwnedStopped] now sends a REAL BLE stop write to the physical
  /// device (see below), so acting on a single missing poll — a transient
  /// backend read-lag or a momentarily short session array — would halt a
  /// still-legitimately-running treatment on real hardware over nothing more
  /// than a one-off glitch. Same 2-in-a-row confirmation as
  /// [_consecutiveFetchFailures] just below, for the same reason.
  final Map<String, int> _missingOwnedStreak = {};

  /// `sessionId|deviceId` pairs we've asked the backend to stop because their
  /// countdown ran past zero without anyone closing them out, mapped to WHEN
  /// we last tried. ANY phone watching the org feed does this sweep — not
  /// just the one that started the run — so a device doesn't stay locked
  /// "In use" forever when the originating phone's app died, backgrounded, or
  /// dropped BLE before it could post its own stop.
  ///
  /// Retried on a cooldown ([_overrunRetryCooldown]) rather than once ever: a
  /// single failed POST (a transient network blip, a momentary backend 5xx)
  /// used to permanently block further attempts for that pair until either
  /// the session happened to leave the feed on its own or the app restarted
  /// and lost this map entirely — silently reverting to the exact stuck-forever
  /// bug this sweep exists to fix. Entries for sessions no longer in the feed
  /// are pruned each fetch so this can't grow unbounded across a long-lived
  /// app session.
  final Map<String, DateTime> _overrunStopAttempted = {};

  static const Duration _overrunRetryCooldown = Duration(seconds: 20);

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

  /// A run THIS phone started (owns the local engine) was stopped elsewhere —
  /// via the web or another device (backend `SESSION_STOPPED`, or the session
  /// dropping out of the active feed). Tear down the local tracking so the
  /// device leaves the "In use" set and the local engine/timer + background
  /// service stop. If the run was already stopped LOCALLY, its normal stop
  /// flow removed it from [activeSessionsProvider] first — we skip so we never
  /// disturb the local completed/Stop-All (post-session questions) UI.
  void _reconcileOwnedStopped(String backendSid) {
    if (!_ownedSessionIds.remove(backendSid)) return; // not an owned run
    final localId = _ref.read(ownBackendToLocalSessionProvider)[backendSid];
    _ref
        .read(ownBackendToLocalSessionProvider.notifier)
        .update((m) => {...m}..remove(backendSid));
    if (localId == null) return;

    final backendToLocal = _ref.read(ownBackendToLocalSessionProvider);
    final stillHasOwnedSibling = _ownedSessionIds.any((sessionId) {
      if (sessionId == backendSid) return false;
      return backendToLocal[sessionId] == localId;
    });
    if (stillHasOwnedSibling) {
      appLogger.i(
        'LiveSessions: owned session $backendSid stopped, but local session '
        '$localId still has other owned Plus bindings” keeping it alive',
      );
      return;
    }

    final localSession =
        _ref.read(activeSessionsProvider.notifier).getSessionById(localId);
    if (localSession == null) return; // already torn down by the local stop flow

    // A BLE unit is only reachable over the link THIS phone holds — the
    // backend and any other client (web, another phone) can clear the
    // session record but cannot physically reach the device. So a stop
    // that arrived here from elsewhere (someone else's Stop All, an admin
    // action) must still send the real stop write, or the hardware keeps
    // running with its backend lock already cleared and nothing left to
    // ever tell it to stop. `reset()` alone used to just assume the unit
    // was already off, which was only ever true for a WiFi run.
    if (localSession.transport == 'ble') {
      final connector = _ref.read(bleConnectorProvider);
      for (final deviceId in localSession.deviceIds) {
        if (!connector.isConnected(deviceId)) continue;
        unawaited(connector.writeToDevice(deviceId, [0x03]).catchError((e) {
          appLogger.w('LiveSessions: BLE stop write to $deviceId failed: $e');
          return false;
        }));
      }
    }
    try {
      // The backend noticing a session ended (its own duration tracking, or
      // the session dropping off the active feed) is just as real a "this
      // session is over" signal as any local detection — and can legitimately
      // WIN THE RACE against the app's own local completion logic, arriving
      // here first. Queue the outcome BEFORE reset() wipes the engine's
      // protocol/deviceIds clean, or a session that ends this way would
      // never make it into "needs review" / history at all — this was a
      // real, previously-undiscovered gap, not a hypothetical one.
      _ref
          .read(sessionEngineFamilyProvider(localId).notifier)
          .enqueuePendingOutcome();
    } catch (_) {}
    try {
      _ref.read(sessionEngineFamilyProvider(localId).notifier).reset();
    } catch (_) {}
    unawaited(
        _ref.read(activeSessionsProvider.notifier).removeSession(localId));
    appLogger.i(
      'LiveSessions: owned session $backendSid stopped remotely — freed local '
      'session $localId',
    );
  }

  Future<void> _fetchActive() async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final dio = _ref.read(nodeDioProvider);
      final resp = await dio
          .get<Map<String, dynamic>>(ApiEndpoints.sessionsActive(orgId));
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
      // Owned runs that WERE live in the feed and are now gone were stopped
      // elsewhere (web/other device). Reconcile them so the device frees even if
      // the SESSION_STOPPED socket event was missed. (Only diff against the
      // previous live state, so a just-started own run not yet in the feed is
      // never torn down.) Requires 2 consecutive misses — see
      // [_missingOwnedStreak] — before actually acting on it.
      final missingNow = <String>{
        for (final s in state)
          if (_ownedSessionIds.contains(s.id) &&
              !mapped.any((m) => m.id == s.id))
            s.id,
      };
      _missingOwnedStreak.removeWhere((id, _) => !missingNow.contains(id));
      final goneOwned = <String>[];
      for (final id in missingNow) {
        final streak = (_missingOwnedStreak[id] ?? 0) + 1;
        if (streak >= 2) {
          goneOwned.add(id);
          _missingOwnedStreak.remove(id);
        } else {
          _missingOwnedStreak[id] = streak;
        }
      }
      _sweepOverrunDevices(mapped);
      // Avoid needless rebuilds (nav badge / History list / timer screen all
      // watch this): when there's nothing live and nothing changed, don't emit.
      if (mapped.isEmpty && state.isEmpty && goneOwned.isEmpty) return;
      if (mounted) state = mapped;
      for (final sid in goneOwned) {
        _reconcileOwnedStopped(sid);
      }
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
    _retryUnresolvedOwnBackendStops();
  }

  /// Backend countdowns don't stop themselves: a device whose countdown hit
  /// zero stays `running`/`paused` in the feed until some client explicitly
  /// posts a stop for it. Normally that's the phone whose local engine drove
  /// the run — but if that phone's app died, backgrounded, or dropped BLE
  /// before the terminal transition fired, nobody ever does it, and the
  /// device is locked "In use" forever with nothing else able to release it
  /// (there's no local engine anywhere to retry the stop, unlike
  /// [_retryUnresolvedOwnBackendStops] above, which only covers OWNED runs).
  ///
  /// So ANY phone watching the org feed posts the stop once it sees a device
  /// run past zero — self-healing across phones, not reliant on the
  /// originating one surviving. One attempt per `sessionId|deviceId` pair per
  /// app session is enough; if the POST fails the next poll's still-overrun
  /// device tries again next cycle since the key is pruned once the session
  /// leaves the feed (below), not once the stop is attempted.
  void _sweepOverrunDevices(List<ActiveSession> sessions) {
    final stillLive = <String>{};
    final now = DateTime.now();
    for (final session in sessions) {
      for (final dev in session.liveDevices) {
        final live = dev.status == SessionStatus.running ||
            dev.status == SessionStatus.paused;
        if (!live) continue;
        final key = '${session.id}|${dev.deviceId}';
        stillLive.add(key);
        // `totalDurationSeconds > 0` guards a device whose timing just hasn't
        // been populated yet (a fresh join reports 0/0 for a beat) from being
        // read as "ran past zero" the instant it appears.
        final overran = dev.totalDurationSeconds > 0 && dev.remainingSeconds <= 0;
        if (!overran) continue;
        final lastAttempt = _overrunStopAttempted[key];
        if (lastAttempt != null &&
            now.difference(lastAttempt) < _overrunRetryCooldown) {
          continue;
        }
        _overrunStopAttempted[key] = now;
        appLogger.w(
          'LiveSessions: ${dev.deviceId} on ${session.id} ran past zero '
          'without stopping — posting stop to release it',
        );
        unawaited(_ref
            .read(sessionSyncServiceProvider)
            .stopServerSessionDeviceByIdentity(
              session.id,
              dev.deviceId,
              slotId: dev.slotId,
              deviceName: dev.deviceName,
            ));
      }
    }
    _overrunStopAttempted.removeWhere((k, _) => !stillLive.contains(k));
  }

  /// Self-healing sweep for the "one failed backend-stop POST orphans the
  /// session forever" gap: piggybacked on this poll (already running for the
  /// whole app session, independent of which screen is open) rather than a
  /// new timer. Any local session whose engine flagged
  /// [SessionEngineState.backendStopUnresolved] gets another bounded retry —
  /// cheap when nothing is unresolved (just reads already-live providers, no
  /// extra network call).
  void _retryUnresolvedOwnBackendStops() {
    for (final session in _ref.read(activeSessionsProvider)) {
      final unresolved = _ref.read(
        sessionEngineFamilyProvider(session.id)
            .select((s) => s.backendStopUnresolved),
      );
      if (unresolved) {
        unawaited(_ref
            .read(sessionEngineFamilyProvider(session.id).notifier)
            .retryBackendStopIfNeeded());
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
      socket
          .onDisconnect((r) => appLogger.w('LiveSessions: disconnected ($r)'));
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
              // If this phone owns the run, free its local tracking so the
              // device stops showing "In use" when stopped from elsewhere.
              _reconcileOwnedStopped(sid);
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

    // Protocol Plus: the backend marks a stacked-sequence run with
    // `protocolPlusIsActive` + a `protocolPlus` object carrying the ordered
    // sub-protocol names and the inter-protocol delay. Parse it so any client
    // can render the sequence tracker for a Plus run (web parity), not only the
    // one that launched it.
    final pp = json['protocolPlus'];
    final ppActive = json['protocolPlusIsActive'] == true;
    final ppName =
        (pp is Map ? pp['template_name']?.toString() : null)?.trim() ?? '';
    final ppSequence = (pp is Map && pp['protocolName'] is List)
        ? (pp['protocolName'] as List)
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    final ppDelay = (pp is Map ? (pp['delay'] as num?)?.toInt() : null) ?? 0;

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
      protocolPlusActive: ppActive,
      protocolPlusName: ppName,
      protocolPlusSequence: ppSequence,
      protocolPlusDelaySeconds: ppDelay,
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
