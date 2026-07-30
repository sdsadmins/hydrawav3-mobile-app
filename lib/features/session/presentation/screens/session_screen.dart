import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/storage/preferences.dart';
import '../../../../core/theme/widgets/hw_info_dialog.dart';
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
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../../session/domain/session_model.dart' as session_model;
import '../../../session/domain/active_session_model.dart' as active_session;
import '../../../session/data/session_repository.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/presentation/providers/pending_outcomes_provider.dart';
import '../widgets/post_session_outcomes_sheet.dart';
import '../../../session/services/background_session_runtime.dart';
import '../../../session/services/wifi_remote_control.dart';

/// Session-screen device layout preference: `true` = vertical (all device cards
/// in one scroll), `false` = horizontal pager (swipe + dot indicator). Persisted
/// so the user's choice sticks across launches.
final sessionDevicesVerticalProvider =
    StateNotifierProvider<SessionDeviceLayoutController, bool>((ref) {
  return SessionDeviceLayoutController(ref.read(preferencesProvider));
});

class SessionDeviceLayoutController extends StateNotifier<bool> {
  SessionDeviceLayoutController(this._prefs)
      : super(_prefs.sessionDevicesVertical);

  final PreferencesService _prefs;

  Future<void> toggle() async {
    state = !state;
    await _prefs.setSessionDevicesVertical(state);
  }
}

class SessionScreen extends ConsumerStatefulWidget {
  final String? sessionId;
  final String protocolId;
  final Protocol? protocol;
  final List<String> deviceIds;
  final Map<String, String> protocolByDeviceId;
  final bool skipEngineBootstrap;

  /// 'ble' or 'wifi'
  final String transport;

  /// Epoch ms when WiFi MQTT config last succeeded â€” aligns app timer with device.
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
  /// phone). When true, no local SessionEngine is bootstrapped â€” timers/pads/
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

/// Live-session chrome uses the UI handoff's palette (`RefPalette`), the same
/// tokens the Hub, More, pad map and AI report already use — this screen was the
/// last large surface still on `ThemeConstants`, which made it read as a
/// different product. The engine, BLE, Protocol Plus and server-sync code above
/// the widget builders is untouched; only colours changed.
///
/// One mapping worth knowing: `ThemeConstants.accent` became `copperInk` rather
/// than `copper`. `copper` (#C69E83) is the handoff's fill tone and is too light
/// for the text and icons this screen uses it for; `copperInk` (#8A5F42) stays
/// legible everywhere and still reads as copper on a stroke.
class _SessionScreenState extends ConsumerState<SessionScreen>
    with WidgetsBindingObserver {
  /// The handoff palette for the current theme. A getter rather than a local in
  /// every builder: this State has ~20 widget methods and threading a palette
  /// argument through all of them would be noise.
  RefPalette get pal => RefPalette.of(context);

  bool _bootstrapStarted = false;
  int _activeDevicePage = 0;
  ProviderSubscription<SessionEngineState>? _engineSub;
  ProviderSubscription<AsyncValue<Map<String, BleConnectionStatus>>>?
      _bleConnectionSub;
  bool _startingSession = false;
  bool _terminalSessionCleanupInFlight = false;
  bool _outcomesPromptShown = false;
  String? _activeSessionId;
  String? _historySnapshotSessionId;
  late final String _engineKey;

  Timer? _padPollTimer;

  /// Per-device grace timers for the "device is not in range" popup. Armed on a
  /// connectedâ†’disconnected edge, cancelled if the unit comes back.
  final Map<String, Timer> _outOfRangeTimers = {};

  /// One out-of-range dialog at a time, and the device it is about (so it can be
  /// dismissed when that device reconnects).
  String? _outOfRangeDialogDeviceId;

  /// The out-of-range dialog route's own context, used to close it precisely.
  BuildContext? _outOfRangeDialogContext;

  /// How long a bound device must stay gone before we tell the user it's out of
  /// range. The connector auto-reconnects up to `maxReconnectAttempts` (5) with
  /// a `reconnectDelay * attempt` backoff (~9s of delay in total) and
  /// AutoConnectManager restarts a scan on the same edge, so waiting 12s means
  /// the popup only appears once that built-in recovery has genuinely failed.
  /// It also silently covers the connector's OWN disconnectâ†’reconnect during
  /// write recovery (350ms + connect â‰¤6s), which must never raise a popup.
  static const Duration _kOutOfRangeGrace = Duration(seconds: 12);

  final Map<String, String> _deviceLabelById = {};

  /// Captured in initState so it can be disposed without touching `ref` later.
  ProtocolPlusController? _protocolPlusController;

  /// Session "Atmosphere" music â€” captured in initState so play/pause can be
  /// driven from lifecycle/status callbacks and stopped on dispose.
  SessionMusicController? _musicController;

  /// Whether the app is currently in the foreground. Music is foreground-only,
  /// so this gates playback alongside the session-running state.
  bool _isForeground = true;

  /// Guards the one-time socket connect (bindings can arrive synchronously via
  /// the widget or late via [protocolPlusBindingsProvider] â€” connect only once).
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

  /// One-shot guard so the session-setup reset (clears the guided-assessment
  /// area of focus so Start is disabled again) fires at most once per terminal.
  bool _setupResetAfterStop = false;

  /// One-shot guard for the pad-poll diagnostic log.
  bool _padDiagLogged = false;

  /// Whether this run's backend session has appeared in the live feed â€” lets us
  /// tell "not started yet" from "stopped remotely" (web/another device).
  bool _backendSessionSeen = false;

  /// Last backend status we reconciled, so remote pause/resume is applied only
  /// on an actual transition (edge-triggered) â€” never level-triggered off the
  /// 1s poll, which would fight a local pause during the backend round-trip.
  active_session.SessionStatus? _lastRemoteStatus;

  /// When the LOCAL user last drove a session pause/resume. During the backend
  /// round-trip the live feed flaps (per-device `dev.status` and session-level
  /// status disagree, and the device can briefly drop from a frame), so the
  /// reconciled `remote` oscillates between the old and new value. Without this
  /// guard each flap is treated as a fresh remote command and reverses the
  /// user's own button â€” pause, resume, pauseâ€¦ for a few seconds until the
  /// backend settles. While this window is open we ignore any backend status
  /// that contradicts the local engine; genuine remote actions still apply once
  /// the backend agrees with us or the window elapses.
  DateTime? _localLifecycleActionAt;

  /// How long a local pause/resume "wins" over a contradicting backend echo.
  static const Duration _localLifecycleSettleWindow = Duration(seconds: 6);

  /// Last reconcile log signature, to log transitions without per-second spam.
  String? _lastReconcileSig;

  /// Listener that reconciles the local engine with remote stop/pause/resume
  /// for a normal run (Protocol Plus runs are reconciled by their controller).
  ProviderSubscription<List<active_session.ActiveSession>>? _liveSessionsSub;

  /// Human-readable label for a device. Prefers a LOCALLY-known name (paired
  /// BLE / org WiFi), then the backend live-feed's registered [fallbackName]
  /// (the only source for a FOREIGN BLE session â€” we aren't bonded to its
  /// devices, so they're not in the local paired map), and only shows the raw
  /// id as a last resort.
  String _deviceLabel(String id, {String? fallbackName}) {
    final key = _normalizeMac(id);
    final local = _deviceLabelById[key];
    if (local != null && local.isNotEmpty) return local;
    if (fallbackName != null && fallbackName.isNotEmpty) return fallbackName;
    return id;
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
    // live feed â€” there is no local engine to bootstrap, listen to, or sync.
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

          // Back in range â†’ drop the pending warning and close one already up.
          if (currentStatus == BleConnectionStatus.connected &&
              previousStatus != BleConnectionStatus.connected) {
            _cancelOutOfRangeWarning(deviceId);
            continue;
          }

          if (!_isDisconnectTransition(previousStatus, currentStatus)) {
            continue;
          }
          unawaited(_handleBleDisconnect(deviceId));
          _armOutOfRangeWarning(deviceId);
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
        // never try to reload it â€” for a Plus run the loaded sub-protocol id
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
            // carries no per-device protocol map. Don't crash the setup â€” abort
            // the reload and leave the existing engine/session running.
            appLogger.w(
                'Skipping engine reload â€” no protocolByDeviceId (re-attach).');
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
    // the org-wide feed reflects it (via the /sessions socket) â€” apply it here
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

    // Case 1: bindings already known â€” synchronous launch / history re-open /
    // the single-device legacy fields. Connect straight away.
    final immediate = _resolveImmediateBindings();
    if (immediate.isNotEmpty) {
      _connectProtocolPlus(immediate);
      return;
    }

    // Case 2: instant-UI launch â€” registration is still in flight. Watch the
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
    // before that there is nothing on the server to pause/resume/stop yet â€” the
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
  /// it may already be present or arrive slightly later â€” handle both.
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
      // Local pause/resume wins over its own in-flight backend echo (see
      // [_localLifecycleActionAt]); stamp it so the reconciler doesn't flap.
      _localLifecycleActionAt = DateTime.now();
      unawaited(sync.pauseServerSession(backendId));
    } else if (prevS == SessionStatus.paused &&
        nextS == SessionStatus.running) {
      _localLifecycleActionAt = DateTime.now();
      unawaited(sync.resumeServerSession(backendId));
    }
  }

