import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/mqtt_publish_client.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../ble/services/ble_connector.dart';
import '../../advanced_settings/domain/advanced_settings_model.dart';
import '../../protocols/domain/protocol_model.dart';
import 'background_session_runtime.dart';
import '../data/session_repository.dart';
import '../domain/session_model.dart';

/// Provider family that creates a separate SessionEngine instance for each session
/// This allows true concurrent sessions without sharing state
final sessionEngineFamilyProvider =
    StateNotifierProvider.family<SessionEngine, SessionEngineState, String>(
        (ref, sessionId) {
  return SessionEngine(ref, sessionId: sessionId);
});

class SessionEngineState {
  final SessionStatus status;
  final TimerState timer;
  final Protocol? protocol;
  final Map<String, Protocol> protocolByDevice;
  final List<String> deviceIds;
  final SessionTransport transport;
  final bool wifiConfigAlreadyPublished;
  final AdvancedSettings advancedSettings;
  final Map<String, AdvancedSettings> advancedSettingsByDevice;
  final Map<String, TimerState> deviceTimers;
  final Map<String, SessionStatus> deviceStatuses;
  final String? delayedDeviceId;

  /// Protocol Plus template name (the sequence's own title), the ordered
  /// sub-protocol names, and the index of the one currently running. Empty
  /// sequence = not a Protocol Plus session. Drives the sequence tracker in the
  /// live session screen.
  final String protocolPlusName;
  final List<String> protocolPlusSequence;
  final int protocolPlusIndex;

  /// Per-device Protocol Plus tracker state for mixed / multi-Plus sessions.
  /// A device id present in [protocolPlusSequenceByDevice] is a Plus device and
  /// gets its own progress card; absent ids are normal protocols.
  final Map<String, String> protocolPlusNameByDevice;
  final Map<String, List<String>> protocolPlusSequenceByDevice;
  final Map<String, int> protocolPlusIndexByDevice;

  final String? error;

  const SessionEngineState({
    this.status = SessionStatus.idle,
    this.timer = const TimerState(),
    this.protocol,
    this.protocolByDevice = const {},
    this.deviceIds = const [],
    this.transport = SessionTransport.ble,
    this.wifiConfigAlreadyPublished = false,
    this.advancedSettings = const AdvancedSettings(),
    this.advancedSettingsByDevice = const {},
    this.deviceTimers = const {},
    this.deviceStatuses = const {},
    this.delayedDeviceId,
    this.protocolPlusName = '',
    this.protocolPlusSequence = const [],
    this.protocolPlusIndex = 0,
    this.protocolPlusNameByDevice = const {},
    this.protocolPlusSequenceByDevice = const {},
    this.protocolPlusIndexByDevice = const {},
    this.error,
  });

  SessionEngineState copyWith({
    SessionStatus? status,
    TimerState? timer,
    Protocol? protocol,
    Map<String, Protocol>? protocolByDevice,
    List<String>? deviceIds,
    SessionTransport? transport,
    bool? wifiConfigAlreadyPublished,
    AdvancedSettings? advancedSettings,
    Map<String, AdvancedSettings>? advancedSettingsByDevice,
    Map<String, TimerState>? deviceTimers,
    Map<String, SessionStatus>? deviceStatuses,
    String? delayedDeviceId,
    String? protocolPlusName,
    List<String>? protocolPlusSequence,
    int? protocolPlusIndex,
    Map<String, String>? protocolPlusNameByDevice,
    Map<String, List<String>>? protocolPlusSequenceByDevice,
    Map<String, int>? protocolPlusIndexByDevice,
    String? error,
  }) {
    return SessionEngineState(
      status: status ?? this.status,
      timer: timer ?? this.timer,
      protocol: protocol ?? this.protocol,
      protocolByDevice: protocolByDevice ?? this.protocolByDevice,
      deviceIds: deviceIds ?? this.deviceIds,
      transport: transport ?? this.transport,
      wifiConfigAlreadyPublished:
          wifiConfigAlreadyPublished ?? this.wifiConfigAlreadyPublished,
      advancedSettings: advancedSettings ?? this.advancedSettings,
      advancedSettingsByDevice:
          advancedSettingsByDevice ?? this.advancedSettingsByDevice,
      deviceTimers: deviceTimers ?? this.deviceTimers,
      deviceStatuses: deviceStatuses ?? this.deviceStatuses,
      delayedDeviceId: delayedDeviceId ?? this.delayedDeviceId,
      protocolPlusName: protocolPlusName ?? this.protocolPlusName,
      protocolPlusSequence: protocolPlusSequence ?? this.protocolPlusSequence,
      protocolPlusIndex: protocolPlusIndex ?? this.protocolPlusIndex,
      protocolPlusNameByDevice:
          protocolPlusNameByDevice ?? this.protocolPlusNameByDevice,
      protocolPlusSequenceByDevice:
          protocolPlusSequenceByDevice ?? this.protocolPlusSequenceByDevice,
      protocolPlusIndexByDevice:
          protocolPlusIndexByDevice ?? this.protocolPlusIndexByDevice,
      error: error,
    );
  }
}

class SessionEngine extends StateNotifier<SessionEngineState> {
  final Ref _ref;
  final String sessionId;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _sessionClockOffset = Duration.zero;
  DateTime? _firstBlePlayAnchor;
  bool _startInProgress = false;
  final Map<String, Stopwatch> _deviceStopwatches = {};

  /// Wall-clock anchors for suspend-proof timing. The Dart [Stopwatch] uses a
  /// monotonic clock that does NOT advance while the device is in deep sleep,
  /// and the periodic UI ticker is frozen while the app is backgrounded / the
  /// screen is off. We record a wall-clock anchor whenever the run (re)starts so
  /// [_reconcileClockFromWall] can detect and add back any elapsed wall time the
  /// monotonic clock missed, keeping the displayed timer aligned with the device.
  DateTime? _wallClockAnchor;
  Duration _monotonicAnchor = Duration.zero;

  /// Per-device catch-up added to each device [Stopwatch] to cover sleep time
  /// the monotonic clock didn't count. Keyed by device id.
  final Map<String, Duration> _deviceClockOffset = {};
  int _cycleIndex = 0;
  int _repetition = 0;
  bool _isActive = true; // Guard against state updates after disposal
  bool _historyCaptured = false; // Save session to history only once on start

  /// True for a server-driven Protocol Plus run. While true, the engine must
  /// NOT auto-STOP a device or mark it "completed" when a single protocol's
  /// duration elapses — the firmware finishes that protocol on its own and the
  /// next one arrives via START_PROTOCOL. Sending STOP here would kill the
  /// device mid-sequence (timer keeps running, device goes dark).
  bool _isProtocolPlus = false;

  /// Device ids running a server-driven Protocol Plus sequence. In a mixed
  /// session (some Plus, some normal) only these devices skip the auto-STOP /
  /// "completed" transition when a single protocol's duration elapses.
  final Set<String> _protocolPlusDeviceIds = <String>{};

  Future<void> _stateUpdateQueue = Future.value();
  static const int _blePauseByte = 0x02;
  static const int _bleResumeByte = 0x04;
  static const int _bleStopByte = 0x03;
  static const String _debugLightProtocolId = 'light-on';

  SessionEngine(this._ref, {required this.sessionId})
      : super(const SessionEngineState());

  /// Public, read-only view of the session transport (the underlying [state] is
  /// protected on StateNotifier). Used by [ProtocolPlusController] to decide
  /// whether a held switch is gated on a BLE link.
  SessionTransport get transport => state.transport;

  Future<void> _enqueueStateUpdate(void Function() fn) {
    _stateUpdateQueue = _stateUpdateQueue.then((_) async {
      if (!_isActive) return;
      fn();
    });
    return _stateUpdateQueue;
  }

  /// Adds [DateTime.now() - anchor] to the running timer so UI matches hardware
  /// when navigation / setup finishes after the device already started.
  void applySessionClockOffsetFromWallAnchor(DateTime anchor) {
    if (!_isActive) return;
    final lag = DateTime.now().difference(anchor);
    _sessionClockOffset = lag.isNegative ? Duration.zero : lag;
    appLogger.i(
      'Session: clock offset $_sessionClockOffset from wall anchor $anchor',
    );
  }

