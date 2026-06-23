import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../../musics/presentation/providers/music_provider.dart';
import '../../../musics/services/session_music_controller.dart';
import '../../services/session_engine.dart';
import '../../services/protocol_plus_controller.dart';
import '../../services/session_sync_service.dart';
import '../../domain/session_model.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart' as session_model;
import '../../../session/domain/active_session_model.dart' as active_session;
import '../../../session/data/session_repository.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/services/background_session_runtime.dart';
import '../../../session/services/wifi_remote_control.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String? sessionId;
  final String protocolId;
  final Protocol? protocol;
  final List<String> deviceIds;
  final Map<String, String> protocolByDeviceId;
  final bool skipEngineBootstrap;

  /// 'ble' or 'wifi'
  final String transport;

  /// Epoch ms when WiFi MQTT config last succeeded — aligns app timer with device.
  final int? sessionClockAnchorMs;

  final AdvancedSettings advancedSettings;
  final Map<String, AdvancedSettings> advancedSettingsByDevice;
  final String? delayedDeviceId;
  final bool wifiConfigAlreadyPublished;

  /// Protocol Plus wiring (null for a normal single-protocol run).
  /// When set, this screen opens the `/sessions` socket and applies each
  /// server `START_PROTOCOL` switch to the running engine.
  final String? protocolPlusId;
  final String? protocolPlusServerSessionId;
  final String? protocolPlusMac;

  /// Per-device Protocol Plus bindings for a multi-device session. When
  /// non-empty this takes precedence over the single [protocolPlusServerSessionId]
  /// / [protocolPlusMac] fields (which remain for the single-device path).
  final List<ProtocolPlusBinding> protocolPlusBindings;

  /// True when this is a Protocol Plus run whose server registration is still
  /// in flight at navigation time (the instant-UI launch). The screen then
  /// watches [protocolPlusBindingsProvider] and wires its socket when the
  /// bindings arrive, instead of receiving them up-front in [protocolPlusBindings].
  final bool protocolPlusPending;

  /// Live REMOTE VIEW of a foreign WiFi session (started on the web or another
  /// phone). When true, no local SessionEngine is bootstrapped — timers/pads/
  /// status come from the org-wide live feed ([liveSessionsProvider]) and
  /// Pause/Resume/Stop go through [wifiRemoteControlProvider]. [backendSessionId]
  /// is the live-feed session id to display.
  final bool remoteView;
  final String? backendSessionId;

  const SessionScreen({
    super.key,
    this.sessionId,
    required this.protocolId,
    this.protocol,
    required this.deviceIds,
    this.protocolByDeviceId = const {},
    this.transport = 'ble',
    this.sessionClockAnchorMs,
    this.advancedSettings = const AdvancedSettings(),
    this.advancedSettingsByDevice = const {},
    this.delayedDeviceId,
    this.skipEngineBootstrap = false,
    this.wifiConfigAlreadyPublished = false,
    this.protocolPlusId,
    this.protocolPlusServerSessionId,
    this.protocolPlusMac,
    this.protocolPlusBindings = const [],
    this.protocolPlusPending = false,
    this.remoteView = false,
    this.backendSessionId,
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen>
    with WidgetsBindingObserver {
  bool _bootstrapStarted = false;
  int _activeDevicePage = 0;
  ProviderSubscription<SessionEngineState>? _engineSub;
  ProviderSubscription<AsyncValue<Map<String, BleConnectionStatus>>>?
      _bleConnectionSub;
  bool _startingSession = false;
  bool _terminalSessionCleanupInFlight = false;
  String? _activeSessionId;
  String? _historySnapshotSessionId;
  late final String _engineKey;

  Timer? _padPollTimer;

  final Map<String, String> _deviceLabelById = {};

  /// Captured in initState so it can be disposed without touching `ref` later.
  ProtocolPlusController? _protocolPlusController;

  /// Session "Atmosphere" music — captured in initState so play/pause can be
  /// driven from lifecycle/status callbacks and stopped on dispose.
  SessionMusicController? _musicController;

  /// Whether the app is currently in the foreground. Music is foreground-only,
  /// so this gates playback alongside the session-running state.
  bool _isForeground = true;

  /// Guards the one-time socket connect (bindings can arrive synchronously via
  /// the widget or late via [protocolPlusBindingsProvider] — connect only once).
  bool _plusSocketConnected = false;

  /// The bindings this screen actually wired its socket with. For the instant-UI
  /// launch they arrive AFTER navigation, so they're tracked here to (a) persist
  /// onto the active session and (b) gate the server pause/resume/stop sync.
  List<ProtocolPlusBinding> _resolvedPlusBindings = const [];

  /// Subscription to the late-binding delivery provider (instant-UI launch).
  ProviderSubscription<List<ProtocolPlusBinding>>? _plusBindingsSub;

  /// Backend sessionId for a NORMAL (non-Plus) run. Arrives after launch via
  /// [normalServerSessionIdProvider] (the `/sessions/start` POST is async), so
  /// it's tracked here to drive backend pause/resume/stop for parity with web.
  String? _normalBackendSessionId;

  /// Subscription to the normal-run backend sessionId delivery provider.
  ProviderSubscription<String?>? _normalServerIdSub;

  /// One-shot guard so the normal-run backend stop POST fires at most once.
  bool _normalServerStopped = false;

  /// One-shot guard for the pad-poll diagnostic log.
  bool _padDiagLogged = false;

  /// Whether this run's backend session has appeared in the live feed — lets us
  /// tell "not started yet" from "stopped remotely" (web/another device).
  bool _backendSessionSeen = false;

  /// Last backend status we reconciled, so remote pause/resume is applied only
  /// on an actual transition (edge-triggered) — never level-triggered off the
  /// 1s poll, which would fight a local pause during the backend round-trip.
  active_session.SessionStatus? _lastRemoteStatus;

  /// Last reconcile log signature, to log transitions without per-second spam.
  String? _lastReconcileSig;

  /// Listener that reconciles the local engine with remote stop/pause/resume
  /// for a normal run (Protocol Plus runs are reconciled by their controller).
  ProviderSubscription<List<active_session.ActiveSession>>? _liveSessionsSub;

  String _deviceLabel(String id) {
    final key = _normalizeMac(id);
    return _deviceLabelById[key] ?? id;
  }

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can reconcile the timer + restart its ticker
    // when the app returns to the foreground (screen was off / app backgrounded).
    WidgetsBinding.instance.addObserver(this);
    _musicController = ref.read(sessionMusicControllerProvider.notifier);
    _activeSessionId = _findMatchingActiveSessionId();
    _engineKey = _activeSessionId ?? _buildFallbackEngineKey();

    // REMOTE VIEW: this screen mirrors a foreign WiFi session from the org-wide
    // live feed — there is no local engine to bootstrap, listen to, or sync.
    // Just make sure the feed is running and load device labels; build() reads
    // everything from [liveSessionsProvider] and routes controls to the remote
    // control service. Keep the screen awake while viewing a live run.
    if (widget.remoteView) {
      unawaited(WakelockPlus.enable());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final orgId = ref.read(authStateProvider).selectedOrgId ??
            ref.read(authStateProvider).user?.organizationId;
        if (orgId != null && orgId.isNotEmpty) {
          ref.read(liveSessionsProvider.notifier).start(orgId);
        }
      });
      unawaited(_loadDeviceNames());
      return;
    }

    _engineSub = ref.listenManual<SessionEngineState>(
      sessionEngineFamilyProvider(_engineKey),
      (prev, next) {
        if (!mounted) return;
        final prevS = prev?.status;
        final nextS = next.status;
        _maybeSyncProtocolPlusServer(prevS, nextS);
        _maybeSyncNormalServer(prevS, nextS);
        final deviceStatusesChanged = prev == null
            ? next.deviceStatuses.isNotEmpty
            : !mapEquals(prev.deviceStatuses, next.deviceStatuses);
        final statusChanged = prevS != nextS;
        final nowActive =
            nextS == SessionStatus.running || nextS == SessionStatus.paused;
        final wasActive =
            prevS == SessionStatus.running || prevS == SessionStatus.paused;
        if (statusChanged) {
          _applyWakelockForStatus(nextS);
          // Music plays only while the session is actively running.
          _syncMusicToSession(nextS);
        }
        if (nowActive && !wasActive) {
          _startBackendPadPolling();
          unawaited(_ensureAndSyncFromEngineState(next));
        } else if (nowActive && (statusChanged || deviceStatusesChanged)) {
          unawaited(_ensureAndSyncFromEngineState(next));
        } else if (!nowActive && wasActive) {
          // Avoid setState while route is being popped/unmounted.
          _stopBackendPadPolling(fromDispose: true);
          unawaited(_handleTerminalSessionState(next));
        } else if (!nowActive &&
            (nextS == SessionStatus.stopped ||
                nextS == SessionStatus.completed)) {
          unawaited(_handleTerminalSessionState(next));
        }
      },
    );

    _bleConnectionSub =
        ref.listenManual<AsyncValue<Map<String, BleConnectionStatus>>>(
      bleConnectionStatesProvider,
      (prev, next) {
        if (!mounted || widget.transport != 'ble') return;
        final previousStates = prev?.valueOrNull;
        final nextStates = next.valueOrNull;
        if (previousStates == null || nextStates == null) return;

        for (final deviceId in widget.deviceIds) {
          final previousStatus = previousStates[deviceId];
          final currentStatus = nextStates[deviceId];
          if (!_isDisconnectTransition(previousStatus, currentStatus)) {
            continue;
          }
          unawaited(_handleBleDisconnect(deviceId));
        }
      },
    );

    // If the engine is already active before this screen finishes wiring up
    // listeners (common when coming from setup with skipEngineBootstrap=true),
    // ensure we still create + sync the active session so History can show it.
    unawaited(_ensureAndSyncFromEngineState(
      ref.read(sessionEngineFamilyProvider(_engineKey)),
    ));

    // Keep the screen awake if this screen opens onto an already-live session
    // (e.g. re-entering from setup with skipEngineBootstrap=true).
    _applyWakelockForStatus(
      ref.read(sessionEngineFamilyProvider(_engineKey)).status,
    );

    // Seed the music gate with the current session state (a track may already
    // be selected from a prior screen visit, and the session may be running).
    _syncMusicToSession(
      ref.read(sessionEngineFamilyProvider(_engineKey)).status,
    );

    Future<void> bootstrap() async {
      if (!mounted) return;
      if (_bootstrapStarted) return;
      _bootstrapStarted = true;
      if (widget.skipEngineBootstrap) return;

      final ctrl = ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
      final currentEngineState =
          ref.read(sessionEngineFamilyProvider(_engineKey));

      try {
        if (!mounted) return;

        final allActiveSessions = ref.read(activeSessionsProvider);
        final hasConflictingSession = allActiveSessions.any(
          (session) =>
              session.id != _activeSessionId &&
              _isLiveSession(session.status) &&
              session.deviceIds.any(widget.deviceIds.contains),
        );
        final targetProtocolId = widget.protocol?.id ?? widget.protocolId;
        final engineMatchesTarget = _areDeviceListsEqual(
                currentEngineState.deviceIds, widget.deviceIds) &&
            currentEngineState.protocol?.id == targetProtocolId;

        // If the engine for this session is already live (e.g. re-opening a
        // running WiFi / Protocol-Plus session from the active-sessions card),
        // never try to reload it — for a Plus run the loaded sub-protocol id
        // never equals the stack protocolId, so engineMatchesTarget is always
        // false and the reload path below would otherwise tear down the live
        // controls. Fall through to the re-sync so the controls re-attach.
        final engineAlreadyLive =
            currentEngineState.status == SessionStatus.running ||
                currentEngineState.status == SessionStatus.paused;

        if (hasConflictingSession) {
          appLogger.w(
            'Skipping engine bootstrap for session=$_engineKey due to device overlap',
          );
          return;
        }

        if (!engineAlreadyLive &&
            (!engineMatchesTarget ||
                currentEngineState.status == SessionStatus.idle)) {
          appLogger.i(
              'Loading new session into engine - devices: ${widget.deviceIds}');
          ctrl.prepareSession(
            deviceIds: widget.deviceIds,
            transport: widget.transport == 'wifi'
                ? session_model.SessionTransport.wifi
                : session_model.SessionTransport.ble,
          );

          if (!mounted) return;

          // Resolve the selected protocol per device (no fallback: every device must have one).
          if (widget.protocolByDeviceId.isEmpty) {
            // Re-attach path (e.g. re-opening from the active-sessions card)
            // carries no per-device protocol map. Don't crash the setup — abort
            // the reload and leave the existing engine/session running.
            appLogger.w(
                'Skipping engine reload — no protocolByDeviceId (re-attach).');
            return;
          }

          final Protocol commonProtocol = widget.protocol ??
              await ref.read(
                protocolDetailProvider(widget.protocolId).future,
              );

          final Map<String, Protocol> protocolByDevice = {};
          await Future.wait(widget.deviceIds.map((id) async {
            final pid = widget.protocolByDeviceId[id];
            if (pid == null) {
              throw StateError('No protocol selected for device: $id');
            }
            final proto = pid == commonProtocol.id
                ? commonProtocol
                : await ref.read(protocolDetailProvider(pid).future);
            protocolByDevice[id] = proto;
          }));

          if (protocolByDevice.length != widget.deviceIds.length) {
            throw StateError('protocolByDevice resolution incomplete.');
          }

          ctrl.loadSession(
            commonProtocol,
            widget.deviceIds,
            transport: widget.transport == 'wifi'
                ? session_model.SessionTransport.wifi
                : session_model.SessionTransport.ble,
            advancedSettings: widget.advancedSettings,
            advancedSettingsByDevice: widget.advancedSettingsByDevice,
            delayedDeviceId: widget.delayedDeviceId,
            protocolByDevice: protocolByDevice,
            wifiConfigAlreadyPublished: widget.wifiConfigAlreadyPublished,
          );

          if (!mounted) return;
          if (widget.transport == 'wifi') {
            final ms = widget.sessionClockAnchorMs;
            if (widget.wifiConfigAlreadyPublished && ms != null) {
              ctrl.applySessionClockOffsetFromWallAnchor(
                DateTime.fromMillisecondsSinceEpoch(ms),
              );
            }
            await ctrl.start();
          }
        }

        // Always ensure active session is created and synced for this screen
        final updatedEngineState =
            ref.read(sessionEngineFamilyProvider(_engineKey));
        if (_areDeviceListsEqual(
            widget.deviceIds, updatedEngineState.deviceIds)) {
          final protocolName = updatedEngineState.protocol?.templateName ??
              widget.protocol?.templateName ??
              'Unknown Protocol';
          await _ensureActiveSessionCreated(protocolName: protocolName);
          await _syncCurrentSessionToActiveSessions();
        } else {
          appLogger
              .w('Skipping session sync - engine managing different devices');
        }
      } catch (e) {
        appLogger.e('SessionScreen error: $e');
      }
    }

    // Must run after the first frame: Riverpod [ref] and [mounted] are not safe
    // from a microtask scheduled at initState time; WiFi start() was never
    // reached, so the session stayed idle (no timer / no pause controls).
    WidgetsBinding.instance.addPostFrameCallback((_) => bootstrap());

    // Protocol Plus: open the socket and apply server-driven protocol switches.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProtocolPlus());

    // Normal runs: track the backend sessionId (published after the async
    // `/sessions/start` POST) so we can drive backend pause/resume/stop.
    _initNormalServerSync();

    // Reconcile the local engine with remote stop/pause/resume: when this run's
    // backend session is paused/resumed/stopped from the web or another device,
    // the org-wide feed reflects it (via the /sessions socket) — apply it here
    // so the timer screen mirrors everywhere (web parity).
    _liveSessionsSub = ref.listenManual<List<active_session.ActiveSession>>(
      liveSessionsProvider,
      (prev, next) => _reconcileNormalRunFromBackend(next),
    );

    // Ensure the org-wide live feed (source of backend sun/moon + timing) is
    // running, in case the app bootstrap hasn't started it yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orgId = ref.read(authStateProvider).selectedOrgId ??
          ref.read(authStateProvider).user?.organizationId;
      if (orgId != null && orgId.isNotEmpty) {
        ref.read(liveSessionsProvider.notifier).start(orgId);
      }
    });

    // Load device names once so the session UI can show user-friendly labels.
    unawaited(_loadDeviceNames());
  }

  /// When this is a Protocol Plus run, connect the `/sessions` socket so each
  /// server `START_PROTOCOL` event switches the running engine to the next
  /// protocol. Protocol[0] was already started by the launching screen.
  void _initProtocolPlus() {
    if (!mounted) return;

    // Case 1: bindings already known — synchronous launch / history re-open /
    // the single-device legacy fields. Connect straight away.
    final immediate = _resolveImmediateBindings();
    if (immediate.isNotEmpty) {
      _connectProtocolPlus(immediate);
      return;
    }

    // Case 2: instant-UI launch — registration is still in flight. Watch the
    // delivery provider and connect the moment the server bindings arrive.
    if (widget.protocolPlusPending) {
      final sessionId = widget.sessionId ?? _engineKey;
      // They may have already arrived before this post-frame callback ran.
      final current = ref.read(protocolPlusBindingsProvider(sessionId));
      if (current.isNotEmpty) {
        _connectProtocolPlus(current);
        return;
      }
      _plusBindingsSub = ref.listenManual<List<ProtocolPlusBinding>>(
        protocolPlusBindingsProvider(sessionId),
        (prev, next) {
          if (next.isNotEmpty) _connectProtocolPlus(next);
        },
      );
    }
  }

  /// Bindings available up-front (not the pending instant-UI path): the
  /// multi-device list, or the single-device legacy fields.
  List<ProtocolPlusBinding> _resolveImmediateBindings() {
    if (widget.protocolPlusBindings.isNotEmpty) {
      return widget.protocolPlusBindings;
    }
    final serverSessionId = widget.protocolPlusServerSessionId;
    if (widget.protocolPlusId == null ||
        serverSessionId == null ||
        serverSessionId.isEmpty) {
      return const [];
    }
    final mac = widget.protocolPlusMac ??
        (widget.deviceIds.isNotEmpty ? widget.deviceIds.first : '');
    return [
      ProtocolPlusBinding(
        localMac: mac,
        serverDeviceId: mac,
        serverSessionId: serverSessionId,
        plusId: widget.protocolPlusId ?? '',
      ),
    ];
  }

  /// Wire the `/sessions` socket exactly once, persist the bindings onto the
  /// active session (so history re-open can re-attach / stop the schedule), and
  /// cover the rare case where the run already ended before registration
  /// completed (stop the server schedule immediately).
  void _connectProtocolPlus(List<ProtocolPlusBinding> bindings) {
    if (!mounted || _plusSocketConnected || bindings.isEmpty) return;
    _plusSocketConnected = true;
    _resolvedPlusBindings = bindings;

    final engineKey = widget.sessionId ?? _engineKey;
    final engine = ref.read(sessionEngineFamilyProvider(engineKey).notifier);

    _protocolPlusController = ref.read(protocolPlusControllerProvider);
    unawaited(
      _protocolPlusController!.connectAll(
        bindings: bindings,
        engine: engine,
        localSessionId: engineKey,
      ),
    );
    appLogger.i(
      'ProtocolPlus: SessionScreen connected socket '
      '(${bindings.length} device binding(s))',
    );

    unawaited(_persistPlusBindings(bindings));

    // The "run already ended before bindings arrived" race is handled inside
    // connectAll: its engine listener fires immediately and, if the engine is
    // already terminal, ends the run (stop server + free device + dispose).
  }

  /// Write the (possibly late-arriving) Plus bindings onto the tracked active
  /// session so re-opening from history can re-attach the socket / stop the
  /// server schedule. No-op until the active session exists.
  Future<void> _persistPlusBindings(List<ProtocolPlusBinding> bindings) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || bindings.isEmpty) return;
    await ref.read(activeSessionsProvider.notifier).updateProtocolPlusBindings(
          sessionId,
          bindings.map((b) => b.toMap()).toList(),
        );
  }

  /// Keep the server-side Protocol Plus session in sync with the local engine
  /// on pause/resume/stop. No-op for normal (non Protocol Plus) sessions.
  void _maybeSyncProtocolPlusServer(
    SessionStatus? prevS,
    SessionStatus nextS,
  ) {
    final controller = _protocolPlusController;
    final hasPlus = widget.protocolPlusBindings.isNotEmpty ||
        (widget.protocolPlusServerSessionId?.isNotEmpty ?? false) ||
        widget.protocolPlusPending ||
        _resolvedPlusBindings.isNotEmpty;
    // `controller` is only set once the socket is wired (bindings in hand), so
    // before that there is nothing on the server to pause/resume/stop yet — the
    // terminal-before-connect case is handled in [_connectProtocolPlus].
    if (controller == null || !hasPlus || prevS == nextS) {
      return;
    }

    if (prevS == SessionStatus.running && nextS == SessionStatus.paused) {
      unawaited(controller.pauseServerSession());
    } else if (prevS == SessionStatus.paused &&
        nextS == SessionStatus.running) {
      unawaited(controller.resumeServerSession());
    }
    // Terminal (stopped/completed) is intentionally NOT handled here. The
    // app-scoped controller owns end-of-run via its own engine listener, so the
    // server stop + active-session removal + socket teardown happen even when
    // this screen is not mounted (e.g. a Plus run that finishes off-screen).
  }

  /// Track the backend sessionId for a normal (non-Plus) run. It's published to
  /// [normalServerSessionIdProvider] after the async `/sessions/start` POST, so
  /// it may already be present or arrive slightly later — handle both.
  void _initNormalServerSync() {
    final key = widget.sessionId ?? _engineKey;
    final current = ref.read(normalServerSessionIdProvider(key));
    if (current != null && current.isNotEmpty) {
      _normalBackendSessionId = current;
    }
    _normalServerIdSub = ref.listenManual<String?>(
      normalServerSessionIdProvider(key),
      (prev, next) {
        if (next != null && next.isNotEmpty) _normalBackendSessionId = next;
      },
    );
  }

  /// Keep the backend session for a NORMAL run in sync with the local engine on
  /// pause/resume (parity with web). Terminal stop is handled in
  /// [_handleTerminalSessionState]. No-op until the backend sessionId is known.
  void _maybeSyncNormalServer(SessionStatus? prevS, SessionStatus nextS) {
    final backendId = _normalBackendSessionId;
    if (backendId == null || backendId.isEmpty || prevS == nextS) return;
    final sync = ref.read(sessionSyncServiceProvider);
    if (prevS == SessionStatus.running && nextS == SessionStatus.paused) {
      unawaited(sync.pauseServerSession(backendId));
    } else if (prevS == SessionStatus.paused &&
        nextS == SessionStatus.running) {
      unawaited(sync.resumeServerSession(backendId));
    }
  }

  /// Mirror a remote stop/pause/resume onto the local engine for a NORMAL run.
  /// Pause/resume reconcile the UI only (the remote client already commanded the
  /// device — Wi-Fi via MQTT); a remote stop ends the run locally too.
  void _reconcileNormalRunFromBackend(
    List<active_session.ActiveSession> sessions,
  ) {
    if (!mounted) return;
    final backendId = _normalBackendSessionId;
    if (backendId == null || backendId.isEmpty) return;

    active_session.ActiveSession? backendSession;
    for (final s in sessions) {
      if (s.id == backendId) {
        backendSession = s;
        break;
      }
    }

    final engineCtrl = ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
    final localStatus = ref.read(sessionEngineFamilyProvider(_engineKey)).status;
    final localLive = localStatus == SessionStatus.running ||
        localStatus == SessionStatus.paused;

    if (backendSession == null) {
      // Backend session is gone — stopped/finished elsewhere. End locally too,
      // but only if we'd actually seen it (so we don't stop a run whose backend
      // session simply hasn't appeared in the feed yet).
      if (_backendSessionSeen && !_normalServerStopped && localLive) {
        _normalServerStopped = true; // remote already stopped the server side
        appLogger.i('Session: backend $backendId removed — applying remote stop');
        unawaited(engineCtrl.stop());
      }
      return;
    }

    _backendSessionSeen = true;
    // Use the PER-DEVICE backend status, not the session-level one: pausing a
    // single device leaves the session status RUNNING on the backend, so the
    // session-level status would miss a per-device pause/resume.
    final dev = _findBackendLiveDevice(sessions, widget.deviceIds.first);
    final remote = dev?.status ?? backendSession.status;

    // Log transitions so we can see remote vs local state without per-second spam.
    final sig = 'dev=${dev?.status} sess=${backendSession.status} '
        'local=$localStatus lastRemote=$_lastRemoteStatus';
    if (sig != _lastReconcileSig) {
      _lastReconcileSig = sig;
      appLogger.i('Reconcile[$backendId]: $sig (firstDev=${widget.deviceIds.first})');
    }

    // Edge-triggered: only act when the backend status actually changes, so a
    // local pause isn't undone by the poll still reporting the old status during
    // the backend round-trip. applyRemoteLifecycle is a no-op if already there.
    if (_lastRemoteStatus == remote) return;
    _lastRemoteStatus = remote;
    if (remote == active_session.SessionStatus.paused &&
        localStatus == SessionStatus.running) {
      appLogger.i('Reconcile[$backendId]: APPLY remote PAUSE');
      // Full pause path (cancels the ticker + syncs the background runtime) so
      // it sticks; applyRemoteLifecycle alone gets resynced back to running.
      // Re-sending the Wi-Fi pause is idempotent (device is already paused).
      unawaited(engineCtrl.pause());
    } else if (remote == active_session.SessionStatus.running &&
        localStatus == SessionStatus.paused) {
      appLogger.i('Reconcile[$backendId]: APPLY remote RESUME');
      unawaited(engineCtrl.resume());
    } else {
      appLogger.i('Reconcile[$backendId]: remote changed to $remote but '
          'local=$localStatus — no engine action');
    }
  }

  /// Stop the backend session for a NORMAL run exactly once (on terminal). This
  /// is what clears the run from every client's live feed and prevents a stale
  /// RUNNING session lingering on the web.
  void _stopNormalServerSession() {
    if (_normalServerStopped) return;
    final backendId = _normalBackendSessionId;
    if (backendId == null || backendId.isEmpty) return;
    _normalServerStopped = true;
    unawaited(ref.read(sessionSyncServiceProvider).stopServerSession(backendId));
  }

  Future<void> _loadDeviceNames() async {
    try {
      final transport = widget.transport;
      final map = <String, String>{};

      if (transport == 'ble') {
        final paired = await ref.read(bleRepositoryProvider).getPairedDevices();
        for (final p in paired) {
          map[_normalizeMac(p.macAddress)] = p.name;
        }
      } else if (transport == 'wifi') {
        final wifiDevices = await ref.read(wifiDevicesByOrgProvider.future);
        for (final d in wifiDevices) {
          map[_normalizeMac(d.macAddress)] = d.name;
        }
      }

      if (!mounted) return;
      setState(() {
        _deviceLabelById
          ..clear()
          ..addAll(map);
      });
    } catch (_) {
      // If loading fails, we keep showing ids (fallback).
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    super.didChangeAppLifecycleState(appState);

    // Track foreground/background so music (foreground-only) pauses when the app
    // is backgrounded / screen is off, and resumes on return while running.
    final foreground = appState == AppLifecycleState.resumed;
    if (foreground != _isForeground) {
      _isForeground = foreground;
      _syncMusicToSession(
        ref.read(sessionEngineFamilyProvider(_engineKey)).status,
      );
    }

    if (appState != AppLifecycleState.resumed) return;
    // The periodic UI ticker is frozen while the app is backgrounded / the
    // screen is off, and the monotonic clock skips deep-sleep time — so the
    // displayed timer can be stale or behind the device. Ask the engine to
    // reconcile from the wall clock and restart its ticker, then re-assert the
    // keep-screen-on flag (some OEMs drop it across a background transition).
    final engine = ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
    engine.onAppResumed();
    _applyWakelockForStatus(
      ref.read(sessionEngineFamilyProvider(_engineKey)).status,
    );
  }

  /// Drive the session music gate from the current session status + foreground
  /// state. Best-effort — the controller swallows any audio error.
  void _syncMusicToSession(SessionStatus status) {
    _musicController?.applyConditions(
      sessionRunning: status == SessionStatus.running,
      appForeground: _isForeground,
    );
  }

  /// Bottom sheet to pick the session "Atmosphere" track + mute, mirroring the
  /// web app. Music plays only while the session is running (foreground-only).
  void _showAtmosphereSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, sheetRef, _) {
            final music = sheetRef.watch(sessionMusicControllerProvider);
            final controller =
                sheetRef.read(sessionMusicControllerProvider.notifier);
            final tracksAsync = sheetRef.watch(musicListProvider);
            final maxHeight = MediaQuery.of(ctx).size.height * 0.6;

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 20, color: ThemeConstants.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Session Atmosphere',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: ThemeConstants.textPrimary,
                              ),
                            ),
                          ),
                          // Mute toggle (keeps the track running, silent).
                          IconButton(
                            tooltip: music.isMuted ? 'Unmute' : 'Mute',
                            onPressed: music.hasTrack
                                ? () => controller.toggleMute()
                                : null,
                            icon: Icon(
                              music.isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: music.hasTrack
                                  ? ThemeConstants.textSecondary
                                  : ThemeConstants.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Looping music plays while the session is running.',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // "None" — clear the current selection.
                      _atmosphereTile(
                        icon: Icons.not_interested_rounded,
                        name: 'None',
                        selected: !music.hasTrack,
                        onTap: () => controller.clear(),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: tracksAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (e, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'Couldn\'t load music.',
                              style:
                                  TextStyle(color: ThemeConstants.textSecondary),
                            ),
                          ),
                          data: (tracks) {
                            if (tracks.isEmpty) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'No music tracks available.',
                                  style: TextStyle(
                                    color: ThemeConstants.textSecondary,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              itemCount: tracks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final track = tracks[i];
                                final isActive = music.activeTrackId == track.id;
                                final isAudible =
                                    isActive && music.isPlaying && !music.isMuted;
                                return _atmosphereTile(
                                  icon: isActive
                                      ? Icons.graphic_eq_rounded
                                      : Icons.music_note_outlined,
                                  name: track.name,
                                  selected: isActive,
                                  trailing: isAudible
                                      ? Icon(Icons.equalizer_rounded,
                                          size: 18,
                                          color: ThemeConstants.accent)
                                      : null,
                                  onTap: () => controller.selectTrack(track),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// A selectable row in the Atmosphere sheet (track or the "None" option).
  Widget _atmosphereTile({
    required IconData icon,
    required String name,
    required bool selected,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.12)
              : ThemeConstants.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? ThemeConstants.accent
                    : ThemeConstants.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: ThemeConstants.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  /// Keep the screen awake while a session is live so the device-synced timer
  /// stays visible and ticking; release it once nothing is live anymore.
  void _applyWakelockForStatus(SessionStatus status) {
    final live =
        status == SessionStatus.running || status == SessionStatus.paused;
    unawaited(_setWakelock(live));
  }

  Future<void> _setWakelock(bool enable, {bool fromDispose = false}) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else if (fromDispose) {
        // dispose() runs after the widget is unmounted, so `ref` is no longer
        // usable — disable unconditionally (best-effort) to avoid leaking the
        // wakelock. A still-live session's screen re-enables it on its own.
        await WakelockPlus.disable();
      } else {
        // Don't drop the wakelock if another tracked session is still live
        // (concurrent sessions share the single app-wide screen-on flag).
        final anyLive = ref
            .read(activeSessionsProvider)
            .any((s) => _isLiveSession(s.status));
        if (!anyLive) await WakelockPlus.disable();
      }
    } catch (e) {
      appLogger.w('Session: wakelock toggle failed (enable=$enable): $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Music is a session-screen feature — never let it outlive the screen.
    unawaited(_musicController?.stopAndReset() ?? Future<void>.value());
    unawaited(_setWakelock(false, fromDispose: true));
    _stopBackendPadPolling(fromDispose: true);
    _engineSub?.close();
    _bleConnectionSub?.close();
    _plusBindingsSub?.close();
    _normalServerIdSub?.close();
    _liveSessionsSub?.close();
    // NOTE: We intentionally do NOT dispose the Protocol Plus socket here.
    // The socket must outlive this screen: a Protocol Plus run keeps receiving
    // the server's START_PROTOCOL switches and applying them via the
    // app-scoped SessionEngine even after the user navigates away from the
    // session screen. The socket is instead torn down when the run actually
    // ends (stop/complete — see _maybeSyncProtocolPlusServer) or when the next
    // session's connectAll() replaces it. The controller is an app-scoped
    // provider, so it (and its socket) survive this widget being unmounted.
    // Session engine cleanup happens automatically
    super.dispose();
  }

  static String _normalizeMac(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  }

  void _startBackendPadPolling() {
    if (_padPollTimer != null) return;
    if (widget.deviceIds.isEmpty) return;
    final firstMac = _normalizeMac(widget.deviceIds.first);

    void tick() {
      if (!mounted) return;
      try {
        // Source pad state + timing from the org-wide backend feed (the single
        // source of truth) rather than a separate fetch — it already polls
        // /sessions/active every second and parses per-device sun/moon. Match
        // each local device to its backend device (WiFi exact mac, BLE ±1) and
        // feed the backend frame into the engine keyed by the LOCAL id so the
        // per-device card picks it up (and goes grey when the backend reports
        // the pad disabled — web parity).
        final sessions = ref.read(liveSessionsProvider);
        final engine = ref.read(
          sessionEngineFamilyProvider(_engineKey).notifier,
        );

        String? moon;
        String? sun;
        var matched = 0;
        for (final localId in widget.deviceIds) {
          final dev = _findBackendLiveDevice(sessions, localId);
          if (dev == null) continue;
          matched++;
          engine.updateDeviceTelemetry(localId, {
            'macAddress': localId,
            'moon': dev.moon,
            'sun': dev.sun,
            'remainingSeconds': dev.remainingSeconds,
            'elapsedSeconds': dev.elapsedSeconds,
            'totalDurationSeconds': dev.totalDurationSeconds,
          });
          if (_normalizeMac(localId) == firstMac) {
            moon = dev.moon;
            sun = dev.sun;
          }
        }
        if (!_padDiagLogged) {
          _padDiagLogged = true;
          appLogger.i(
            'PadPoll: liveSessions=${sessions.length}, '
            'localDevices=${widget.deviceIds}, matched=$matched, '
            'firstMoon=$moon firstSun=$sun',
          );
        }
      } catch (e, st) {
        appLogger.d('Session pad poll: $e\n$st');
      }
    }

    tick();
    _padPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Find the backend live-device for a local device id across all live
  /// sessions. Matches WiFi by exact (normalized) MAC and BLE by ±1 last byte
  /// (units advertise on a MAC ±1 from the registered/firmware id).
  active_session.LiveDeviceState? _findBackendLiveDevice(
    List<active_session.ActiveSession> sessions,
    String localId,
  ) {
    final candidates = _normalizedMacVariants(localId);
    for (final s in sessions) {
      for (final d in s.liveDevices) {
        if (candidates.contains(_normalizeMac(d.deviceId))) return d;
      }
    }
    return null;
  }

  static Set<String> _normalizedMacVariants(String raw) {
    final norm = _normalizeMac(raw); // hex-only, lowercase
    final variants = <String>{norm};
    if (norm.length == 12) {
      final lastByte = int.tryParse(norm.substring(10), radix: 16);
      if (lastByte != null) {
        for (final delta in const [1, -1]) {
          final nb =
              ((lastByte + delta) & 0xFF).toRadixString(16).padLeft(2, '0');
          variants.add(norm.substring(0, 10) + nb);
        }
      }
    }
    return variants;
  }

  void _stopBackendPadPolling({bool fromDispose = false}) {
    _padPollTimer?.cancel();
    _padPollTimer = null;
  }

  Future<void> _ensureActiveSessionCreated({String? protocolName}) async {
    final activeSessionsNotifier = ref.read(activeSessionsProvider.notifier);
    active_session.ActiveSession? existingSession;
    for (final session in ref.read(activeSessionsProvider)) {
      if (session.id == _engineKey) {
        existingSession = session;
        break;
      }
    }

    if (existingSession != null) {
      _activeSessionId = existingSession.id;
      appLogger.i('Reusing existing session by ID: $_activeSessionId');
      return;
    }

    _activeSessionId = await activeSessionsNotifier.createSession(
      sessionId: _engineKey,
      protocolId: widget.protocolId,
      protocolName: protocolName ?? 'Unknown Protocol',
      deviceIds: widget.deviceIds,
      transport: widget.transport,
      // Persist Plus bindings so re-opening from history can re-attach the
      // socket and stop the server-side schedule. Prefer bindings resolved at
      // runtime (instant-UI launch) over the up-front widget bindings.
      protocolPlusBindings: (_resolvedPlusBindings.isNotEmpty
              ? _resolvedPlusBindings
              : widget.protocolPlusBindings)
          .map((b) => b.toMap())
          .toList(),
    );
    appLogger.i(
        'Created new session: $_activeSessionId for devices: ${widget.deviceIds}');
  }

  Future<void> _captureSessionHistorySnapshot(SessionEngineState engine) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || _historySnapshotSessionId == sessionId) {
      return;
    }

    // Claim the snapshot synchronously (before any await) so concurrent
    // engine-state listener callbacks can't each fire a duplicate save/POST
    // while the first one is still in flight.
    _historySnapshotSessionId = sessionId;

    final auth = ref.read(authStateProvider);
    final userId = auth.user?.id;
    final now = DateTime.now();
    final sessionEngine =
        ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
    final record = sessionEngine.getSessionRecord(
      sessionId: sessionId,
      clientType: 'guest',
      createdBy: userId,
      updatedBy: userId,
      createdAt: now,
      updatedAt: now,
      discomfortBefore: 6,
      discomfortAfter: 2,
      notes: 'Guest session started from mobile app',
    );

    if (record == null) {
      // Couldn't build a record yet — release the claim so a later, valid
      // engine state can retry.
      _historySnapshotSessionId = null;
      return;
    }

    await ref.read(sessionRepositoryProvider).saveSession(record);
    appLogger.i('Captured session history snapshot for $sessionId');
  }

  bool _areDeviceListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    final set1 = Set<String>.from(list1);
    final set2 = Set<String>.from(list2);
    return set1.containsAll(set2);
  }

  String? _findMatchingActiveSessionId() {
    final explicitSessionId = widget.sessionId;
    if (explicitSessionId != null && explicitSessionId.isNotEmpty) {
      return explicitSessionId;
    }

    final matchingSessions = ref
        .read(activeSessionsProvider)
        .where((session) =>
            _isLiveSession(session.status) &&
            session.protocolId == widget.protocolId &&
            _areDeviceListsEqual(session.deviceIds, widget.deviceIds))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matchingSessions.isEmpty ? null : matchingSessions.first.id;
  }

  String _buildFallbackEngineKey() {
    final sortedDeviceIds = [...widget.deviceIds]..sort();
    return '${widget.transport}:${widget.protocolId}:${sortedDeviceIds.join(",")}';
  }

  bool _isLiveSession(active_session.SessionStatus status) {
    return status == active_session.SessionStatus.running ||
        status == active_session.SessionStatus.paused;
  }

  active_session.ActiveSession? _findTrackedSession(
    List<active_session.ActiveSession> sessions,
  ) {
    final activeSessionId = _activeSessionId;
    if (activeSessionId == null) return null;
    for (final session in sessions) {
      if (session.id == activeSessionId) {
        return session;
      }
    }
    return null;
  }

  active_session.SessionStatus _toActiveStatus(SessionStatus status) {
    return switch (status) {
      session_model.SessionStatus.idle => active_session.SessionStatus.idle,
      session_model.SessionStatus.running =>
        active_session.SessionStatus.running,
      session_model.SessionStatus.paused => active_session.SessionStatus.paused,
      session_model.SessionStatus.stopped =>
        active_session.SessionStatus.stopped,
      session_model.SessionStatus.completed =>
        active_session.SessionStatus.completed,
    };
  }

  SessionStatus _toSessionStatus(active_session.SessionStatus status) {
    return switch (status) {
      active_session.SessionStatus.idle => session_model.SessionStatus.idle,
      active_session.SessionStatus.running =>
        session_model.SessionStatus.running,
      active_session.SessionStatus.paused => session_model.SessionStatus.paused,
      active_session.SessionStatus.stopped =>
        session_model.SessionStatus.stopped,
      active_session.SessionStatus.completed =>
        session_model.SessionStatus.completed,
    };
  }

  /// REMOTE VIEW: build a read-only [SessionEngineState] from the matching
  /// foreign session in the live feed, so the existing build() renders it like
  /// a local run. Per-device timers/status come from the backend `liveDevices`;
  /// pads still come from the feed at the card call site. Protocol-Plus tracker
  /// data isn't carried by the feed, so those fields stay empty (the tracker is
  /// hidden in remote mode).
  SessionEngineState _remoteEngineState(
    List<active_session.ActiveSession> sessions,
  ) {
    final id = widget.backendSessionId;
    active_session.ActiveSession? s;
    for (final x in sessions) {
      if (x.id == id) {
        s = x;
        break;
      }
    }
    if (s == null) return const SessionEngineState();

    final deviceTimers = <String, TimerState>{};
    final deviceStatuses = <String, SessionStatus>{};
    var maxTotal = 0;
    var maxElapsed = 0;
    for (final d in s.liveDevices) {
      deviceStatuses[d.deviceId] = _toSessionStatus(d.status);
      deviceTimers[d.deviceId] = TimerState(
        elapsed: Duration(seconds: d.elapsedSeconds),
        totalDuration: Duration(seconds: d.totalDurationSeconds),
        isRunning: d.status == active_session.SessionStatus.running,
      );
      if (d.totalDurationSeconds > maxTotal) maxTotal = d.totalDurationSeconds;
      if (d.elapsedSeconds > maxElapsed) maxElapsed = d.elapsedSeconds;
    }

    return SessionEngineState(
      status: _toSessionStatus(s.status),
      transport: s.transport == 'wifi'
          ? session_model.SessionTransport.wifi
          : session_model.SessionTransport.ble,
      deviceIds: s.deviceIds,
      deviceTimers: deviceTimers,
      deviceStatuses: deviceStatuses,
      timer: TimerState(
        elapsed: Duration(seconds: maxElapsed),
        totalDuration: Duration(seconds: maxTotal),
      ),
    );
  }

  Future<void> _syncCurrentSessionToActiveSessions() async {
    if (_activeSessionId == null) return;
    final engine = ref.read(sessionEngineFamilyProvider(_engineKey));
    final activeSessionsNotifier = ref.read(activeSessionsProvider.notifier);

    // Only update if this session's devices match the engine's current devices
    if (_areDeviceListsEqual(widget.deviceIds, engine.deviceIds)) {
      await activeSessionsNotifier.updateSessionStatus(
        _activeSessionId!,
        _toActiveStatus(engine.status),
      );
      await activeSessionsNotifier.updateDeviceStatuses(
        _activeSessionId!,
        <String, active_session.SessionStatus>{
          for (final entry in engine.deviceStatuses.entries)
            entry.key: _toActiveStatus(entry.value),
        },
      );
      appLogger.i('Synced session $_activeSessionId with engine state');
    } else {
      appLogger.w('Skipping session sync - device lists do not match');
    }
  }

  Future<void> _removeTrackedSessionIfAny() async {
    if (_activeSessionId == null) return;

    // Only remove session if it's actually completed or stopped
    final engine = ref.read(sessionEngineFamilyProvider(_engineKey));
    final sessionStatus = engine.status;

    if (sessionStatus == SessionStatus.completed ||
        sessionStatus == SessionStatus.stopped) {
      await ref
          .read(activeSessionsProvider.notifier)
          .removeSession(_activeSessionId!);
      appLogger.i('Removed completed session: $_activeSessionId');
      _activeSessionId = null;
    } else {
      appLogger.w(
          'Not removing session $_activeSessionId - status is $sessionStatus');
    }
  }

  Future<void> _handleBleDisconnect(String deviceId) async {
    final engine = ref.read(sessionEngineFamilyProvider(_engineKey));
    final isLive = engine.status == SessionStatus.running ||
        engine.status == SessionStatus.paused;
    if (!isLive) return;

    await ref
        .read(sessionEngineFamilyProvider(_engineKey).notifier)
        .handleBleDisconnect(deviceId);
  }

  Future<void> _syncEngineStateToActiveSessions(
      SessionEngineState engine) async {
    if (_activeSessionId == null) return;
    final activeSessionsNotifier = ref.read(activeSessionsProvider.notifier);

    // Only update if this session's devices match the engine's current devices
    if (_areDeviceListsEqual(widget.deviceIds, engine.deviceIds)) {
      await activeSessionsNotifier.updateSessionStatus(
        _activeSessionId!,
        _toActiveStatus(engine.status),
      );
      await activeSessionsNotifier.updateDeviceStatuses(
        _activeSessionId!,
        <String, active_session.SessionStatus>{
          for (final entry in engine.deviceStatuses.entries)
            entry.key: _toActiveStatus(entry.value),
        },
      );
      appLogger.i('Synced session $_activeSessionId with engine state');
    } else {
      appLogger.w('Skipping engine state sync - device lists do not match');
    }
  }

  Future<void> _ensureAndSyncFromEngineState(SessionEngineState engine) async {
    final isLive = engine.status == SessionStatus.running ||
        engine.status == SessionStatus.paused;
    if (!isLive) return;
    await _ensureActiveSessionCreated(
      protocolName:
          engine.protocol?.templateName ?? widget.protocol?.templateName,
    );
    await _captureSessionHistorySnapshot(engine);
    await _syncEngineStateToActiveSessions(engine);
  }

  Future<void> _handleTerminalSessionState(SessionEngineState engine) async {
    if (engine.status != SessionStatus.stopped &&
        engine.status != SessionStatus.completed) {
      return;
    }
    // End the backend session for a normal run first, so the run clears from
    // every client's live feed even if there's no local active-session record.
    _stopNormalServerSession();
    if (_terminalSessionCleanupInFlight) return;
    if (_activeSessionId == null) return;

    _terminalSessionCleanupInFlight = true;
    final trackedSessionId = _activeSessionId!;
    try {
      await _syncEngineStateToActiveSessions(engine);
      await ref
          .read(activeSessionsProvider.notifier)
          .removeSession(trackedSessionId);
      await ref
          .read(backgroundSessionRuntimeProvider.notifier)
          .stopService(sessionId: trackedSessionId);
      _activeSessionId = null;
      appLogger.i(
        'Removed terminal active session immediately: $trackedSessionId '
        '(status=${engine.status})',
      );
    } finally {
      _terminalSessionCleanupInFlight = false;
    }
  }

  bool _isDisconnectTransition(
    BleConnectionStatus? previous,
    BleConnectionStatus? current,
  ) {
    if (current != BleConnectionStatus.disconnected &&
        current != BleConnectionStatus.error) {
      return false;
    }
    return previous == BleConnectionStatus.connected ||
        previous == BleConnectionStatus.connecting ||
        previous == BleConnectionStatus.disconnecting;
  }

  @override
  Widget build(BuildContext context) {
    // The org-wide live feed: source of backend sun/moon + per-device timing,
    // and (in remote view) the entire display state.
    final liveSessions = ref.watch(liveSessionsProvider);

    // REMOTE VIEW mirrors a foreign WiFi session from the feed — synthesize a
    // read-only engine state from it so the existing UI renders unchanged.
    final engine = widget.remoteView
        ? _remoteEngineState(liveSessions)
        : ref.watch(sessionEngineFamilyProvider(_engineKey));

    // Get session-specific data instead of always using engine state
    final activeSessions = ref.watch(activeSessionsProvider);
    final currentSession = _findTrackedSession(activeSessions);

    final timer = engine.timer;
    // Prefer the live engine status when the engine for this session is
    // actually running/paused, so a stale tracked status can't strand the
    // Stop/Pause/Resume controls after re-entering a live (WiFi) session.
    final engineLive = engine.status == SessionStatus.running ||
        engine.status == SessionStatus.paused;
    final status = engineLive
        ? engine.status
        : (currentSession == null
            ? engine.status
            : _toSessionStatus(currentSession.status));
    final ctrl = ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
    final protocol = engine.protocol;
    // During timed pause gaps the engine sets currentCycleIndex to -1, but
    // the pads still reflect the active protocol cycle — use lastVisualCycleIndex.
    final int padCycleIdx;
    if (protocol != null && protocol.cycles.isNotEmpty) {
      if (timer.currentCycleIndex >= 0 &&
          timer.currentCycleIndex < protocol.cycles.length) {
        padCycleIdx = timer.currentCycleIndex;
      } else if (timer.lastVisualCycleIndex >= 0 &&
          timer.lastVisualCycleIndex < protocol.cycles.length) {
        padCycleIdx = timer.lastVisualCycleIndex;
      } else {
        padCycleIdx = 0;
      }
    } else {
      padCycleIdx = -1;
    }
    // Web parity: pad colors come straight from the backend per-device sun/moon
    // (the org-wide live feed). No local cycle fallback — when the backend
    // reports the pad off/neutral the mapping returns grey, exactly like the web.
    // Colors are resolved PER DEVICE at the card call site below.
    final orderedDeviceIds = widget.deviceIds
        .where((id) => engine.deviceTimers.containsKey(id))
        .toList();
    if (orderedDeviceIds.isEmpty && engine.deviceTimers.isNotEmpty) {
      orderedDeviceIds.addAll(engine.deviceTimers.keys);
    }
    if (_activeDevicePage >= orderedDeviceIds.length &&
        orderedDeviceIds.isNotEmpty) {
      _activeDevicePage = 0;
    }

    // Telemetry adds optional blocks (fault card / warning banner / sensor row)
    // to the device card. Give the fixed-height PageView extra room when any
    // device is showing them, so the controls (incl. Stop) stay on-screen
    // instead of being scrolled out of view.
    final hasTelemetryExtras = orderedDeviceIds.any((id) {
      final t = engine.telemetryByDevice[id];
      return t != null &&
          (t.isFault || t.isWarning || t.sensorReadouts.isNotEmpty);
    });

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: Text(
          widget.remoteView
              ? 'Live: ${engine.deviceIds.length} device(s)'
              : 'Session(${widget.deviceIds.length} Devices)',
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            // Save or update session to active sessions before going back.
            // Remote view owns no local session, so there's nothing to sync.
            if (!widget.remoteView && status != SessionStatus.idle) {
              await _syncCurrentSessionToActiveSessions();
            }

            if (!mounted) return;
            context.pop();
          },
        ),
        actions: [
          Consumer(
            builder: (context, musicRef, _) {
              final music = musicRef.watch(sessionMusicControllerProvider);
              final controller =
                  musicRef.read(sessionMusicControllerProvider.notifier);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mute toggle — visible top-level control while a track is
                  // active (mirrors the web's Mute button).
                  if (music.hasTrack)
                    IconButton(
                      tooltip: music.isMuted ? 'Unmute' : 'Mute',
                      onPressed: () => controller.toggleMute(),
                      icon: Icon(
                        music.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: music.isMuted
                            ? ThemeConstants.textSecondary
                            : ThemeConstants.accent,
                      ),
                    ),
                  // Session "Atmosphere" music — accent when a track is active.
                  IconButton(
                    tooltip: 'Session music',
                    onPressed: _showAtmosphereSheet,
                    icon: Icon(
                      music.hasTrack
                          ? Icons.music_note_rounded
                          : Icons.music_note_outlined,
                      color: music.hasTrack ? ThemeConstants.accent : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 8),
            if (status == SessionStatus.idle) ...[
              _buildControls(status, ctrl),
              const SizedBox(height: 24),
            ] else if (orderedDeviceIds.isNotEmpty) ...[
              SizedBox(
                // Plus devices render an extra progress card inside the device
                // card, so give the page more height when any device is Plus.
                height: (engine.protocolPlusSequenceByDevice.isNotEmpty
                        ? 560
                        : 420) +
                    (hasTelemetryExtras ? 130 : 0),
                child: PageView.builder(
                  itemCount: orderedDeviceIds.length,
                  onPageChanged: (idx) =>
                      setState(() => _activeDevicePage = idx),
                  itemBuilder: (context, index) {
                    final id = orderedDeviceIds[index];
                    final deviceTimer = engine.deviceTimers[id]!;
                    final deviceStatus =
                        engine.deviceStatuses[id] ?? SessionStatus.idle;
                    final perDeviceProtocolName =
                        engine.protocolByDevice[id]?.templateName ??
                            protocol?.templateName ??
                            '';
                    final deviceSequence =
                        engine.protocolPlusSequenceByDevice[id] ??
                            const <String>[];
                    final backendDev =
                        _findBackendLiveDevice(liveSessions, id);
                    return _buildDeviceSessionCard(
                      id: id,
                      label: _deviceLabel(id),
                      protocolName: perDeviceProtocolName,
                      timer: deviceTimer,
                      status: deviceStatus,
                      totalCycles: timer.totalCycles,
                      padCycleIdx: padCycleIdx,
                      moonColor: _webMoonPadColor(backendDev?.moon),
                      sunColor: _webSunPadColor(backendDev?.sun),
                      // Timer comes from the backend (single source of truth) so
                      // the app matches the web exactly instead of drifting from
                      // the local engine clock.
                      backendRemainingSeconds: backendDev?.remainingSeconds,
                      backendTotalSeconds: backendDev?.totalDurationSeconds,
                      telemetry: engine.telemetryByDevice[id],
                      ctrl: ctrl,
                      isProtocolPlusDevice: deviceSequence.isNotEmpty,
                      plusSequence: deviceSequence,
                      plusName: engine.protocolPlusNameByDevice[id] ?? '',
                      plusIndex: engine.protocolPlusIndexByDevice[id] ?? 0,
                      plusDelaySeconds:
                          engine.protocolPlusDelayByDevice[id] ?? 0,
                      plusOnBreak:
                          engine.protocolPlusOnBreakByDevice[id] ?? false,
                      plusBreakRemaining:
                          engine.protocolPlusBreakRemainingByDevice[id] ?? 0,
                    );
                  },
                ),
              ),
              if (orderedDeviceIds.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(orderedDeviceIds.length, (idx) {
                    final active = idx == _activeDevicePage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? ThemeConstants.accent
                            : ThemeConstants.textTertiary
                                .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
              ],
              const SizedBox(height: 18),
              const SizedBox(height: 24),
            ] else ...[
              const SizedBox(height: 24),
            ],

            // REMOTE VIEW: session-wide Pause All / Resume All / Stop All.
            if (widget.remoteView &&
                (status == SessionStatus.running ||
                    status == SessionStatus.paused))
              _buildRemoteAllControls(status, liveSessions),

            // Device status
            if (widget.deviceIds.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ThemeConstants.border)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: ThemeConstants.success,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(
                      widget.transport == 'wifi'
                          ? '${widget.deviceIds.length} WiFi device(s) selected'
                          : '${widget.deviceIds.length} device(s) connected',
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Protocol Plus tracker — a horizontal route map: the sequence title on top,
  /// then stops (stations) laid out left→right and joined by a track whose
  /// traveled portion is filled. The active stop pulses; passed stops show ✓.
  /// Advances on each START_PROTOCOL.
  Widget _buildProtocolPlusSequence(
    List<String> names, {
    required String name,
    required int index,
    int delaySeconds = 0,
    bool onBreak = false,
    int breakRemaining = 0,
  }) {
    var currentIndex = index;
    if (currentIndex < 0) currentIndex = 0;
    if (currentIndex > names.length - 1) currentIndex = names.length - 1;
    // While on break the current protocol has finished and the next is "up
    // next" — there's always a next when on break (the engine never flags a
    // break on the final protocol).
    final hasNext = currentIndex < names.length - 1;
    final breaking = onBreak && hasNext;
    final nextIndex = breaking ? currentIndex + 1 : -1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row: Protocol Plus name + step counter.
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: ThemeConstants.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : 'Protocol Plus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentIndex + 1}/${names.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.accent,
                  ),
                ),
              ),
            ],
          ),
          // Break banner: the current protocol has finished and the next one
          // starts after the device's break gap. Shows a live countdown.
          if (breaking) ...[
            const SizedBox(height: 12),
            _buildBreakBanner(
              nextName: names[nextIndex],
              remaining: breakRemaining,
            ),
          ],
          const SizedBox(height: 14),
          // Horizontal route: stations + connecting track.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < names.length; i++) ...[
                Expanded(
                  child: _routeStop(
                    index: i,
                    name: names[i],
                    // During a break the finished protocol reads as "past" and
                    // the next one is highlighted as "up next".
                    isActive: !breaking && i == currentIndex,
                    isPast: i < currentIndex || (breaking && i == currentIndex),
                    isNext: breaking && i == nextIndex,
                  ),
                ),
                if (i < names.length - 1)
                  _routeTrack(
                    done: i < currentIndex,
                    delaySeconds: delaySeconds,
                    // The connector being "traversed" right now is the break gap
                    // between the finished protocol and the next one.
                    active: breaking && i == currentIndex,
                    countdown: breaking && i == currentIndex ? breakRemaining : null,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// A single station on the horizontal route: the dot on top, name below.
  Widget _routeStop({
    required int index,
    required String name,
    required bool isActive,
    required bool isPast,
    bool isNext = false,
  }) {
    final Color dotBg;
    final Color dotFg;
    if (isActive) {
      dotBg = ThemeConstants.accent;
      dotFg = Colors.white;
    } else if (isNext) {
      // "Up next" during a break — a hollow accent ring that pulses.
      dotBg = ThemeConstants.accent.withValues(alpha: 0.14);
      dotFg = ThemeConstants.accent;
    } else if (isPast) {
      dotBg = ThemeConstants.accent.withValues(alpha: 0.20);
      dotFg = ThemeConstants.accent;
    } else {
      dotBg = ThemeConstants.surfaceVariant;
      dotFg = ThemeConstants.textTertiary;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: (isActive || isNext) ? 30 : 26,
          height: (isActive || isNext) ? 30 : 26,
          decoration: BoxDecoration(
            color: dotBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive || isNext
                  ? ThemeConstants.accent
                  : isPast
                      ? ThemeConstants.accent.withValues(alpha: 0.35)
                      : ThemeConstants.border,
              width: 2,
            ),
            boxShadow: isActive || isNext
                ? [
                    BoxShadow(
                      color: ThemeConstants.accent
                          .withValues(alpha: isActive ? 0.40 : 0.22),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: isPast
              ? Icon(Icons.check_rounded, size: 15, color: dotFg)
              : isNext
                  ? Icon(Icons.hourglass_top_rounded, size: 15, color: dotFg)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: dotFg,
                      ),
                    ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.15,
            fontWeight: isActive || isNext ? FontWeight.w700 : FontWeight.w500,
            color: isActive || isNext
                ? ThemeConstants.textPrimary
                : isPast
                    ? ThemeConstants.textTertiary
                    : ThemeConstants.textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        if (isActive)
          Text(
            'RUNNING',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: ThemeConstants.accent,
            ),
          )
        else if (isNext)
          Text(
            'UP NEXT',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: ThemeConstants.accent.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }

  /// The connecting track segment between two stations. Sits at dot height.
  /// When [delaySeconds] > 0 (a Protocol Plus break), shows the break time in
  /// seconds above the line, e.g. "90s". When [active] is true the break on
  /// THIS segment is happening right now, so [countdown] (the live remaining
  /// seconds) is shown instead and the line is accented.
  Widget _routeTrack({
    required bool done,
    int delaySeconds = 0,
    bool active = false,
    int? countdown,
  }) {
    final line = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 26,
      height: active ? 4 : 3,
      decoration: BoxDecoration(
        color: done
            ? ThemeConstants.accent.withValues(alpha: 0.55)
            : active
                ? ThemeConstants.accent
                : ThemeConstants.border,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    // Live break on this segment → show the counting-down remaining time.
    if (active) {
      final secs = (countdown ?? 0) > 0 ? '${countdown}s' : '…';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            secs,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: ThemeConstants.accent,
            ),
          ),
          const SizedBox(height: 2),
          line,
        ],
      );
    }

    // No break time → keep the bare line vertically centered on the ~26-30px dot.
    if (delaySeconds <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 13),
        child: line,
      );
    }

    // Break time label sits on the connector, aligned to the dot's center.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${delaySeconds}s',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: ThemeConstants.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        line,
      ],
    );
  }

  /// A prominent banner shown while a Plus device is between protocols: the
  /// break is counting down and the next protocol is named. Replaces the old
  /// "value only" hint (B-32) with the live countdown UI requested in B-24.
  Widget _buildBreakBanner({
    required String nextName,
    required int remaining,
  }) {
    final counting = remaining > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ThemeConstants.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ThemeConstants.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            counting ? Icons.pause_circle_filled_rounded : Icons.sync_rounded,
            size: 18,
            color: ThemeConstants.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  counting ? 'BREAK' : 'SWITCHING',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: ThemeConstants.accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  counting
                      ? 'Next: $nextName'
                      : 'Starting $nextName…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (counting) ...[
            const SizedBox(width: 8),
            Text(
              _formatBreak(remaining),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: ThemeConstants.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Format break seconds as M:SS (or SS for sub-minute gaps).
  String _formatBreak(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Red fault card — blocking firmware error (overcurrent / device fault).
  /// Mirrors the web live-session fault card (label + fault value + reason).
  Widget _buildFaultCard(DeviceTelemetry t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (t.faultLabel ?? 'Device Fault').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                if (t.faultValue != null)
                  Text(
                    'fv: ${t.faultValue}',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (t.faultReason != null && t.faultReason!.isNotEmpty)
                  Text(
                    'fr: ${t.faultReason}',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Orange warning banner — non-blocking (firmware keeps running). Mirrors the
  /// web warning copy for pad-disconnect / NTC-overheat.
  Widget _buildWarningBanner(DeviceTelemetry t) {
    final isPadDisconnect = t.isPadDisconnect;
    final label = isPadDisconnect ? 'Pad Not Connected' : 'Device Overheated';
    final icon =
        isPadDisconnect ? Icons.power_off_rounded : Icons.warning_amber_rounded;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.orange.shade800, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Friendly labels for the firmware's short telemetry keys.
  ///
  /// ⚠️ BEST-EFFORT — these short keys are firmware-defined and are NOT
  /// documented in the app/web codebase. Confirm each meaning (and unit) with
  /// the firmware team and correct the mapping below; unknown keys fall back to
  /// the raw key so nothing is hidden.
  static const Map<String, ({String label, String? unit})> _telemetryLabels = {
    // Confirmed against a real frame; units still BEST-EFFORT (verify w/ firmware).
    'tp': (label: 'Temp', unit: '°C'),
    'c': (label: 'Current', unit: 'A'),
    'av': (label: 'Voltage', unit: 'V'),
    // `td` / `tl` meanings are NOT yet identified (both read 0 mid-session) —
    // intentionally left unmapped so they render as raw keys, not mislabeled.
  };

  /// Generic live sensor readouts (temperature/voltage/current/…). Field names
  /// are firmware-defined; known short keys are mapped to readable labels via
  /// [_telemetryLabels], unknown keys render as-is.
  Widget _buildSensorReadouts(Map<String, num> readouts) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: readouts.entries.map((e) {
        final mapped = _telemetryLabels[e.key.toLowerCase()];
        final label = mapped?.label ?? e.key;
        final unit = mapped?.unit;
        final valueText = unit != null ? '${e.value}$unit' : '${e.value}';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ThemeConstants.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label: $valueText',
            style: TextStyle(
              color: ThemeConstants.textSecondary,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDeviceSessionCard({
    required String id,
    required String label,
    required String protocolName,
    required TimerState timer,
    required SessionStatus status,
    required int totalCycles,
    required int padCycleIdx,
    required Color moonColor,
    required Color sunColor,
    required SessionEngine ctrl,
    int? backendRemainingSeconds,
    int? backendTotalSeconds,
    DeviceTelemetry? telemetry,
    bool isProtocolPlusDevice = false,
    List<String> plusSequence = const [],
    String plusName = '',
    int plusIndex = 0,
    int plusDelaySeconds = 0,
    bool plusOnBreak = false,
    int plusBreakRemaining = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? ThemeConstants.surface : Colors.white;

    // Live telemetry (device→app) takes precedence over the cycle-derived pad
    // colors when present — the firmware's actual thermode state is authoritative.
    final effectiveMoonColor = (telemetry?.moon != null)
        ? _webMoonPadColor(telemetry!.moon)
        : moonColor;
    final effectiveSunColor = (telemetry?.sun != null)
        ? _webSunPadColor(telemetry!.sun)
        : sunColor;
    final isFault = telemetry?.isFault ?? false;
    final isWarning = telemetry?.isWarning ?? false;

    // Prefer the backend timer (single source of truth → matches the web). Fall
    // back to the local engine timer only until the backend value is available.
    final useBackendTimer =
        backendRemainingSeconds != null && backendRemainingSeconds >= 0;
    final displayRemaining = useBackendTimer
        ? Duration(seconds: backendRemainingSeconds)
        : timer.remaining;
    final double displayProgress;
    if (useBackendTimer &&
        backendTotalSeconds != null &&
        backendTotalSeconds > 0) {
      displayProgress =
          (1 - backendRemainingSeconds / backendTotalSeconds).clamp(0.0, 1.0);
    } else {
      displayProgress = timer.progress;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        // Web parity: red border on fault, orange on warning, default otherwise.
        border: Border.all(
          color: isFault
              ? Colors.red
              : isWarning
                  ? Colors.orange
                  : ThemeConstants.borderLight,
          width: isFault ? 2 : 1,
        ),
      ),
      // Scrollable so the card never overflows — Plus devices add a progress
      // card, and small screens may not fit the ring + status + controls.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            // FAULT card (red) / WARNING banner (orange) — device→app telemetry,
            // mirroring the web live-session card. Fault supersedes warning.
            if (isFault) ...[
              const SizedBox(height: 10),
              _buildFaultCard(telemetry!),
            ] else if (isWarning) ...[
              const SizedBox(height: 10),
              _buildWarningBanner(telemetry!),
            ],
            // Per-device Protocol Plus progress card (only for Plus devices).
            if (isProtocolPlusDevice && plusSequence.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildProtocolPlusSequence(
                plusSequence,
                name: plusName,
                index: plusIndex,
                delaySeconds: plusDelaySeconds,
                onBreak: plusOnBreak,
                breakRemaining: plusBreakRemaining,
              ),
            ],
            if (protocolName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                protocolName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              decoration: status == SessionStatus.running
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ThemeConstants.accent.withValues(alpha: 0.10),
                          blurRadius: 26,
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : null,
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _TimerRing(
                      progress: displayProgress,
                      active: status == SessionStatus.running),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayRemaining.formatted,
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dark_mode_rounded,
                                size: 20, color: effectiveMoonColor),
                            const SizedBox(width: 12),
                            Icon(Icons.wb_sunny_rounded,
                                size: 22, color: effectiveSunColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            if (totalCycles > 0 && padCycleIdx >= 0) ...[
              const SizedBox(height: 8),
              Text(
                'Cycle ${padCycleIdx + 1}/$totalCycles',
                style: TextStyle(
                  color: ThemeConstants.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
            // Live sensor readouts (temperature/voltage/current/…) when the
            // firmware/backend includes them in the telemetry frame.
            if (telemetry != null && telemetry.sensorReadouts.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSensorReadouts(telemetry.sensorReadouts),
            ],
            const SizedBox(height: 16),
            _buildPerDeviceControls(id, status, ctrl,
                isProtocolPlusDevice: isProtocolPlusDevice,
                plusOnBreak: plusOnBreak),
          ],
        ),
      ),
    );
  }

  Widget _buildPerDeviceControls(
    String deviceId,
    SessionStatus status,
    SessionEngine ctrl, {
    bool isProtocolPlusDevice = false,
    bool plusOnBreak = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softSurface = isDark ? ThemeConstants.surfaceVariant : Colors.white;

    // REMOTE VIEW: drive the device over the cloud broker + backend instead of
    // the local engine. Resolve the live session for this run; if it's gone from
    // the feed there's nothing to control.
    final bool remote = widget.remoteView;
    active_session.ActiveSession? remoteSession;
    if (remote) {
      for (final x in ref.read(liveSessionsProvider)) {
        if (x.id == widget.backendSessionId) {
          remoteSession = x;
          break;
        }
      }
      if (remoteSession == null) return const SizedBox.shrink();
    }
    final wifiRemote = remote ? ref.read(wifiRemoteControlProvider) : null;
    void pauseFn() => remote
        ? wifiRemote!.pauseDevice(remoteSession!, deviceId)
        : ctrl.pauseDevice(deviceId);
    void resumeFn() => remote
        ? wifiRemote!.resumeDevice(remoteSession!, deviceId)
        : ctrl.resumeDevice(deviceId);
    void stopFn() => remote
        ? wifiRemote!.stopDevice(remoteSession!, deviceId)
        : ctrl.stopDevice(deviceId);

    // While a BLE device's link is down during a live run, its pause/stop/resume
    // commands can't reach it — keep the buttons visible but DISABLED (greyed).
    // Reconnect happens silently in the background; no extra UI/label. WiFi is
    // unaffected (commands go over MQTT, no live BLE link needed).
    final isLive =
        status == SessionStatus.running || status == SessionStatus.paused;
    final disconnected = widget.transport == 'ble' &&
        isLive &&
        ref.watch(bleDeviceStatusProvider(deviceId)) !=
            BleConnectionStatus.connected;

    // Protocol Plus runs on a server-scheduled timeline; pausing/resuming would
    // desync the scheduled protocol switches, so only Stop is offered. Normal
    // protocol devices (incl. those in a mixed session) keep pause/resume.
    if (isProtocolPlusDevice &&
        (status == SessionStatus.running || status == SessionStatus.paused)) {
      // During a break the firmware is idle and the BLE link is expected to be
      // down — that's NOT a reason to block Stop. Stopping then just cancels the
      // server-scheduled remaining protocols (no live link needed), so keep the
      // button enabled even while disconnected mid-break.
      final blockStop = disconnected && !plusOnBreak;
      return SizedBox(
        height: 44,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: blockStop ? null : stopFn,
          style: ElevatedButton.styleFrom(
            backgroundColor: ThemeConstants.error,
            foregroundColor: ThemeConstants.textPrimary,
          ),
          child: const Text('Stop'),
        ),
      );
    }

    if (status == SessionStatus.running) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: disconnected ? null : pauseFn,
                style: OutlinedButton.styleFrom(
                  backgroundColor: softSurface,
                  foregroundColor: ThemeConstants.textPrimary,
                  side: BorderSide(color: ThemeConstants.borderLight),
                ),
                child: Text('Pause'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: disconnected ? null : stopFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.error,
                  foregroundColor: ThemeConstants.textPrimary,
                ),
                child: Text('Stop'),
              ),
            ),
          ),
        ],
      );
    }
    if (status == SessionStatus.paused) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: disconnected ? null : resumeFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.accent,
                  foregroundColor: ThemeConstants.textPrimary,
                ),
                child: Text('Resume'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: disconnected ? null : stopFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.error,
                  foregroundColor: ThemeConstants.textPrimary,
                ),
                child: Text('Stop'),
              ),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: null,
        child: Text(_statusLabel(status)),
      ),
    );
  }

  /// REMOTE VIEW: session-wide Pause All / Resume All / Stop All for a foreign
  /// WiFi run, routed through the cloud broker + backend.
  Widget _buildRemoteAllControls(
    SessionStatus status,
    List<active_session.ActiveSession> sessions,
  ) {
    active_session.ActiveSession? s;
    for (final x in sessions) {
      if (x.id == widget.backendSessionId) {
        s = x;
        break;
      }
    }
    if (s == null) return const SizedBox.shrink();
    final session = s;
    final remote = ref.read(wifiRemoteControlProvider);
    final paused = status == SessionStatus.paused;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () =>
                    paused ? remote.resume(session) : remote.pause(session),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                label: Text(paused ? 'Resume All' : 'Pause All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.accent,
                  foregroundColor: ThemeConstants.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => remote.stop(session),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.error,
                  foregroundColor: ThemeConstants.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(SessionStatus status, SessionEngine ctrl) {
    return switch (status) {
      SessionStatus.idle => SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            // WiFi sessions auto-start once protocol loads; don't allow manual start.
            onPressed: widget.transport == 'wifi' || _startingSession
                ? null
                : () async {
                    setState(() => _startingSession = true);
                    try {
                      await ctrl.start();
                      final currentProtocol = ref
                          .read(sessionEngineFamilyProvider(_engineKey))
                          .protocol;
                      await _ensureActiveSessionCreated(
                        protocolName:
                            currentProtocol?.templateName ?? 'Unknown Protocol',
                      );
                      await _syncCurrentSessionToActiveSessions();
                    } finally {
                      if (mounted) {
                        setState(() => _startingSession = false);
                      }
                    }
                  },
            child: _startingSession
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.transport == 'wifi' ? 'Starting…' : 'Start Session'),
          ),
        ),
      SessionStatus.running => const SizedBox.shrink(),
      SessionStatus.paused => const SizedBox.shrink(),
      SessionStatus.stopped || SessionStatus.completed => SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
              onPressed: () async {
                await _removeTrackedSessionIfAny();
                ctrl.reset();
                if (!mounted) return;
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.success),
              child: Text('Done'))),
    };
  }

  Color _statusColor(SessionStatus s) => switch (s) {
        SessionStatus.idle => ThemeConstants.textTertiary,
        SessionStatus.running => ThemeConstants.success,
        SessionStatus.paused => ThemeConstants.warning,
        SessionStatus.stopped => ThemeConstants.error,
        SessionStatus.completed => ThemeConstants.success,
      };

  String _statusLabel(SessionStatus s) => switch (s) {
        SessionStatus.idle => 'Ready',
        SessionStatus.running => 'Running',
        SessionStatus.paused => 'Paused',
        SessionStatus.stopped => 'Stopped',
        SessionStatus.completed => 'Completed',
      };

  static bool _strEqIc(String a, String b) =>
      a.toLowerCase().trim() == b.toLowerCase().trim();

  /// Same rules as web `DeviceTimer` Moon icon (left pad). Accepts both the
  /// backend vocabulary ('hot'/'cold'/'leftHotRed'/'leftColdBlue') and the BLE
  /// frame's LED color ('red'/'blue', from p2.l) so live telemetry colors match.
  Color _webMoonPadColor(String? moon) {
    if (moon == null || moon.isEmpty) return Colors.grey;
    final m = moon.trim();
    if (_strEqIc(m, 'leftHotRed') || _strEqIc(m, 'hot') || _strEqIc(m, 'red')) {
      return Colors.red;
    }
    if (_strEqIc(m, 'leftColdBlue') ||
        _strEqIc(m, 'cold') ||
        _strEqIc(m, 'blue')) {
      return Colors.blue;
    }
    return Colors.grey;
  }

  /// Same rules as web `DeviceTimer` Sun icon (right pad). Accepts 'red'/'blue'
  /// (from p1.l) in addition to the backend 'hot'/'cold' vocabulary.
  Color _webSunPadColor(String? sun) {
    if (sun == null || sun.isEmpty) return Colors.grey;
    final s = sun.trim();
    if (_strEqIc(s, 'rightHotRed') || _strEqIc(s, 'hot') || _strEqIc(s, 'red')) {
      return Colors.red;
    }
    if (_strEqIc(s, 'rightColdBlue') ||
        _strEqIc(s, 'cold') ||
        _strEqIc(s, 'blue')) {
      return Colors.blue;
    }
    return Colors.grey;
  }
}

class _TimerRing extends CustomPainter {
  final double progress;
  final bool active;
  _TimerRing({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final bg = Paint()
      ..color = ThemeConstants.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..color = ThemeConstants.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2,
        2 * pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _TimerRing old) => progress != old.progress;
}