  /// Mirror a remote stop/pause/resume onto the local engine for a NORMAL run.
  /// Pause/resume reconcile the UI only (the remote client already commanded the
  /// device â€” Wi-Fi via MQTT); a remote stop ends the run locally too.
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
      // Backend session is gone â€” stopped/finished elsewhere. End locally too,
      // but only if we'd actually seen it (so we don't stop a run whose backend
      // session simply hasn't appeared in the feed yet).
      if (_backendSessionSeen && !_normalServerStopped && localLive) {
        _normalServerStopped = true; // remote already stopped the server side
        appLogger.i('Session: backend $backendId removed â€” applying remote stop');
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

    // Local action wins during its settle window: while a just-issued local
    // pause/resume is still propagating, the feed flaps between the old and new
    // status (per-device vs session-level disagree). Ignore any backend value
    // that contradicts the local engine â€” and crucially do NOT advance
    // _lastRemoteStatus, so the matching value keeps short-circuiting above and
    // the contradicting value never edge-triggers an engine action. Genuine
    // remote changes still apply once the window elapses.
    final localAction = _localLifecycleActionAt;
    final localActive = localStatus == SessionStatus.running ||
        localStatus == SessionStatus.paused;
    if (localAction != null && localActive) {
      if (DateTime.now().difference(localAction) < _localLifecycleSettleWindow) {
        if (remote != _toActiveStatus(localStatus)) {
          appLogger.i('Reconcile[$backendId]: ignoring backend echo $remote '
              'while local=$localStatus settles');
          return;
        }
      } else {
        // Window elapsed â€” drop the guard so later remote changes are honoured.
        _localLifecycleActionAt = null;
      }
    }

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
          'local=$localStatus â€” no engine action');
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
    // screen is off, and the monotonic clock skips deep-sleep time â€” so the
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
  /// state. Best-effort â€” the controller swallows any audio error.
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
      backgroundColor: pal.card,
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
                              size: 20, color: pal.copperInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Session Atmosphere',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: pal.ink,
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
                                  ? pal.ink2
                                  : pal.ink3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Looping music plays while the session is running.',
                        style: TextStyle(
                          fontSize: 12,
                          color: pal.ink2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // "None" â€” clear the current selection.
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
                                  TextStyle(color: pal.ink2),
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
                                    color: pal.ink2,
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
                                          color: pal.copperInk)
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
              ? pal.copperInk.withValues(alpha: 0.12)
              : pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? pal.copperInk : pal.line,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? pal.copperInk
                    : pal.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: pal.ink,
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
        // usable â€” disable unconditionally (best-effort) to avoid leaking the
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
    // Music is a session-screen feature â€” never let it outlive the screen.
    unawaited(_musicController?.stopAndReset() ?? Future<void>.value());
    unawaited(_setWakelock(false, fromDispose: true));
    _stopBackendPadPolling(fromDispose: true);
    _engineSub?.close();
    _bleConnectionSub?.close();
    for (final t in _outOfRangeTimers.values) {
      t.cancel();
    }
    _outOfRangeTimers.clear();
    _plusBindingsSub?.close();
    _normalServerIdSub?.close();
    _liveSessionsSub?.close();
    // NOTE: We intentionally do NOT dispose the Protocol Plus socket here.
    // The socket must outlive this screen: a Protocol Plus run keeps receiving
    // the server's START_PROTOCOL switches and applying them via the
    // app-scoped SessionEngine even after the user navigates away from the
    // session screen. The socket is instead torn down when the run actually
    // ends (stop/complete â€” see _maybeSyncProtocolPlusServer) or when the next
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
        // source of truth) rather than a separate fetch â€” it already polls
        // /sessions/active every second and parses per-device sun/moon. Match
        // each local device to its backend device (WiFi exact mac, BLE Â±1) and
        // feed the backend frame into the engine keyed by the LOCAL id so the
        // per-device card picks it up (and goes grey when the backend reports
        // the pad disabled â€” web parity).
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
  /// sessions. Matches WiFi by exact (normalized) MAC and BLE by Â±1 last byte
  /// (units advertise on a MAC Â±1 from the registered/firmware id).
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