  Duration get _effectiveElapsed => _stopwatch.elapsed + _sessionClockOffset;

  /// Record where the wall clock and the monotonic stopwatch are right now, so
  /// [_reconcileClockFromWall] can measure any divergence later. Called whenever
  /// the run (re)starts ticking.
  void _anchorWallClock() {
    _wallClockAnchor = DateTime.now();
    _monotonicAnchor = _stopwatch.elapsed;
  }

  /// Add back any wall-clock time the monotonic [Stopwatch] missed while the
  /// device was asleep, then re-anchor. Safe to call every tick: while awake
  /// both clocks advance together so the drift is ~0 and this is a no-op. The
  /// drift only grows across a suspend (screen off / app backgrounded), where it
  /// captures exactly the sleep duration and folds it into the session + per-
  /// device offsets so the displayed timer catches up to the running device.
  void _reconcileClockFromWall() {
    if (!_isActive || state.status != SessionStatus.running) return;
    final anchor = _wallClockAnchor;
    if (anchor == null) return;
    final wallElapsed = DateTime.now().difference(anchor);
    final monotonicElapsed = _stopwatch.elapsed - _monotonicAnchor;
    final drift = wallElapsed - monotonicElapsed;
    // Ignore sub-second jitter (and any backwards wall-clock adjustment).
    if (drift <= const Duration(milliseconds: 500)) return;
    _sessionClockOffset += drift;
    for (final id in state.deviceIds) {
      if (state.deviceStatuses[id] == SessionStatus.running) {
        _deviceClockOffset[id] =
            (_deviceClockOffset[id] ?? Duration.zero) + drift;
      }
    }
    _anchorWallClock();
    appLogger.i('Session: reconciled +$drift of missed sleep time after wake');
  }

  /// Call when the app returns to the foreground. The periodic UI ticker is
  /// suspended while the app is backgrounded / the screen is off, and the
  /// monotonic clock skips deep-sleep time — so the displayed timer can be stale
  /// or behind the device. Reconcile against the wall clock and restart the
  /// ticker so the UI jumps straight to the device's true position.
  void onAppResumed() {
    if (!_isActive || state.status != SessionStatus.running) return;
    _reconcileClockFromWall();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    _syncDisplayedTimerFromStopwatch();
  }

  Future<bool> _sendLargePayload(
    String mac,
    String payloadFrame,
  ) async {
    final connector = _ref.read(bleConnectorProvider);

    return await connector.writeJsonToDevice(
      mac,
      utf8.encode(payloadFrame),
    );
  }

  Future<bool> _sendPlayCommand(String mac) async {
    final connector = _ref.read(bleConnectorProvider);
    final ok = await connector.writeToDevice(mac, [0x01]);
    appLogger.i('Session: BLE raw PLAY attempt 1/1 for $mac → $ok');
    return ok;
  }