  /// The backend session containing [localId] that the feed flagged as a
  /// Protocol Plus run (has a parsed sub-protocol sequence). Used to render the
  /// sequence tracker from the feed when the local engine has no Plus state
  /// (web parity â€” any client shows a Plus run as Plus, not just the launcher).
  active_session.ActiveSession? _findBackendPlusSession(
    List<active_session.ActiveSession> sessions,
    String localId,
  ) {
    final candidates = _normalizedMacVariants(localId);
    for (final s in sessions) {
      if (s.protocolPlusSequence.isEmpty) continue;
      for (final d in s.liveDevices) {
        if (candidates.contains(_normalizeMac(d.deviceId))) return s;
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
    // clientType / clientId / intake come from the engine context set by the
    // launcher (setClientContext) â€” guest when none was provided.
    final record = sessionEngine.getSessionRecord(
      sessionId: sessionId,
      createdBy: userId,
      updatedBy: userId,
      createdAt: now,
      updatedAt: now,
      discomfortBefore: 6,
      discomfortAfter: 2,
      notes: 'Session started from mobile app',
    );

    if (record == null) {
      // Couldn't build a record yet â€” release the claim so a later, valid
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

  /// Start the countdown to telling the user this unit is out of range. The
  /// session itself is deliberately left alone â€” the firmware keeps running the
  /// loaded protocol after the link drops, so a walk out of range must not end
  /// a valid treatment (see `SessionEngine.handleBleDisconnect`).
  void _armOutOfRangeWarning(String deviceId) {
    _outOfRangeTimers[deviceId]?.cancel();
    _outOfRangeTimers[deviceId] = Timer(_kOutOfRangeGrace, () {
      _outOfRangeTimers.remove(deviceId);
      unawaited(_showOutOfRangeWarning(deviceId));
    });
  }

  /// The unit is back (or the screen is going away): drop the pending warning
  /// and close the dialog if it was about this device.
  void _cancelOutOfRangeWarning(String deviceId) {
    _outOfRangeTimers.remove(deviceId)?.cancel();
    if (_outOfRangeDialogDeviceId != deviceId) return;
    // Reconnected while the popup was up â€” take it away rather than making the
    // user dismiss a message that is no longer true. Popping through the
    // DIALOG's own context (not the screen's) means that once the user has
    // already dismissed it, `mounted` is false and we can't pop anything else.
    final dialogContext = _outOfRangeDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _showOutOfRangeWarning(String deviceId) async {
    if (!mounted || widget.transport != 'ble') return;
    // One at a time. With several units gone the first message already tells
    // the user what to do.
    if (_outOfRangeDialogDeviceId != null) return;

    // Only while the run is live â€” this screen can outlive the session.
    final engine = ref.read(sessionEngineFamilyProvider(_engineKey));
    if (engine.status != SessionStatus.running &&
        engine.status != SessionStatus.paused) {
      return;
    }

    final ble = ref.read(bleRepositoryProvider);
    // Came back during the grace window (the connection-state edge may not have
    // fired if it bounced quickly).
    if (ble.isConnected(deviceId)) return;
    // Deliberate drop: an in-app stop/disconnect, session-end reconnect
    // suppression, or the connector's own mid-write recovery. None of these
    // mean the device is out of range.
    if (ble.isReconnectSuppressed(deviceId)) return;
    // Wi-Fi provisioning always drops BLE â€” that's the flow working, not a fault.
    if (ref.read(bleProvisioningIdsProvider).contains(deviceId)) return;

    _outOfRangeDialogDeviceId = deviceId;
    try {
      await showHwInfoDialog(
        context,
        icon: Icons.bluetooth_disabled_rounded,
        iconColor: pal.mid,
        title: 'Your Hydrawave device is not in range',
        message:
            '${_deviceLabel(deviceId)} lost its Bluetooth connection. Please '
            'move closer to the device â€” or bring it nearer to your phone â€” and '
            'it will reconnect automatically. Your session keeps running.',
        actionLabel: 'OK',
        onDialogContext: (ctx) => _outOfRangeDialogContext = ctx,
      );
    } finally {
      _outOfRangeDialogDeviceId = null;
      _outOfRangeDialogContext = null;
    }
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

    // Queue the post-session review snapshot (idempotent, client-only). We do
    // NOT auto-open the sheet here â€” web parity: the questions appear on the
    // explicit Stop All / Done end-action. If the session ended off-screen, the
    // queued snapshot surfaces as a "Needs review" card on the Live feed.
    if (!widget.remoteView) {
      ref
          .read(sessionEngineFamilyProvider(_engineKey).notifier)
          .enqueuePendingOutcome();
      // On Stop All (or any terminal), clear the per-session intake so the
      // session setup resets â€” in Client mode this empties the area of focus,
      // which disables "Start Session" until a new assessment is done. Safe:
      // the outcomes sheet finalizes off the engine's snapshot, not this state.
      if (!_setupResetAfterStop) {
        _setupResetAfterStop = true;
        ref.read(guidedAssessmentProvider.notifier).reset();
      }
    }

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

  /// Present the post-session outcomes sheet for this session (if it has a
  /// queued review), then finalize â€” a single `/intake` POST with the answers,
  /// or a bare log on Skip/dismiss. Idempotent via [_outcomesPromptShown].
  Future<void> _promptSessionOutcomes() async {
    if (_outcomesPromptShown) return;
    final notifier = ref.read(pendingOutcomesProvider.notifier);
    final pending = notifier.needsReviewById(_engineKey);
    if (pending == null) return; // nothing queued, or already answered
    _outcomesPromptShown = true;
    if (!mounted) return;
    final outcomes = await showPostSessionOutcomesSheet(
      context,
      protocolQuestions: pending.orderedProtocolQuestions,
    );
    // outcomes == null â†’ Skip/dismiss: still log the session (no answers).
    await notifier.finalize(_engineKey, outcomes);
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

    // REMOTE VIEW mirrors a foreign WiFi session from the feed â€” synthesize a
    // read-only engine state from it so the existing UI renders unchanged.
    final engine = widget.remoteView
        ? _remoteEngineState(liveSessions)
        : ref.watch(sessionEngineFamilyProvider(_engineKey));

    // Get session-specific data instead of always using engine state
    final activeSessions = ref.watch(activeSessionsProvider);
    final currentSession = _findTrackedSession(activeSessions);

    final timer = engine.timer;
    // The local engine is authoritative for an own run in ANY non-idle state â€”
    // running, paused, AND a just-reached terminal (stopped/completed). Only
    // fall back to the tracked/backend session status when the engine hasn't
    // taken over yet (idle), e.g. right after re-entering a live (WiFi) session.
    //
    // Including the terminal case is what fixes the device-pressed-stop glitch:
    // a firmware `rs:stop` flips the engine to stopped immediately, but the
    // org-wide feed still reports the device "running" for up to a minute â€” so
    // without this the Stop/Pause controls would snap back to enabled until the
    // feed caught up. Trusting the engine's terminal state keeps them disabled.
    final engineAuthoritative = engine.status != SessionStatus.idle;
    final status = engineAuthoritative
        ? engine.status
        : (currentSession == null
            ? engine.status
            : _toSessionStatus(currentSession.status));
    final ctrl = ref.read(sessionEngineFamilyProvider(_engineKey).notifier);
    // The session-wide control card (Pause All / Stop All) shows while a run is
    // live. For a remote/foreign view it also stays after the run has
    // completed/stopped, so the user can still send Stop All to the backend and
    // clear the session from the live feed (it can't be auto-cleared).
    final showTopControl = status == SessionStatus.running ||
        status == SessionStatus.paused ||
        (widget.remoteView &&
            (status == SessionStatus.completed ||
                status == SessionStatus.stopped));
    final protocol = engine.protocol;
    // During timed pause gaps the engine sets currentCycleIndex to -1, but
    // the pads still reflect the active protocol cycle â€” use lastVisualCycleIndex.
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
    // (the org-wide live feed). No local cycle fallback â€” when the backend
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

    final verticalLayout = ref.watch(sessionDevicesVerticalProvider);

    // Builds one device card, shared by the vertical list and the horizontal
    // pager so the (large) argument wiring isn't duplicated.
    Widget buildDeviceCard(String id, {required bool scrollable}) {
      final deviceTimer = engine.deviceTimers[id]!;
      final deviceStatus = engine.deviceStatuses[id] ?? SessionStatus.idle;
      final perDeviceProtocolName =
          engine.protocolByDevice[id]?.templateName ??
              protocol?.templateName ??
              '';
      final backendDev = _findBackendLiveDevice(liveSessions, id);

      // Prefer the local engine's Plus state (it also drives the live break
      // countdown). Fall back to the BACKEND FEED's Protocol Plus info when the
      // engine has none â€” so a Plus run this client didn't launch (remote view /
      // re-opened / feed-only) still renders the sequence tracker (web parity).
      var deviceSequence =
          engine.protocolPlusSequenceByDevice[id] ?? const <String>[];
      var plusName = engine.protocolPlusNameByDevice[id] ?? '';
      var plusIndex = engine.protocolPlusIndexByDevice[id] ?? 0;
      var plusDelay = engine.protocolPlusDelayByDevice[id] ?? 0;
      var plusOnBreak = engine.protocolPlusOnBreakByDevice[id] ?? false;
      var plusBreakRemaining =
          engine.protocolPlusBreakRemainingByDevice[id] ?? 0;
      if (deviceSequence.isEmpty) {
        final ppSession = _findBackendPlusSession(liveSessions, id);
        if (ppSession != null) {
          deviceSequence = ppSession.protocolPlusSequence;
          plusName = ppSession.protocolPlusName;
          plusDelay = ppSession.protocolPlusDelaySeconds;
          // Active sub-protocol = the device's current backend `protocol` name
          // matched against the sequence (web parity); break state isn't derived
          // from the feed (no live break countdown without the local engine).
          final active = backendDev?.protocol;
          final idx = active == null ? -1 : deviceSequence.indexOf(active);
          plusIndex = idx >= 0 ? idx : 0;
          plusOnBreak = false;
          plusBreakRemaining = 0;
        }
      }
      return _buildDeviceSessionCard(
        id: id,
        // Foreign BLE devices aren't in the local paired map â€” fall back to the
        // backend feed's registered name instead of the raw bluetooth id.
        label: _deviceLabel(id, fallbackName: backendDev?.deviceName),
        protocolName: perDeviceProtocolName,
        timer: deviceTimer,
        status: deviceStatus,
        totalCycles: timer.totalCycles,
        padCycleIdx: padCycleIdx,
        moonColor: _webMoonPadColor(backendDev?.moon),
        sunColor: _webSunPadColor(backendDev?.sun),
        // Timer comes from the backend (single source of truth) so the app
        // matches the web exactly instead of drifting from the local engine.
        backendRemainingSeconds: backendDev?.remainingSeconds,
        backendTotalSeconds: backendDev?.totalDurationSeconds,
        telemetry: engine.telemetryByDevice[id],
        ctrl: ctrl,
        isProtocolPlusDevice: deviceSequence.isNotEmpty,
        plusSequence: deviceSequence,
        plusDurations:
            engine.protocolPlusDurationsByDevice[id] ?? const <int>[],
        plusName: plusName,
        plusIndex: plusIndex,
        plusDelaySeconds: plusDelay,
        plusOnBreak: plusOnBreak,
        plusBreakRemaining: plusBreakRemaining,
        scrollable: scrollable,
      );
    }

    return Scaffold(
      backgroundColor: pal.bg,
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
          // Toggle between the vertical list (all cards in one scroll) and the
          // horizontal pager (swipe + dots). Only useful with >1 device.
          if (orderedDeviceIds.length > 1)
            IconButton(
              tooltip: verticalLayout
                  ? 'Switch to swipe view'
                  : 'Switch to list view',
              onPressed: () =>
                  ref.read(sessionDevicesVerticalProvider.notifier).toggle(),
              icon: Icon(verticalLayout
                  ? Icons.view_carousel_outlined
                  : Icons.view_agenda_outlined),
            ),
          Consumer(
            builder: (context, musicRef, _) {
              final music = musicRef.watch(sessionMusicControllerProvider);
              final controller =
                  musicRef.read(sessionMusicControllerProvider.notifier);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mute toggle â€” visible top-level control while a track is
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
                            ? pal.ink2
                            : pal.copperInk,
                      ),
                    ),
                  // Session "Atmosphere" music â€” accent when a track is active.
                  IconButton(
                    tooltip: 'Session music',
                    onPressed: _showAtmosphereSheet,
                    icon: Icon(
                      music.hasTrack
                          ? Icons.music_note_rounded
                          : Icons.music_note_outlined,
                      color: music.hasTrack ? pal.copperInk : null,
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
            ] else if (orderedDeviceIds.isNotEmpty || showTopControl) ...[
              // Session-wide control card (device summary + Pause/Resume All +
              // Stop All) pinned above the per-device cards. Shown while the run
              // is live, and (for a remote/foreign view) also once it has
              // completed/stopped so the user can still Stop All to clear it.
              if (showTopControl)
                _buildTopControlCard(
                    status, ctrl, liveSessions, orderedDeviceIds.length),
              if (verticalLayout) ...[
                // Vertical: every device card stacked in one scroll (the body
                // ListView scrolls), so all devices are visible without swiping.
                for (final id in orderedDeviceIds) ...[
                  buildDeviceCard(id, scrollable: false),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
              ] else ...[
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
                    itemBuilder: (context, index) => buildDeviceCard(
                      orderedDeviceIds[index],
                      scrollable: true,
                    ),
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
                              ? pal.copperInk
                              : pal.ink3
                                  .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                const SizedBox(height: 24),
              ],
            ] else ...[
              const SizedBox(height: 24),
            ],

            // (Session-wide Pause/Resume/Stop All now live in the top control
            // card above the device cards â€” see _buildTopControlCard.)

            // Device status
            if (widget.deviceIds.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: pal.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pal.line)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: pal.good,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(
                      widget.transport == 'wifi'
                          ? '${widget.deviceIds.length} WiFi device(s) selected'
                          : '${widget.deviceIds.length} device(s) connected',
                      style: TextStyle(
                        color: pal.ink2,
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

  /// Protocol Plus tracker â€” a horizontal route map: the sequence title on top,
  /// then stops (stations) laid out leftâ†’right and joined by a track whose
  /// traveled portion is filled. The active stop pulses; passed stops show âœ“.
  /// Advances on each START_PROTOCOL.
  Widget _buildProtocolPlusSequence(
    List<String> names, {
    required String name,
    required int index,
    List<int> durations = const [],
    int delaySeconds = 0,
    bool onBreak = false,
    int breakRemaining = 0,
  }) {
    var currentIndex = index;
    if (currentIndex < 0) currentIndex = 0;
    if (currentIndex > names.length - 1) currentIndex = names.length - 1;
    // While on break the current protocol has finished and the next is "up
    // next" â€” there's always a next when on break (the engine never flags a
    // break on the final protocol).
    final hasNext = currentIndex < names.length - 1;
    final breaking = onBreak && hasNext;
    final nextIndex = breaking ? currentIndex + 1 : -1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row: Protocol Plus name + step counter.
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: pal.copperInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : 'Protocol Plus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: pal.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pal.copperInk.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentIndex + 1}/${names.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: pal.copperInk,
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
                    durationSeconds: i < durations.length ? durations[i] : 0,
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
    int durationSeconds = 0,
  }) {
    final Color dotBg;
    final Color dotFg;
    if (isActive) {
      dotBg = pal.copperInk;
      dotFg = Colors.white;
    } else if (isNext) {
      // "Up next" during a break â€” a hollow accent ring that pulses.
      dotBg = pal.copperInk.withValues(alpha: 0.14);
      dotFg = pal.copperInk;
    } else if (isPast) {
      dotBg = pal.copperInk.withValues(alpha: 0.20);
      dotFg = pal.copperInk;
    } else {
      dotBg = pal.card2;
      dotFg = pal.ink3;
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
                  ? pal.copperInk
                  : isPast
                      ? pal.copperInk.withValues(alpha: 0.35)
                      : pal.line,
              width: 2,
            ),
            boxShadow: isActive || isNext
                ? [
                    BoxShadow(
                      color: pal.copperInk
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
                ? pal.ink
                : isPast
                    ? pal.ink3
                    : pal.ink2,
          ),
        ),
        if (durationSeconds > 0) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined,
                  size: 9, color: pal.ink3),
              const SizedBox(width: 2),
              Text(
                _fmtStopDuration(durationSeconds),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: pal.ink3,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 3),
        if (isActive)
          Text(
            'RUNNING',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: pal.copperInk,
            ),
          )
        else if (isNext)
          Text(
            'UP NEXT',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: pal.copperInk.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }

  /// Compact per-protocol duration label for a route stop: "45s", "5m", "5m 30s".
  String _fmtStopDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  /// The connecting track segment between two stations. Sits at dot height.
  /// When [delaySeconds] > 0 (a Protocol Plus break), shows the break time as
  /// minutes and seconds above the line, e.g. "1m 30s". When [active] is true the
  /// break on THIS segment is happening right now, so [countdown] (the live
  /// remaining time) is shown instead and the line is accented.
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
            ? pal.copperInk.withValues(alpha: 0.55)
            : active
                ? pal.copperInk
                : pal.line,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    // Live break on this segment â†’ show the counting-down remaining time.
    if (active) {
      final secs = (countdown ?? 0) > 0 ? _formatBreak(countdown!) : 'â€¦';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            secs,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: pal.copperInk,
            ),
          ),
          const SizedBox(height: 2),
          line,
        ],
      );
    }

    // No break time â†’ keep the bare line vertically centered on the ~26-30px dot.
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
          _formatBreak(delaySeconds),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: pal.ink3,
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
        color: pal.copperInk.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: pal.copperInk.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            counting ? Icons.pause_circle_filled_rounded : Icons.sync_rounded,
            size: 18,
            color: pal.copperInk,
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
                    color: pal.copperInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  counting
                      ? 'Next: $nextName'
                      : 'Starting $nextNameâ€¦',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pal.ink,
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
                color: pal.copperInk,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Format a Protocol Plus break as an informative "1m 30s" (or "45s" / "5m"),
  /// matching the per-protocol station duration labels.
  String _formatBreak(int seconds) => _fmtStopDuration(seconds);

  /// Red fault card â€” blocking firmware error (overcurrent / device fault).
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

  /// Orange warning banner â€” non-blocking (firmware keeps running). Mirrors the
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
  /// âš ï¸ BEST-EFFORT â€” these short keys are firmware-defined and are NOT
  /// documented in the app/web codebase. Confirm each meaning (and unit) with
  /// the firmware team and correct the mapping below; unknown keys fall back to
  /// the raw key so nothing is hidden.
  static const Map<String, ({String label, String? unit})> _telemetryLabels = {
    // Confirmed against a real frame; units still BEST-EFFORT (verify w/ firmware).
    'tp': (label: 'Temp', unit: 'Â°C'),
    'c': (label: 'Current', unit: 'A'),
    'av': (label: 'Voltage', unit: 'V'),
    // `td` / `tl` meanings are NOT yet identified (both read 0 mid-session) â€”
    // intentionally left unmapped so they render as raw keys, not mislabeled.
  };

  /// Generic live sensor readouts (temperature/voltage/current/â€¦). Field names
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
            color: pal.copperInk.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label: $valueText',
            style: TextStyle(
              color: pal.ink2,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Wrap [child] in a [SingleChildScrollView] only when [scrollable]; otherwise
  /// return it as-is (so it sizes to its content in the vertical list).
  Widget _maybeScroll({required bool scrollable, required Widget child}) {
    return scrollable ? SingleChildScrollView(child: child) : child;
  }

  /// Builds the ring's arcs for a Protocol Plus run: one per sub-protocol, with
  /// a break arc between consecutive stages.
  ///
  /// Returns empty for a plain protocol (and when the engine hasn't reported
  /// per-stage durations yet), which makes the ring fall back to its single
  /// continuous arc. Durations are the ENGINE's, so the ring can't disagree with
  /// what the device is actually doing.
  List<_RingSegment> _plusRingSegments({
    required List<String> plusSequence,
    required List<int> plusDurations,
    required int breakSeconds,
  }) {
    if (plusSequence.length < 2) return const [];
    // Without real per-stage durations the arcs would be a guess â€” better one
    // honest arc than a sequence drawn to the wrong proportions.
    if (plusDurations.length != plusSequence.length) return const [];

    final out = <_RingSegment>[];
    for (var i = 0; i < plusSequence.length; i++) {
      out.add(_RingSegment(plusDurations[i].toDouble()));
      if (i < plusSequence.length - 1 && breakSeconds > 0) {
        out.add(_RingSegment(breakSeconds.toDouble(), isBreak: true));
      }
    }
    return out;
  }

  /// Maps the engine's sub-protocol index onto the segment list, which has a
  /// break interleaved after every stage but the last.
  int _plusRingActiveIndex({
    required int sequenceLength,
    required int plusIndex,
    required bool onBreak,
  }) {
    if (sequenceLength < 2) return -1;
    final stage = plusIndex.clamp(0, sequenceLength - 1);
    // Stage k sits at segment 2k; the break that follows it at 2k + 1.
    return onBreak ? stage * 2 + 1 : stage * 2;
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
    List<int> plusDurations = const [],
    String plusName = '',
    int plusIndex = 0,
    int plusDelaySeconds = 0,
    bool plusOnBreak = false,
    int plusBreakRemaining = 0,
    // Horizontal pager gives each card a fixed height, so its content scrolls
    // within (true). In the vertical list the outer ListView scrolls, so the
    // card must size to its content instead (false).
    bool scrollable = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? pal.card : Colors.white;

    // Live telemetry (deviceâ†’app) takes precedence over the cycle-derived pad
    // colors when present â€” the firmware's actual thermode state is authoritative.
    final effectiveMoonColor = (telemetry?.moon != null)
        ? _webMoonPadColor(telemetry!.moon)
        : moonColor;
    final effectiveSunColor = (telemetry?.sun != null)
        ? _webSunPadColor(telemetry!.sun)
        : sunColor;
    final isFault = telemetry?.isFault ?? false;
    final isWarning = telemetry?.isWarning ?? false;

    // Backend timer is the single source of truth (matches the web): the web
    // renders the feed's per-device remainingSeconds/totalSeconds verbatim and
    // has no special Protocol Plus path. The backend now runs ONE continuous
    // whole-sequence clock for Plus too â€” deviceStartTime is set once at session
    // start and is no longer reset on a sub-protocol switch â€” so its
    // `remainingSeconds` is already a smooth, monotonic countdown over the entire
    // sequence (the old "timer restarts on each switch" bug is fixed server-side).
    // So trust the backend for Plus devices as well; fall back to the local
    // engine timer only until the first backend value arrives. The break banner /
    // sequence tracker continue to use the local engine state.
    //
    // EXCEPT once this device is terminal locally. The feed is polled once a
    // second and the server takes a moment to close the run, so a device the
    // user just stopped on the hardware would otherwise keep counting down for
    // another beat or two after the app already knows it stopped.
    final deviceTerminal = status == SessionStatus.stopped ||
        status == SessionStatus.completed;
    final useBackendTimer = !deviceTerminal &&
        backendRemainingSeconds != null &&
        backendRemainingSeconds >= 0;
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
                  : pal.line2,
          width: isFault ? 2 : 1,
        ),
      ),
      // In the pager each card has a fixed height, so make its content scroll
      // within (Plus devices add a progress card, and small screens may not fit
      // the ring + status + controls). In the vertical list the page scrolls, so
      // the card sizes to its content instead.
      child: _maybeScroll(
        scrollable: scrollable,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pal.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            // FAULT card (red) / WARNING banner (orange) â€” deviceâ†’app telemetry,
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
                durations: plusDurations,
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
                  color: pal.ink2,
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
                          color: pal.copperInk.withValues(alpha: 0.10),
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
                    active: status == SessionStatus.running,
                    trackColor: pal.line,
                    accentColor: pal.copperInk,
                    segments: _plusRingSegments(
                      plusSequence: plusSequence,
                      plusDurations: plusDurations,
                      breakSeconds: plusDelaySeconds,
                    ),
                    activeIndex: _plusRingActiveIndex(
                      sequenceLength: plusSequence.length,
                      plusIndex: plusIndex,
                      onBreak: plusOnBreak,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayRemaining.formatted,
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            color: pal.ink,
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
                  color: pal.ink3,
                  fontSize: 12,
                ),
              ),
            ],
            // Live sensor readouts (temperature/voltage/current/â€¦) when the
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
    final softSurface = isDark ? pal.card2 : Colors.white;

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
    // A foreign BLE device can't be reached over the WiFi broker (no server-side
    // macAddress, no local bond), so per-device control routes through the
    // backend BY REGISTERED NAME â€” taken from the live feed, NOT the raw
    // bluetooth id. WiFi remote keeps using the broker.
    final isBleRemote = remote && widget.transport != 'wifi';
    active_session.LiveDeviceState? feedDev;
    if (remote) {
      for (final d in remoteSession!.liveDevices) {
        if (d.deviceId == deviceId) {
          feedDev = d;
          break;
        }
      }
    }
    final wifiRemote =
        (remote && !isBleRemote) ? ref.read(wifiRemoteControlProvider) : null;
    final sync = ref.read(sessionSyncServiceProvider);
    final backendId = widget.backendSessionId ?? '';

    void pauseFn() {
      if (!remote) {
        ctrl.pauseDevice(deviceId);
      } else if (isBleRemote) {
        unawaited(sync.pauseServerSessionDeviceByIdentity(backendId, deviceId,
            deviceName: feedDev?.deviceName, slotId: feedDev?.slotId));
      } else {
        wifiRemote!.pauseDevice(remoteSession!, deviceId);
      }
    }

    void resumeFn() {
      if (!remote) {
        ctrl.resumeDevice(deviceId);
      } else if (isBleRemote) {
        unawaited(sync.resumeServerSessionDeviceByIdentity(backendId, deviceId,
            deviceName: feedDev?.deviceName, slotId: feedDev?.slotId));
      } else {
        wifiRemote!.resumeDevice(remoteSession!, deviceId);
      }
    }

    void stopFn() {
      if (!remote) {
        ctrl.stopDevice(deviceId);
      } else if (isBleRemote) {
        unawaited(sync.stopServerSessionDeviceByIdentity(backendId, deviceId,
            deviceName: feedDev?.deviceName, slotId: feedDev?.slotId));
      } else {
        wifiRemote!.stopDevice(remoteSession!, deviceId);
      }
    }

    // While an OWN BLE device's link is down during a live run, its commands
    // can't reach it â€” keep the buttons visible but DISABLED (greyed); reconnect
    // happens silently. This gate is irrelevant for a REMOTE/foreign view (we
    // drive the backend, not a local BLE link) and for WiFi (commands go over
    // MQTT), so it applies only to an own BLE run.
    final isLive =
        status == SessionStatus.running || status == SessionStatus.paused;
    final disconnected = !remote &&
        widget.transport == 'ble' &&
        isLive &&
        ref.watch(bleDeviceStatusProvider(deviceId)) !=
            BleConnectionStatus.connected;

    // Protocol Plus runs on a server-scheduled timeline; pausing/resuming would
    // desync the scheduled protocol switches, so only Stop is offered. Normal
    // protocol devices (incl. those in a mixed session) keep pause/resume.
    if (isProtocolPlusDevice &&
        (status == SessionStatus.running || status == SessionStatus.paused)) {
      // During a break the firmware is idle and the BLE link is expected to be
      // down â€” that's NOT a reason to block Stop. Stopping then just cancels the
      // server-scheduled remaining protocols (no live link needed), so keep the
      // button enabled even while disconnected mid-break.
      final blockStop = disconnected && !plusOnBreak;
      return SizedBox(
        height: 44,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: blockStop ? null : stopFn,
          style: ElevatedButton.styleFrom(
            backgroundColor: pal.low,
            foregroundColor: pal.ink,
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
                  foregroundColor: pal.ink,
                  side: BorderSide(color: pal.line2),
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
                  backgroundColor: pal.low,
                  foregroundColor: pal.ink,
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
                  backgroundColor: pal.copperInk,
                  foregroundColor: pal.ink,
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
                  backgroundColor: pal.low,
                  foregroundColor: pal.ink,
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
  /// Session-wide control card shown at the TOP of a live session: a device
  /// summary + Pause All / Resume All (toggles on status) + Stop All. Works for
  /// both local runs (drives the engine, whose state listener syncs pause/
  /// resume/stop to the backend so the web + other devices reflect it) and the
  /// web-synced remote view (routes through the cloud broker). [deviceCount] is
  /// the number of devices currently shown.
  Widget _buildTopControlCard(
    SessionStatus status,
    SessionEngine ctrl,
    List<active_session.ActiveSession> liveSessions,
    int deviceCount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? pal.card : Colors.white;
    final paused = status == SessionStatus.paused;
    final isWifi = widget.transport == 'wifi';
    // Pause/Resume only makes sense while the run is still live; once it has
    // completed/stopped the session can only be cleared via Stop All.
    final canPause =
        status == SessionStatus.running || status == SessionStatus.paused;

    // Remote (web-started) sessions route through the cloud broker; resolve the
    // live session to act on. If it's gone from the feed, hide the controls.
    active_session.ActiveSession? remoteSession;
    if (widget.remoteView) {
      for (final x in liveSessions) {
        if (x.id == widget.backendSessionId) {
          remoteSession = x;
          break;
        }
      }
      if (remoteSession == null) return const SizedBox.shrink();
    }
    // A foreign BLE session can't be reached over the WiFi broker (we aren't
    // bonded to its pads), so drive the backend session state directly: the
    // web + other clients reconcile, and on Stop All the backend drops the
    // session from the live feed (clearing the card). WiFi remote keeps using
    // the broker, which also writes the backend state.
    final isBleRemote = widget.remoteView && !isWifi;
    final wifiRemote = (widget.remoteView && isWifi)
        ? ref.read(wifiRemoteControlProvider)
        : null;
    final sync = ref.read(sessionSyncServiceProvider);
    final backendId = widget.backendSessionId;

    void onPauseResume() {
      if (!widget.remoteView) {
        if (paused) {
          ctrl.resume();
        } else {
          ctrl.pause();
        }
        return;
      }
      if (isBleRemote) {
        if (backendId == null) return;
        unawaited(paused
            ? sync.resumeServerSession(backendId)
            : sync.pauseServerSession(backendId));
      } else if (paused) {
        wifiRemote!.resume(remoteSession!);
      } else {
        wifiRemote!.pause(remoteSession!);
      }
    }

    Future<void> onStopAll() async {
      if (!widget.remoteView) {
        ctrl.stop();
        // Web parity: the post-session questions appear on the explicit Stop
        // All (client sessions only â€” the enqueue no-ops for guests).
        ctrl.enqueuePendingOutcome();
        await _promptSessionOutcomes();
        return;
      }
      if (isBleRemote) {
        if (backendId != null) unawaited(sync.stopServerSession(backendId));
      } else {
        wifiRemote!.stop(remoteSession!);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isWifi ? Icons.wifi_rounded : Icons.bluetooth_rounded,
                size: 18,
                color: pal.copperInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$deviceCount ${isWifi ? 'WiFi' : 'Bluetooth'} '
                  'device${deviceCount == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: pal.ink,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: canPause ? onPauseResume : null,
                    icon: Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(paused ? 'Resume All' : 'Pause All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pal.copperInk,
                      foregroundColor: pal.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: onStopAll,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pal.low,
                      foregroundColor: pal.ink,
                    ),
                  ),
                ),
              ),
            ],
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
                    widget.transport == 'wifi' ? 'Startingâ€¦' : 'Start Session'),
          ),
        ),
      SessionStatus.running => const SizedBox.shrink(),
      SessionStatus.paused => const SizedBox.shrink(),
      SessionStatus.stopped || SessionStatus.completed => SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
              onPressed: () async {
                // Ask the post-session questions before leaving, if not already
                // handled by the auto-prompt (idempotent).
                if (!widget.remoteView) {
                  ref
                      .read(sessionEngineFamilyProvider(_engineKey).notifier)
                      .enqueuePendingOutcome();
                  await _promptSessionOutcomes();
                }
                await _removeTrackedSessionIfAny();
                ctrl.reset();
                if (!mounted) return;
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: pal.good),
              child: Text('Done'))),
    };
  }

  Color _statusColor(SessionStatus s) => switch (s) {
        SessionStatus.idle => pal.ink3,
        SessionStatus.running => pal.good,
        SessionStatus.paused => pal.mid,
        SessionStatus.stopped => pal.low,
        SessionStatus.completed => pal.good,
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

  /// Same rules as web `DeviceTimer` Moon icon (left pad = p1). Accepts both the
  /// backend vocabulary ('hot'/'cold'/'leftHotRed'/'leftColdBlue') and the BLE
  /// frame's LED color ('red'/'blue', from p1.l) so live telemetry colors match.
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

  /// Same rules as web `DeviceTimer` Sun icon (right pad = p2). Accepts
  /// 'red'/'blue' (from p2.l) in addition to the backend 'hot'/'cold' vocabulary.
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

/// One arc of the session ring â€” a protocol stage or the break between two.
class _RingSegment {
  final double seconds;
  final bool isBreak;
  const _RingSegment(this.seconds, {this.isBreak = false});
}

/// Break colour, matching the UI handoff's `BREAK_COL` (app.js:1274).
const Color _kBreakColor = Color(0xFF4E7A8A);

/// The session progress ring.
///
/// Plain protocols get a single arc, as before. A Protocol Plus run gets the UI
/// handoff's SEGMENTED ring (`liveRingSVG`, app.js:1290): one arc per
/// sub-protocol AND one per break, sized by their real durations, so the shape
/// of the whole sequence is visible at a glance.
///
/// Segment durations come from the engine's own `plusDurations` /
/// `plusDelaySeconds` â€” never from a locally recomputed timeline like the spec's
/// `stackTimeline()`. The spec invents durations because it has no engine; we
/// have one, and a ring that disagreed with the device would be worse than no
/// ring.
///
/// Completed stages render filled, the current stage at full strength, and
/// upcoming stages as track only. The active arc is deliberately NOT partially
/// filled: per-stage elapsed time isn't exposed here, and the continuous
/// countdown plus the bar beneath the ring already carry that. Faking it would
/// mean drawing a position the device never reported.
class _TimerRing extends CustomPainter {
  final double progress;
  final bool active;

  /// Empty for a plain protocol â†’ a single continuous arc.
  final List<_RingSegment> segments;

  /// Index into [segments] of the stage running now; -1 when unknown.
  final int activeIndex;

  /// Passed in rather than read from a palette: a `CustomPainter` has no
  /// `BuildContext`, so it can't resolve the theme itself.
  final Color trackColor;
  final Color accentColor;

  _TimerRing({
    required this.progress,
    required this.active,
    required this.trackColor,
    required this.accentColor,
    this.segments = const [],
    this.activeIndex = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    if (segments.length < 2) {
      canvas.drawCircle(center, radius, stroke(trackColor));
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * progress.clamp(0.0, 1.0),
        false,
        stroke(accentColor),
      );
      return;
    }

    final total = segments.fold<double>(0, (a, s) => a + s.seconds);
    if (total <= 0) return;

    // A small gap between arcs so adjacent stages read as separate.
    const gapFraction = 0.012;
    var startFraction = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final span = seg.seconds / total;
      final sweep = (span - gapFraction).clamp(0.002, 1.0) * 2 * pi;
      final from = -pi / 2 + startFraction * 2 * pi;
      startFraction += span;

      final fill = seg.isBreak ? _kBreakColor : accentColor;
      if (activeIndex >= 0 && i < activeIndex) {
        // Done â€” filled, but dimmed so the current stage stands out.
        canvas.drawArc(
            rect, from, sweep, false, stroke(fill.withValues(alpha: 0.55)));
      } else if (i == activeIndex) {
        canvas.drawArc(rect, from, sweep, false, stroke(fill));
      } else {
        canvas.drawArc(
          rect,
          from,
          sweep,
          false,
          stroke(seg.isBreak
              ? _kBreakColor.withValues(alpha: 0.28)
              : trackColor),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimerRing old) =>
      progress != old.progress ||
      activeIndex != old.activeIndex ||
      segments.length != old.segments.length;
}