  Future<void> _publishWifiPlayCmd(int playCmd) async {
    final deviceIds = state.deviceIds;
    if (deviceIds.isEmpty) return;
    try {
      final dio = _ref.read(djangoDioProvider);
      for (final mac in deviceIds) {
        final payloadStr = jsonEncode({'mac': mac, 'playCmd': playCmd});
        appLogger.i(
          'WiFi: Publishing playCmd=$playCmd (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
        );
        await postMqttPublishRequest(
          dio,
          data: {
            'topic': 'HydraWav3Pro/config',
            'payload': payloadStr,
          },
        );
      }
    } on DioException catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed '
        '(cmd=$playCmd, status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
      );
    } catch (e) {
      appLogger.e('WiFi: playCmd publish failed (cmd=$playCmd): $e');
    }
  }

  Future<void> _publishWifiPlayCmdToMac(String mac, int playCmd) async {
    if (mac.isEmpty) return;
    try {
      final dio = _ref.read(djangoDioProvider);
      final payloadStr = jsonEncode({'mac': mac, 'playCmd': playCmd});
      appLogger.i(
        'WiFi: Publishing playCmd=$playCmd (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
      );
      await postMqttPublishRequest(
        dio,
        data: {
          'topic': 'HydraWav3Pro/config',
          'payload': payloadStr,
        },
      );
    } on DioException catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed (cmd=$playCmd, mac=$mac, status=${e.response?.statusCode}, message=${e.message})',
      );
    } catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed (cmd=$playCmd, mac=$mac): $e',
      );
    }
  }

  /// Set transport/devices before protocol loads.
  /// This prevents accidental BLE-start attempts while protocol is still loading.
  void prepareSession({
    required List<String> deviceIds,
    required SessionTransport transport,
  }) {
    if (!_isActive) return;
    final selectedDeviceIds = List<String>.from(deviceIds);
    state = state.copyWith(
      deviceIds: selectedDeviceIds,
      transport: transport,
    );
    appLogger.i(
      'Session: prepareSession(transport=$transport, deviceIds=$selectedDeviceIds)',
    );
  }

  void loadSession(
    Protocol protocol,
    List<String> deviceIds, {
    SessionTransport transport = SessionTransport.ble,
    AdvancedSettings advancedSettings = const AdvancedSettings(),
    Map<String, AdvancedSettings>? advancedSettingsByDevice,
    Map<String, Protocol>? protocolByDevice,
    bool wifiConfigAlreadyPublished = false,
    String? delayedDeviceId,
  }) {
    if (!_isActive) return; // Guard against updates after disposal

    appLogger.i('═══════════════════════════════════════════════════');
    appLogger.i('Session: loadSession()');
    appLogger.i('  Protocol: ${protocol.templateName} (id=${protocol.id})');
    appLogger.i('  Transport: $transport');
    appLogger.i('  Devices: $deviceIds');
    appLogger.i('  Cycles: ${protocol.cycles.length}');
    final settingsByDevice = <String, AdvancedSettings>{
      for (final id in deviceIds)
        id: advancedSettingsByDevice?[id] ?? advancedSettings,
    };

    if (protocolByDevice == null) {
      state = state.copyWith(
        status: SessionStatus.stopped,
        error: 'No protocol selected per device (protocolByDevice missing).',
      );
      return;
    }

    final resolvedProtocolByDevice = <String, Protocol>{};
    for (final id in deviceIds) {
      final proto = protocolByDevice[id];
      if (proto == null) {
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'No protocol selected for device: $id',
        );
        return;
      }
      resolvedProtocolByDevice[id] = proto;
    }
    final selectedDeviceIds = List<String>.from(deviceIds);
    final computedTotalDurationSeconds = selectedDeviceIds.isEmpty
        ? _computeEffectiveTotalDurationSeconds(
            protocol,
            advancedSettings,
            applyStartDelay: false,
          )
        : selectedDeviceIds
            .map((id) {
              final deviceProtocol = resolvedProtocolByDevice[id]!;
              final deviceSettings = settingsByDevice[id] ?? advancedSettings;
              return _computeEffectiveTotalDurationSeconds(
                deviceProtocol,
                deviceSettings,
                applyStartDelay: _shouldApplyStartDelay(
                  transportId: id,
                  advancedSettings: deviceSettings,
                ),
              );
            })
            .reduce((a, b) => a > b ? a : b);
    appLogger
        .i('  Total Duration: ${computedTotalDurationSeconds}s (computed)');
    appLogger.i(
      '  Advanced: cycle1=${advancedSettings.cycle1Initiation}, '
      'cycle5=${advancedSettings.cycle5Completion}, '
      'led=${advancedSettings.lights}, '
      'vibrationMode=${advancedSettings.vibrationMode}, '
      'vibMin=${advancedSettings.vibMin}, vibMax=${advancedSettings.vibMax}, '
      'sweepMin=${advancedSettings.vibrationSweepMin}, '
      'sweepMax=${advancedSettings.vibrationSweepMax}, '
      'singleHz=${advancedSettings.vibrationSingleHz}, '
      'flip=${advancedSettings.flipSettings}',
    );
    appLogger.i('═══════════════════════════════════════════════════');

    final deviceTimers = <String, TimerState>{
      for (final id in selectedDeviceIds)
        id: TimerState(
          totalDuration: Duration(
            seconds: _computeEffectiveTotalDurationSeconds(
              resolvedProtocolByDevice[id]!,
              settingsByDevice[id] ?? advancedSettings,
              applyStartDelay: _shouldApplyStartDelay(
                transportId: id,
                advancedSettings: settingsByDevice[id] ?? advancedSettings,
              ),
            ),
          ),
          totalCycles: resolvedProtocolByDevice[id]!.cycles.length,
          lastVisualCycleIndex:
              resolvedProtocolByDevice[id]!.cycles.isNotEmpty ? 0 : -1,
        ),
    };
    final deviceStatuses = <String, SessionStatus>{
      for (final id in selectedDeviceIds) id: SessionStatus.idle,
    };

    try {
      state = SessionEngineState(
        status: SessionStatus.idle,
        protocol: protocol,
        protocolByDevice: resolvedProtocolByDevice,
        deviceIds: selectedDeviceIds,
        transport: transport,
        wifiConfigAlreadyPublished: wifiConfigAlreadyPublished,
        advancedSettings: advancedSettings,
        advancedSettingsByDevice: settingsByDevice,
        deviceTimers: deviceTimers,
        deviceStatuses: deviceStatuses,
        delayedDeviceId: delayedDeviceId,
        timer: TimerState(
          totalDuration: Duration(seconds: computedTotalDurationSeconds),
          totalCycles: protocol.cycles.length,
          lastVisualCycleIndex: protocol.cycles.isNotEmpty ? 0 : -1,
        ),
      );
    } catch (e) {
      appLogger
          .d('Session: loadSession state update ignored (notifier disposed)');
    }
    _cycleIndex = -1;
    _repetition = 0;
    _sessionClockOffset = Duration.zero;
    _firstBlePlayAnchor = null;
    _wallClockAnchor = null;
    _monotonicAnchor = Duration.zero;
    _deviceClockOffset.clear();
    _startInProgress = false;
    _deviceStopwatches
      ..clear()
      ..addEntries(selectedDeviceIds.map((e) => MapEntry(e, Stopwatch())));
  }

  Future<void> start() async {
    if (_startInProgress) {
      appLogger.w('⚠️ Ignoring start() — start sequence already in progress');
      return;
    }
    if (state.status != SessionStatus.idle) {
      appLogger.e("⛔ BLOCKED start() — status: ${state.status}");
      return;
    }
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status == SessionStatus.running ||
        state.status == SessionStatus.paused) {
      appLogger.w("⚠️ Ignoring start() — session already active");
      return;
    }

    appLogger.i(
      'Session: start() transport=${state.transport} deviceIds=${state.deviceIds}',
    );
    _startInProgress = true;

    try {
      if (state.protocol == null) {
        appLogger.w('Session: start() ignored — protocol not loaded yet');
        return;
      }

      // WiFi sessions: command is already sent via MQTT/API from the protocol
      // screen. We just run the timer UI.
      if (state.transport == SessionTransport.wifi) {
        if (!state.wifiConfigAlreadyPublished) {
          // Publish full RS35 session config per device, then start the timer UI.
          // This matches the web flow when starting directly from the session setup screen.
          try {
            final dio = _ref.read(djangoDioProvider);
            for (final mac in state.deviceIds) {
              final deviceProtocol = state.protocolByDevice[mac];
              if (deviceProtocol == null) {
                throw StateError('Missing protocol for device=$mac');
              }

              final payloadObj = _protocolToRs232Json(
                deviceProtocol,
                transportId: mac,
              );
              final payloadStr = jsonEncode(payloadObj);

              await postMqttPublishRequest(
                dio,
                data: {
                  'topic': 'HydraWav3Pro/config',
                  'payload': payloadStr,
                },
              );
            }
          } on DioException catch (e) {
            appLogger.e(
              'WiFi: config publish failed '
              '(status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
            );
            if (!_isActive) return;
            state = state.copyWith(
              status: SessionStatus.stopped,
              error: 'WiFi publish failed: ${e.message ?? e.toString()}',
            );
            return;
          } catch (e) {
            appLogger.e('WiFi: config publish failed: $e');
            if (!_isActive) return;
            state = state.copyWith(
              status: SessionStatus.stopped,
              error: 'WiFi publish failed: $e',
            );
            return;
          } finally {
            // If we published config ourselves, align UI to "now".
            _sessionClockOffset = Duration.zero;
          }
        }

        appLogger.i(
          'Session: Starting WiFi session timer (devices=${state.deviceIds.length})',
        );
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final id in state.deviceIds) {
          statuses[id] = SessionStatus.running;
          _deviceStopwatches[id]?.start();
        }
        state = state.copyWith(
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
        _beginRuntimeTimer();
        return;
      }

      final connector = _ref.read(bleConnectorProvider);
      final targetDeviceIds = state.deviceIds.isNotEmpty
          ? state.deviceIds
          : connector.connectedDeviceIds;

      if (targetDeviceIds.isEmpty) {
        if (!_isActive) return;
        state = state.copyWith(
          error: 'No BLE device selected/connected',
        );
        appLogger.w('Session: Start aborted — no target BLE devices');
        return;
      }

      // CRITICAL FIX: Verify all devices are actually connected before attempting payload send.
      // This fixes the issue where selected devices may have disconnected between device
      // selection and session start.
      final actuallyConnectedIds =
          targetDeviceIds.where((id) => connector.isConnected(id)).toList();

      if (actuallyConnectedIds.isEmpty) {
        if (!_isActive) return;

        state = state.copyWith(
          error: 'No BLE devices connected...',
        );
        return;
      }

      // Log warning if some selected devices disconnected
      final disconnectedIds =
          targetDeviceIds.where((id) => !connector.isConnected(id)).toList();
      if (disconnectedIds.isNotEmpty) {
        appLogger.w(
          'Session: Some selected devices disconnected, proceeding with connected devices only '
          '(disconnected=${disconnectedIds.join(", ")}, connected=${actuallyConnectedIds.join(", ")})',
        );
      }

      if (BleConstants.startSendsOnlyPlayCmd) {
        // This mode is only meant to "turn on" by sending a tiny command.
        // Cancel any previously running timer so we don't tick while
        // `state.protocol` is null (this was causing the crash you pasted).
        _timer?.cancel();
        _timer = null;
        _stopwatch.stop();
        _stopwatch.reset();

        final failed = <String>[];
        final playCmdJson = jsonEncode({'playCmd': 1});
        // Some firmwares only accept specific newline framing. We try a small
        // ordered set to find the exact terminator the device expects.
        final terminatorFrames = <String>[
          '$playCmdJson${BleConstants.sessionJsonLineSuffix}', // current suffix (likely '\n')
          '$playCmdJson\r\n',
          '$playCmdJson\n\n',
        ];

        appLogger.i(
          'Session: Sending playCmd-only (frame variants=$terminatorFrames) '
          'to ${actuallyConnectedIds.length} connected device(s)',
        );

        for (final mac in actuallyConnectedIds) {
          bool anyOk = false;
          for (final frame in terminatorFrames) {
            appLogger.i(
              "Session: playCmd-only sending to $mac frame='${frame.replaceAll('\n', '\\\\n').replaceAll('\r', '\\\\r')}' "
              '(${frame.length} bytes, utf8)',
            );
            final ok = await connector.writeToDevice(mac, utf8.encode(frame));
            anyOk = anyOk || ok;
            appLogger.i('Session: playCmd-only sent to $mac (variant) → $ok');
            // Tiny pause between variants; helps some UART-like bridges.
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!anyOk) failed.add(mac);
        }

        if (failed.isNotEmpty) {
          state = state.copyWith(
            error: 'Failed to send playCmd to: ${failed.join(', ')}',
          );
          appLogger.w('Session: playCmd-only failed');
          return;
        }

        // In playCmd-only mode, we don't run the protocol timer.
        if (!_isActive) return;
        state = state.copyWith(status: SessionStatus.stopped, error: null);
        return;
      }

      if (state.protocol == null) return;

      appLogger.i(
        'Session: start payload source '
        '(common protocolId=${state.protocol!.id}, name=${state.protocol!.templateName}, sessions=${state.protocol!.sessions}, cycles=${state.protocol!.cycles.length})',
      );

      // For BLE we intentionally start UI timer only AFTER PLAY succeeds,
      // so elapsed time tracks physical device runtime.
      appLogger
          .i('Session: Starting BLE send sequence (timer starts after PLAY)');

      // Send protocol JSON to all connected devices over BLE (RS232 bridge)
      // first, then do ONE common delay, then send PLAY to all devices together.
      // This matches the web start flow and avoids per-device timing skew.
      _firstBlePlayAnchor = null;

      final failed = <String>[];

      // STEP 1: payload to all devices (concurrently)
      final payloadResults = await Future.wait(
        actuallyConnectedIds.map((mac) async {
          final deviceProtocol = state.protocolByDevice[mac];
          if (deviceProtocol == null) {
            failed.add(mac);
            return MapEntry(mac, false);
          }

          final legacyShape = _protocolToRs232Json(
            deviceProtocol,
            transportId: mac,
          );

          if (deviceProtocol.cycles.isNotEmpty) {
            final c0 = deviceProtocol.cycles.first;
            appLogger.i(
              'Session: protocol first-cycle '
              '(dur=${c0.durationSeconds}, rep=${c0.repetitions}, hot=${c0.hotPwm}, cold=${c0.coldPwm}, left=${c0.leftFunction}, right=${c0.rightFunction})',
            );
          }

          final protocolFrame = jsonEncode(legacyShape);
          final escapedFrame =
              protocolFrame.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
          appLogger.i(
            'Session: BLE request (device=$mac, mac field=$mac): '
            '$escapedFrame',
          );

          appLogger.i(
            'Session: Sending protocol to $mac '
            '(mac key=$mac, ${protocolFrame.length} bytes, shape=web-rs35-flat)',
          );
          appLogger.i('📱 BLE Payload Details for $mac:');
          appLogger.i('   - cycles: ${deviceProtocol.cycles.length}');
          appLogger.i(
              '   - total duration: ${deviceProtocol.totalDurationSeconds}s');
          appLogger.i('   - payload size: ${protocolFrame.length} bytes');
          appLogger.i("🔥 CALLING BLE PAYLOAD NOW");

          final okProtocol = await _sendLargePayload(mac, protocolFrame);
          appLogger.i(
            "🔥 BLE PAYLOAD RESULT: okProtocol=$okProtocol for device=$mac",
          );

          return MapEntry(mac, okProtocol);
        }),
      );

      final payloadSucceeded = payloadResults
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toList();
      final payloadFailed = payloadResults
          .where((e) => e.value == false)
          .map((e) => e.key)
          .toList();

      failed.addAll(payloadFailed);
      if (failed.isNotEmpty) {
        // Abort start if any device never received config.
        _stopwatch.stop();
        _timer?.cancel();
        _timer = null;
        if (!_isActive) return;
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Failed to send protocol payload to: ${failed.join(', ')}',
        );
        return;
      }

      // STEP 2: one common delay (matches web)
      const prePlayDelay = Duration(milliseconds: 2500);
      await Future<void>.delayed(prePlayDelay);

      // STEP 3: PLAY to all devices together (concurrently)
      final commonPlayAnchor = DateTime.now();
      final playResults = await Future.wait(
        payloadSucceeded.map((mac) async {
          appLogger.i('Session: Sending raw PLAY command (0x01) to $mac');
          final okRawPlay = await _sendPlayCommand(mac);
          appLogger.i(
            'Session: BLE raw PLAY command result for $mac → $okRawPlay',
          );
          return MapEntry(mac, MapEntry(okRawPlay, commonPlayAnchor));
        }),
      );

      final playFailed = playResults
          .where((e) => (e.value.key) == false)
          .map((e) => e.key)
          .toList();
      failed.addAll(playFailed);

      if (failed.isNotEmpty) {
        _stopwatch.stop();
        _timer?.cancel();
        _timer = null;
        if (!_isActive) return;
        // Stop whatever did start.
        unawaited(_completeDevices(payloadSucceeded));
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Failed to send PLAY to: ${failed.join(', ')}',
        );
        return;
      }

      // STEP 4: start per-device timers/status after PLAY succeeds for all
      await _enqueueStateUpdate(() {
        final timers = Map<String, TimerState>.from(state.deviceTimers);
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final mac in payloadSucceeded) {
          _deviceStopwatches[mac]?.start();
          timers[mac] = (timers[mac] ?? const TimerState()).copyWith(
            isRunning: true,
          );
          statuses[mac] = SessionStatus.running;
          _firstBlePlayAnchor = commonPlayAnchor;
        }
        state = state.copyWith(
          deviceTimers: timers,
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
      });

      _beginRuntimeTimer();
    } finally {
      _startInProgress = false;
    }
  }

  /// Protocol Plus: switch [mac] to [newProtocol] mid-session when the server
  /// emits START_PROTOCOL. Re-sends the full config + PLAY over BLE, or
  /// publishes config via MQTT for WiFi — reusing the exact senders the normal
  /// run uses. Does NOT reset the session timer or disturb the normal flow.
  Future<bool> applyProtocolPlusSwitch(
    String mac,
    Protocol newProtocol,
    int protocolIndex,
  ) async {
    if (!_isActive) return false;
    appLogger.i(
      'ProtocolPlus: switching device=$mac to ${newProtocol.templateName} '
      '(index=$protocolIndex, transport=${state.transport})',
    );

    // Reflect the new protocol per-device + advance the sequence indicator so
    // the live session screen highlights the now-active protocol chip.
    final updatedByDevice = Map<String, Protocol>.from(state.protocolByDevice)
      ..[mac] = newProtocol;
    // Re-derive this device's advanced settings from the NEW protocol so the
    // switch payload uses that protocol's own cycle1/cycle5 (edge cycle) and
    // vibration range — not the previous protocol's. Otherwise every protocol
    // in the sequence inherits protocol[0]'s edge-cycle flags.
    final updatedSettingsByDevice =
        Map<String, AdvancedSettings>.from(state.advancedSettingsByDevice)
          ..[mac] = _advancedSettingsForProtocol(newProtocol);
    final updatedIndexByDevice =
        Map<String, int>.from(state.protocolPlusIndexByDevice)
          ..[mac] = protocolIndex;
    try {
      state = state.copyWith(
        protocolByDevice: updatedByDevice,
        advancedSettingsByDevice: updatedSettingsByDevice,
        protocolPlusIndex: protocolIndex,
        protocolPlusIndexByDevice: updatedIndexByDevice,
      );
    } catch (_) {}

    final payloadStr =
        jsonEncode(_protocolToRs232Json(newProtocol, transportId: mac));

    if (state.transport == SessionTransport.wifi) {
      try {
        await postMqttPublishRequest(
          _ref.read(djangoDioProvider),
          data: {
            'topic': 'HydraWav3Pro/config',
            'payload': payloadStr,
          },
        );
        appLogger.i('ProtocolPlus: WiFi config published for $mac');
        return true;
      } catch (e) {
        appLogger.e('ProtocolPlus: WiFi switch failed for $mac: $e');
        return false;
      }
    }

    // BLE: full config → settle delay → PLAY (same sequence as a fresh start).
    final connector = _ref.read(bleConnectorProvider);

    // The firmware physically stops when protocol[i-1] finishes and can drop
    // BLE during the gap before this switch. The connector auto-reconnects, so
    // wait briefly for it to come back instead of abandoning the switch.
    if (!connector.isConnected(mac)) {
      appLogger.w(
        'ProtocolPlus: BLE device $mac not connected — waiting for reconnect…',
      );
      const pollEvery = Duration(milliseconds: 500);
      const maxWait = Duration(seconds: 12);
      var waited = Duration.zero;
      while (waited < maxWait && !connector.isConnected(mac)) {
        await Future<void>.delayed(pollEvery);
        waited += pollEvery;
        if (!_isActive) return false;
      }
      if (!connector.isConnected(mac)) {
        appLogger.e(
          'ProtocolPlus: BLE device $mac still not connected after '
          '${maxWait.inSeconds}s — switch skipped',
        );
        return false;
      }
      appLogger.i('ProtocolPlus: BLE device $mac reconnected — switching now');
    }

    // STOP → reset → config → settle → PLAY, with one retry on failure.
    //
    // CRITICAL: a fresh start works because the device is IDLE when it receives
    // config+PLAY. At a Protocol Plus switch the device has just FINISHED
    // protocol[i-1] ("beep + stop") and is in a completed/BUSY state — if we
    // send config+PLAY in that state the firmware only half-accepts it (device
    // "runs a few parts then stops"). Sending STOP first forces the firmware
    // back to idle so the new config+PLAY behaves exactly like a clean start.
    for (var attempt = 1; attempt <= 2; attempt++) {
      // 1) Reset firmware to idle.
      final okStop = await connector.writeToDevice(mac, [_bleStopByte]);
      appLogger.i('ProtocolPlus: BLE pre-switch STOP for $mac → $okStop');
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 2) Push the new protocol config.
      final okPayload = await _sendLargePayload(mac, payloadStr);
      if (!okPayload) {
        appLogger.e(
          'ProtocolPlus: BLE config send failed for $mac (attempt $attempt)',
        );
        if (attempt == 2 || !connector.isConnected(mac)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }

      // 3) Settle, then PLAY (same timing as a fresh start).
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final okPlay = await _sendPlayCommand(mac);
      appLogger.i(
        'ProtocolPlus: BLE switch PLAY for $mac → $okPlay (attempt $attempt)',
      );
      if (okPlay) return true;
      if (attempt == 2) return false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  /// Protocol Plus: make the whole session span [seconds] (the protocol-plus
  /// totalDuration) so it does NOT complete when protocol[0] ends — later
  /// protocols (driven by START_PROTOCOL) keep counting toward this total.
  /// Call right after loadSession(), before start().
  /// Protocol Plus: store the sequence title + ordered sub-protocol names so
  /// the live session screen can render the tracker and highlight the active
  /// protocol.
  void setProtocolPlusSequence(String plusName, List<String> names) {
    if (!_isActive || names.isEmpty) return;
    _isProtocolPlus = true;
    state = state.copyWith(
      protocolPlusName: plusName,
      protocolPlusSequence: List<String>.from(names),
      protocolPlusIndex: 0,
    );
    appLogger.i('ProtocolPlus: "$plusName" sequence → ${names.join(" → ")}');
  }

  /// Per-device Protocol Plus sequences for mixed / multi-Plus sessions. Each
  /// Plus device gets its own tracker; normal devices are absent from these
  /// maps and render normal controls instead of a progress card.
  void setProtocolPlusSequencesByDevice(
    Map<String, String> nameByDevice,
    Map<String, List<String>> sequenceByDevice,
  ) {
    if (!_isActive || sequenceByDevice.isEmpty) return;
    _isProtocolPlus = true;
    state = state.copyWith(
      protocolPlusNameByDevice: Map<String, String>.from(nameByDevice),
      protocolPlusSequenceByDevice: {
        for (final e in sequenceByDevice.entries)
          e.key: List<String>.from(e.value),
      },
      protocolPlusIndexByDevice: {
        for (final id in sequenceByDevice.keys) id: 0,
      },
    );
    appLogger.i(
      'ProtocolPlus: per-device sequences set for ${sequenceByDevice.keys.join(", ")}',
    );
  }

  /// Mark which devices are running a server-driven Protocol Plus sequence so
  /// the tick loop doesn't auto-complete them when one protocol's time elapses.
  void setProtocolPlusDevices(Set<String> deviceIds) {
    if (!_isActive) return;
    _protocolPlusDeviceIds
      ..clear()
      ..addAll(deviceIds);
    if (deviceIds.isNotEmpty) _isProtocolPlus = true;
  }

  /// Override per-device total durations (each Protocol Plus has its own total
  /// length). The overall session timer tracks the longest device. Call after
  /// loadSession(), before start().
  void setDeviceTotalDurations(Map<String, int> secondsByDevice) {
    if (!_isActive || secondsByDevice.isEmpty) return;
    final devTimers = Map<String, TimerState>.from(state.deviceTimers);
    secondsByDevice.forEach((id, secs) {
      if (secs <= 0) return;
      final t = devTimers[id];
      if (t != null) {
        devTimers[id] = t.copyWith(totalDuration: Duration(seconds: secs));
      }
    });
    var maxDur = state.timer.totalDuration;
    for (final t in devTimers.values) {
      if (t.totalDuration > maxDur) maxDur = t.totalDuration;
    }
    state = state.copyWith(
      deviceTimers: devTimers,
      timer: state.timer.copyWith(totalDuration: maxDur),
    );
    appLogger.i(
      'Session: per-device durations set (${secondsByDevice.length} devices, '
      'overall=${maxDur.inSeconds}s)',
    );
  }

  void setSessionTotalDuration(int seconds) {
    if (!_isActive || seconds <= 0) return;
    // Only Protocol Plus extends the session beyond a single protocol, so this
    // is the reliable signal that we're in a server-driven sequence.
    _isProtocolPlus = true;
    final total = Duration(seconds: seconds);
    final devTimers = <String, TimerState>{
      for (final e in state.deviceTimers.entries)
        e.key: e.value.copyWith(totalDuration: total),
    };
    state = state.copyWith(
      timer: state.timer.copyWith(totalDuration: total),
      deviceTimers: devTimers,
    );
    appLogger.i('Session: total duration overridden to ${seconds}s (protocol+)');
  }

  void _beginRuntimeTimer() {
    appLogger.i(
      'Session: Runtime timer started (clockOffset=$_sessionClockOffset)',
    );
    if (!_isActive) return;
    try {
      state = state.copyWith(
        status: _deriveOverallStatus(state.deviceStatuses),
        error: null,
      );
    } catch (e) {
      appLogger
          .d('Session: timer start state update ignored (notifier disposed)');
      return;
    }
    final alreadyRunning = _stopwatch.isRunning;
    if (!alreadyRunning) {
      _stopwatch.reset();
      _stopwatch.start();
    }
    _anchorWallClock();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    // Periodic timer does not fire until the first interval; sync once now
    // so remaining time and cycle/pad UI match the device immediately.
    _syncDisplayedTimerFromStopwatch();
    unawaited(_syncBackgroundRuntime('running'));
    unawaited(_captureSessionHistoryOnce());
  }

  /// Persist this session to history exactly once, the moment it starts
  /// running — independent of any screen being open. The repository also
  /// dedupes by session id, so re-opening the live session never creates a
  /// duplicate intake.
  Future<void> _captureSessionHistoryOnce() async {
    if (_historyCaptured) return;
    if (state.protocol == null) return;
    _historyCaptured = true;
    try {
      final userId = _ref.read(authStateProvider).user?.id;
      final record = getSessionRecord(
        sessionId: sessionId,
        clientType: 'guest',
        createdBy: userId,
        updatedBy: userId,
        discomfortBefore: 6,
        discomfortAfter: 2,
        notes: 'Guest session started from mobile app',
      );
      if (record == null) {
        _historyCaptured = false;
        return;
      }
      await _ref.read(sessionRepositoryProvider).saveSession(record);
      appLogger.i('Session: history captured on start for $sessionId');
    } catch (e) {
      appLogger.e('Session: failed to capture history on start: $e');
    }
  }

  Future<void> _syncBackgroundRuntime(String status) async {
    if (!_isActive || state.protocol == null || state.deviceIds.isEmpty) return;
    final startedAtMs = _firstBlePlayAnchor?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    final snapshot = LiveSessionSnapshot(
      sessionId: sessionId,
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: List<String>.from(state.deviceIds),
      transport: state.transport == SessionTransport.wifi ? 'wifi' : 'ble',
      startedAtEpochMs: startedAtMs,
      delayedDeviceId: state.delayedDeviceId,
      protocolByDeviceId: {
        for (final entry in state.protocolByDevice.entries)
          entry.key: entry.value.id,
      },
      advancedSettings: state.advancedSettings,
      advancedSettingsByDevice:
          Map<String, AdvancedSettings>.from(state.advancedSettingsByDevice),
      fromBackgroundService: true,
    );

    final runtime = _ref.read(backgroundSessionRuntimeProvider.notifier);
    if (status == 'running') {
      await runtime.startService(snapshot);
    } else if (status == 'paused') {
      await runtime.pauseService(sessionId: sessionId);
    } else if (status == 'resumed') {
      await runtime.resumeService(sessionId: sessionId);
    } else if (status == 'stopped') {
      await runtime.stopService(sessionId: sessionId);
    } else {
      await runtime.cacheSnapshotOnly(snapshot);
    }
  }

  /// Advanced settings derived from a protocol's own fields. Keeps the
  /// edge-cycle flags (cycle1/cycle5) and vibration range in sync with the
  /// protocol so the firmware doesn't run an unexpected initiation cycle.
  /// Mirrors the derivation used when launching a Protocol Plus run.
  AdvancedSettings _advancedSettingsForProtocol(Protocol p) => AdvancedSettings(
        cycle1Initiation: p.cycle1,
        cycle5Completion: p.cycle5,
        vibrationSweepMin: p.vibmin,
        vibrationSweepMax: p.vibmax,
        vibMin: p.vibmin,
        vibMax: p.vibmax,
        hotDrop: p.hotdrop,
        coldDrop: p.colddrop,
      );

  Map<String, dynamic> _protocolToRs232Json(
    Protocol p, {
    required String transportId,
  }) {
    final advancedSettings =
        state.advancedSettingsByDevice[transportId] ?? state.advancedSettings;
    final applyDelay = _shouldApplyStartDelay(
      transportId: transportId,
      advancedSettings: advancedSettings,
    );
    return _protocolToRs35Payload(
      p,
      mac: transportId,
      advancedSettings: advancedSettings,
      applyStartDelay: applyDelay,
    );
  }

  Map<String, dynamic> _protocolToRs35Payload(
    Protocol p, {
    required String mac,
    required AdvancedSettings advancedSettings,
    required bool applyStartDelay,
  }) {
    final cycles = p.cycles;

    // Intensity mapping from web sender (0–11).
    const hotMap = <int, int>{
      0: 0,
      1: 50,
      2: 55,
      3: 60,
      4: 65,
      5: 70,
      6: 75,
      7: 80,
      8: 85,
      9: 90,
      10: 95,
      11: 100,
    };
    const coldMap = <int, int>{
      0: 0,
      1: 150,
      2: 160,
      3: 170,
      4: 180,
      5: 190,
      6: 200,
      7: 210,
      8: 220,
      9: 230,
      10: 240,
      11: 250,
    };

    List<String> leftFuncs = cycles.map((c) => c.leftFunction).toList();
    List<String> rightFuncs = cycles.map((c) => c.rightFunction).toList();

    if (advancedSettings.flipSettings) {
      String flip(String fn) {
        if (fn.contains('HotRed')) return fn.replaceAll('HotRed', 'ColdBlue');
        if (fn.contains('ColdBlue')) return fn.replaceAll('ColdBlue', 'HotRed');
        return fn;
      }

      leftFuncs = leftFuncs.map(flip).toList();
      rightFuncs = rightFuncs.map(flip).toList();
    }

    final hotPwm = hotMap[advancedSettings.hotLevel.clamp(0, 11)] ?? 70;
    final coldPwm = coldMap[advancedSettings.coldLevel.clamp(0, 11)] ?? 190;
    final pwmHot = advancedSettings.hotPack
        ? cycles.map((_) => hotPwm).toList()
        : cycles.map((c) => c.hotPwm.toInt()).toList();
    final pwmCold = advancedSettings.coldPack
        ? cycles.map((_) => coldPwm).toList()
        : cycles.map((c) => c.coldPwm.toInt()).toList();

    final vibMode = advancedSettings.vibrationMode;
    final vibMin = switch (vibMode) {
      'Off' => 0,
      'Single' => advancedSettings.vibrationSingleHz.clamp(10, 230).toInt(),
      'Sweep' => advancedSettings.vibrationSweepMin.toInt(),
      _ => advancedSettings.vibMin.toInt(),
    };
    final vibMax = switch (vibMode) {
      'Off' => 1,
      'Single' =>
        (advancedSettings.vibrationSingleHz.clamp(10, 230).toInt() + 10),
      'Sweep' => advancedSettings.vibrationSweepMax.toInt(),
      _ => advancedSettings.vibMax.toInt(),
    };
    final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
      p,
      advancedSettings,
    );
    final totalDuration = _computeEffectiveTotalDurationSeconds(
      p,
      advancedSettings,
      applyStartDelay: applyStartDelay,
    );

    return {
      'mac': mac,
      'sessionCount': p.sessions,
      'sessionPause': p.sessionPause.toInt(),
      'sDelay': applyStartDelay ? advancedSettings.startDelay : 0,
      'cycle1': advancedSettings.cycle1Initiation ? 1 : 0,
      'cycle5': advancedSettings.cycle5Completion ? 1 : 0,
      'edgeCycleDuration': edgeCycleDuration,
      'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
      'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
      'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
      'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
      'leftFuncs': leftFuncs,
      'rightFuncs': rightFuncs,
      'pwmValues': {
        'hot': pwmHot,
        'cold': pwmCold,
      },
      'playCmd': 1,
      'led': advancedSettings.lights ? 1 : 0,
      'hotDrop': advancedSettings.hotDrop.toInt(),
      'coldDrop': advancedSettings.coldDrop.toInt(),
      'vibMin': vibMin,
      'vibMax': vibMax,
      'totalDuration': totalDuration,
    };
  }

  int _computeFirmwareTotalDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings,
  ) {
    final cycles = p.cycles;
    if (cycles.length < 3) return p.totalDurationSeconds;

    // Match web calculateFirmwareTotalDuration behavior.
    final c2 = cycles[0];
    final c3 = cycles[1];
    final c4 = cycles[2];
    int baseTimeline = (c2.repetitions *
            ((c2.durationSeconds + c2.pauseSeconds).toInt())) +
        c2.cyclePause.toInt() +
        (c3.repetitions * ((c3.durationSeconds + c3.pauseSeconds).toInt())) +
        c3.cyclePause.toInt() +
        (c4.repetitions * ((c4.durationSeconds + c4.pauseSeconds).toInt()));

    if (p.sessions > 1) {
      baseTimeline = (baseTimeline * p.sessions) +
          (p.sessionPause.toInt() * (p.sessions - 1));
    }

    final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
      p,
      advancedSettings,
    );

    if (advancedSettings.cycle1Initiation) {
      baseTimeline += edgeCycleDuration + 30;
    }
    if (advancedSettings.cycle5Completion) {
      baseTimeline += edgeCycleDuration + 30;
    }

    return baseTimeline;
  }

  bool _shouldApplyStartDelay({
    required String transportId,
    required AdvancedSettings advancedSettings,
  }) {
    final selectedDelayedDeviceId = state.delayedDeviceId;
    final hasSelectedDelayedDevice = selectedDelayedDeviceId != null &&
        state.deviceIds.contains(selectedDelayedDeviceId);
    return advancedSettings.startDelay > 0 &&
        (!hasSelectedDelayedDevice || selectedDelayedDeviceId == transportId);
  }

  int _computeEffectiveTotalDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings, {
    required bool applyStartDelay,
  }) {
    final baseDuration = _computeFirmwareTotalDurationSeconds(
      p,
      advancedSettings,
    );
    return baseDuration + (applyStartDelay ? advancedSettings.startDelay : 0);
  }

  int _effectiveEdgeCycleDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings,
  ) {
    return (advancedSettings.cycle1Initiation ||
            advancedSettings.cycle5Completion)
        ? 9
        : p.edgecycleduration.toInt();
  }

  Future<void> pause() async {
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status != SessionStatus.running) return;

    appLogger.i('🔥 PAUSE: Sending pause command to device');
    if (state.transport == SessionTransport.wifi) {
      // WiFi pause command = playCmd=3
      await _publishWifiPlayCmd(3);
      appLogger.i('🔥 PAUSE: WiFi playCmd=3 sent');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE pause command to session devices only
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_blePauseByte]);
          appLogger.i('🔥 PAUSE: BLE 0x$_blePauseByte sent to $mac');
        }
      }
    }

    for (final id in state.deviceIds) {
      _deviceStopwatches[id]?.stop();
    }
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
    for (final id in state.deviceIds) {
      if (statuses[id] == SessionStatus.running)
        statuses[id] = SessionStatus.paused;
    }
    try {
      state = state.copyWith(
        deviceStatuses: statuses,
        status: _deriveOverallStatus(statuses),
      );
      appLogger.i('🔥 PAUSE: State updated to paused');
      unawaited(_syncBackgroundRuntime('paused'));
    } catch (e) {
      appLogger.d('Session: pause() state update ignored (notifier disposed)');
    }
  }

  Future<void> resume() async {
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status != SessionStatus.paused) return;

    appLogger.i('🔄 RESUME: Sending resume/continue command to device');
    try {
      state = state.copyWith(status: SessionStatus.running);
    } catch (e) {
      appLogger.d('Session: resume() state update ignored (notifier disposed)');
    }

    if (state.transport == SessionTransport.wifi) {
      // WiFi resume/continue command = playCmd=4
      // This continues the session from where it was paused
      await _publishWifiPlayCmd(4);
      appLogger.i('🔄 RESUME: WiFi playCmd=4 sent (continue from pause)');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE resume/continue command to session devices only
      // 0x04 = Resume/Continue (NOT 0x01 which is start)
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleResumeByte]);
          appLogger.i(
            '🔄 RESUME: BLE 0x$_bleResumeByte sent to $mac (continue from pause)',
          );
        }
      }
    }

    for (final id in state.deviceIds) {
      if (state.deviceStatuses[id] == SessionStatus.paused) {
        _deviceStopwatches[id]?.start();
      }
    }
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
    for (final id in state.deviceIds) {
      if (statuses[id] == SessionStatus.paused)
        statuses[id] = SessionStatus.running;
    }
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    _anchorWallClock();
    _syncDisplayedTimerFromStopwatch();
    appLogger.i('🔄 RESUME: Timer restarted on app side');
    unawaited(_syncBackgroundRuntime('resumed'));
  }

  Future<void> stop() async {
    // Send stop command to devices via transport-specific method
    appLogger.i('🛑 STOP: Sending stop command to device');
    if (state.transport == SessionTransport.wifi) {
      // WiFi stop command = playCmd=2
      await _publishWifiPlayCmd(2);
      appLogger.i('🛑 STOP: WiFi playCmd=2 sent');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE stop command to session devices only
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleStopByte]);
          appLogger.i('🛑 STOP: BLE 0x$_bleStopByte sent to $mac');
        }
      }
    }

    _stopwatch.stop();
    _timer?.cancel();
    for (final id in state.deviceIds) {
      _deviceStopwatches[id]?.stop();
    }
    if (!_isActive) return;
    try {
      final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
      for (final id in state.deviceIds) {
        statuses[id] = SessionStatus.stopped;
      }
      state = state.copyWith(
        deviceStatuses: statuses,
        status: SessionStatus.stopped,
      );
      unawaited(_syncBackgroundRuntime('stopped'));
    } catch (e) {
      appLogger.d('Session: stop() state update ignored (notifier disposed)');
    }
  }

  Future<void> pauseDevice(String deviceId) async {
    if (state.deviceStatuses[deviceId] != SessionStatus.running) return;
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 3);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      // Safety net: never write to (or flip the status of) a device whose BLE
      // link is down — the command can't reach it and would desync app/device.
      // The UI also disables the control while disconnected.
      if (!connector.isConnected(deviceId)) {
        appLogger.w('Session: pauseDevice skipped — $deviceId not connected');
        return;
      }
      await connector.writeToDevice(deviceId, [_blePauseByte]);
    }
    _deviceStopwatches[deviceId]?.stop();
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.paused;
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
  }

  Future<void> resumeDevice(String deviceId) async {
    if (state.deviceStatuses[deviceId] != SessionStatus.paused) return;
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 4);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      if (!connector.isConnected(deviceId)) {
        appLogger.w('Session: resumeDevice skipped — $deviceId not connected');
        return;
      }
      await connector.writeToDevice(deviceId, [_bleResumeByte]);
    }
    _deviceStopwatches[deviceId]?.start();
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.running;
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
    if (_timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    }
  }

  Future<void> stopDevice(String deviceId) async {
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 2);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      if (!connector.isConnected(deviceId)) {
        appLogger.w('Session: stopDevice skipped — $deviceId not connected');
        return;
      }
      await connector.writeToDevice(deviceId, [_bleStopByte]);
    }
    _deviceStopwatches[deviceId]?.stop();
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.stopped;
    if (statuses.values.every(
      (s) => s == SessionStatus.stopped || s == SessionStatus.completed,
    )) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
    }
    final overallStatus = _deriveOverallStatus(statuses);
    state = state.copyWith(
      deviceStatuses: statuses,
      status: overallStatus,
    );
    if (overallStatus == SessionStatus.stopped ||
        overallStatus == SessionStatus.completed) {
      unawaited(_syncBackgroundRuntime('stopped'));
    }
  }

  /// A BLE disconnect is a CONNECTIVITY event, NOT a session-ending one. The
  /// Hydra firmware keeps running the loaded protocol autonomously after the
  /// link drops, so we keep the session and its timers running and never
  /// force-stop anything — parity with the web app, whose `gattserverdisconnected`
  /// handler only updates a connection badge and leaves the run alive.
  ///
  /// Applies to ALL BLE sessions (normal protocol and Protocol Plus). The BLE
  /// connector auto-reconnects in the background; if a Protocol Plus switch is
  /// due while disconnected, the write path reconnects on demand. The run ends
  /// only on its natural timer completion (or an explicit user stop) — not here.
  Future<void> handleBleDisconnect(String deviceId) async {
    if (!_isActive) return;
    if (state.transport != SessionTransport.ble) return;

    final currentStatus = state.deviceStatuses[deviceId];
    if (currentStatus == null) return;
    if (currentStatus == SessionStatus.stopped ||
        currentStatus == SessionStatus.completed) {
      return;
    }

    // Intentionally do NOT mark the device/session stopped, freeze its timer, or
    // stop the background runtime — the session continues through the disconnect.
    // The live connection state for the UI is tracked separately via
    // bleConnectionStatesProvider; this method must not end the run.
    appLogger.w(
      'Session: BLE device=$deviceId disconnected — keeping the session '
      'running (no forced stop; auto-reconnect in progress; session=$sessionId)',
    );
  }

  SessionRecord? getSessionRecord({
    String? sessionId,
    int? discomfortBefore,
    int? discomfortAfter,
    String? notes,
    String clientType = 'guest',
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    if (state.protocol == null) return null;
    final recordedAt = createdAt ?? DateTime.now();
    final protocolByDeviceId =
        <String, ({String name, int durationSeconds})>{
      for (final entry in state.protocolByDevice.entries)
        entry.key: (
          name: entry.value.templateName,
          durationSeconds: entry.value.totalDurationSeconds,
        ),
    };
    return SessionRecord(
      id: sessionId ?? const Uuid().v4(),
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: state.deviceIds,
      protocolByDeviceId: protocolByDeviceId,
      totalDurationSeconds: state.timer.totalDuration.inSeconds,
      elapsedSeconds: _effectiveElapsed.inSeconds,
      discomfortBefore: discomfortBefore,
      discomfortAfter: discomfortAfter,
      notes: notes,
      clientType: clientType,
      createdBy: createdBy,
      updatedBy: updatedBy,
      createdAt: recordedAt,
      updatedAt: updatedAt ?? recordedAt,
      completedAt: recordedAt,
    );
  }

  void reset() {
    _timer?.cancel();
    _stopwatch.reset();
    _sessionClockOffset = Duration.zero;
    _firstBlePlayAnchor = null;
    _wallClockAnchor = null;
    _monotonicAnchor = Duration.zero;
    _deviceClockOffset.clear();
    _startInProgress = false;
    _historyCaptured = false;
    _cycleIndex = -1;
    _repetition = 0;
    _isProtocolPlus = false;
    _protocolPlusDeviceIds.clear();
    try {
      state = const SessionEngineState();
      unawaited(_ref
          .read(backgroundSessionRuntimeProvider.notifier)
          .stopService(sessionId: sessionId));
    } catch (e) {
      appLogger.d('Session: reset() state update ignored (notifier disposed)');
    }
  }

  void _onTick(Timer timer) {
    if (!_isActive || state.status != SessionStatus.running) {
      timer.cancel();
      _timer = null;
      return;
    }
    _reconcileClockFromWall();
    _syncDisplayedTimerFromStopwatch();
  }

  void _syncDisplayedTimerFromStopwatch() {
    if (!_isActive || state.status != SessionStatus.running) return;

    final elapsed = _effectiveElapsed;
    final protocol = state.protocol;
    if (protocol == null) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
      if (!_isActive) return;
      try {
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Session timer tick ignored — protocol is missing',
        );
      } catch (e) {
        appLogger.d(
          'Session: protocol-missing tick state update ignored (notifier disposed)',
        );
      }
      return;
    }

    final updatedTimers = Map<String, TimerState>.from(state.deviceTimers);
    final updatedStatuses =
        Map<String, SessionStatus>.from(state.deviceStatuses);
    final completedDevices = <String>[];

    for (final id in state.deviceIds) {
      final status = updatedStatuses[id] ?? SessionStatus.idle;
      final sw = _deviceStopwatches[id];
      final timerState = updatedTimers[id];
      if (sw == null || timerState == null) continue;
      if (status == SessionStatus.running) {
        final devElapsed =
            sw.elapsed + (_deviceClockOffset[id] ?? Duration.zero);
        if (devElapsed >= timerState.totalDuration) {
          // Protocol Plus: a single protocol finishing is NOT the end of the
          // session. The firmware stops itself and the next protocol arrives
          // via START_PROTOCOL, so DON'T mark completed or send STOP here —
          // just clamp the displayed time and keep the device "running" so the
          // session stays live for the upcoming switch.
          final deviceIsPlus = _protocolPlusDeviceIds.contains(id) ||
              (_isProtocolPlus && _protocolPlusDeviceIds.isEmpty);
          if (deviceIsPlus) {
            updatedTimers[id] = timerState.copyWith(
              elapsed: timerState.totalDuration,
              isRunning: true,
            );
          } else {
            completedDevices.add(id);
            updatedStatuses[id] = SessionStatus.completed;
            updatedTimers[id] = timerState.copyWith(
              elapsed: timerState.totalDuration,
              isRunning: false,
            );
            sw.stop();
          }
        } else {
          updatedTimers[id] = timerState.copyWith(
            elapsed: devElapsed,
            isRunning: true,
          );
        }
      }
    }

    if (completedDevices.isNotEmpty) {
      unawaited(_completeDevices(completedDevices));
    }

    _calculateCurrentPosition(elapsed);

    if (!_isActive) return;

    final prevVisual = state.timer.lastVisualCycleIndex;
    final int newVisual;
    if (protocol.cycles.isEmpty) {
      newVisual = -1;
    } else if (_cycleIndex >= 0) {
      newVisual = _cycleIndex;
    } else if (prevVisual >= 0) {
      newVisual = prevVisual;
    } else {
      newVisual = 0;
    }

    final overallStatus = _deriveOverallStatus(updatedStatuses);

    try {
      state = state.copyWith(
        timer: state.timer.copyWith(
          elapsed: elapsed,
          currentCycleIndex: _cycleIndex,
          currentRepetition: _repetition,
          lastVisualCycleIndex: newVisual,
          isRunning: overallStatus == SessionStatus.running,
        ),
        deviceTimers: updatedTimers,
        deviceStatuses: updatedStatuses,
        status: overallStatus,
      );
    } catch (e) {
      appLogger.d('Session: tick state update ignored (notifier disposed)');
    }

    if (overallStatus == SessionStatus.completed ||
        overallStatus == SessionStatus.stopped) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
      unawaited(_syncBackgroundRuntime('stopped'));
    }
  }

  void _calculateCurrentPosition(Duration elapsed) {
    final protocol = state.protocol!;
    int accumulatedSeconds = 0;
    final elapsedSeconds = elapsed.inSeconds;

    for (int s = 0; s < protocol.sessions; s++) {
      for (int c = 0; c < protocol.cycles.length; c++) {
        final cycle = protocol.cycles[c];
        for (int r = 0; r < cycle.repetitions; r++) {
          accumulatedSeconds += cycle.durationSeconds.toInt();
          if (elapsedSeconds < accumulatedSeconds) {
            _cycleIndex = c;
            _repetition = r;
            return;
          }

          // Matches web payload mapping: pauseIntervals = cycle_pause.
          if (r < cycle.repetitions - 1) {
            accumulatedSeconds += cycle.cyclePause.toInt();
            if (elapsedSeconds < accumulatedSeconds) {
              _cycleIndex = -1;
              _repetition = r;
              return;
            }
          }
        }

        // Matches web payload mapping: cyclePauses = pause_seconds.
        accumulatedSeconds += cycle.pauseSeconds.toInt();
        if (elapsedSeconds < accumulatedSeconds) {
          _cycleIndex = -1;
          _repetition = cycle.repetitions > 0 ? cycle.repetitions - 1 : 0;
          return;
        }
      }

      if (s < protocol.sessions - 1) {
        accumulatedSeconds += protocol.sessionPause.toInt();
        if (elapsedSeconds < accumulatedSeconds) {
          _cycleIndex = -1;
          _repetition = 0;
          return;
        }
      }
    }

    _cycleIndex = protocol.cycles.isNotEmpty ? protocol.cycles.length - 1 : -1;
  }

  Future<void> _completeSession() async {
    appLogger.i('✅ SESSION COMPLETED: Time limit reached, stopping device');

    // CRITICAL: Stop the stopwatch and cancel timer FIRST
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;

    // THEN send STOP command to device (WiFi or BLE)
    appLogger.i('✅ SENDING STOP COMMAND TO DEVICE NOW');
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmd(2);
      appLogger.i('✅ WiFi STOP sent (playCmd=2)');
    } else if (state.transport == SessionTransport.ble) {
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);
        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleStopByte]);
          appLogger.i('✅ BLE STOP sent to $mac (0x$_bleStopByte)');
        }
      }
    }

    // Finally, update UI state
    if (!_isActive) return;
    try {
      state = state.copyWith(
        status: SessionStatus.completed,
        timer: state.timer.copyWith(
          elapsed: state.timer.totalDuration,
          isRunning: false,
        ),
      );
      appLogger.i('✅ SESSION COMPLETED: UI state updated, device stopped');
    } catch (e) {
      appLogger.d(
        'Session: completeSession state update ignored (notifier disposed)',
      );
    }
  }

  Future<void> _completeDevices(List<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    if (state.transport == SessionTransport.wifi) {
      await Future.wait(
        deviceIds.map((mac) => _publishWifiPlayCmdToMac(mac, 2)),
      );
    } else {
      final connector = _ref.read(bleConnectorProvider);
      for (final id in deviceIds) {
        await connector.writeToDevice(id, [_bleStopByte]);
      }
    }
  }

  SessionStatus _deriveOverallStatus(Map<String, SessionStatus> statuses) {
    if (statuses.values.any((s) => s == SessionStatus.running)) {
      return SessionStatus.running;
    }
    if (statuses.values.any((s) => s == SessionStatus.paused)) {
      return SessionStatus.paused;
    }
    if (statuses.isNotEmpty &&
        statuses.values.every(
          (s) => s == SessionStatus.completed || s == SessionStatus.stopped,
        )) {
      return statuses.values.any((s) => s == SessionStatus.completed)
          ? SessionStatus.completed
          : SessionStatus.stopped;
    }
    return SessionStatus.idle;
  }

  @override
  void dispose() {
    _isActive = false; // Mark as inactive before disposing
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
