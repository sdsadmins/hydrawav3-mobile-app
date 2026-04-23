import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../../ble/services/ble_connector.dart';
import '../../protocols/domain/protocol_model.dart';
import '../domain/session_model.dart';

final sessionEngineProvider =
    StateNotifierProvider<SessionEngine, SessionEngineState>((ref) {
  return SessionEngine(ref);
});

class SessionEngineState {
  final SessionStatus status;
  final TimerState timer;
  final Protocol? protocol;
  final List<String> deviceIds;
  final SessionTransport transport;
  final String? error;

  const SessionEngineState({
    this.status = SessionStatus.idle,
    this.timer = const TimerState(),
    this.protocol,
    this.deviceIds = const [],
    this.transport = SessionTransport.ble,
    this.error,
  });

  SessionEngineState copyWith({
    SessionStatus? status,
    TimerState? timer,
    Protocol? protocol,
    List<String>? deviceIds,
    SessionTransport? transport,
    String? error,
  }) {
    return SessionEngineState(
      status: status ?? this.status,
      timer: timer ?? this.timer,
      protocol: protocol ?? this.protocol,
      deviceIds: deviceIds ?? this.deviceIds,
      transport: transport ?? this.transport,
      error: error,
    );
  }
}

class SessionEngine extends StateNotifier<SessionEngineState> {
  final Ref _ref;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _sessionClockOffset = Duration.zero;
  DateTime? _firstBlePlayAnchor;
  bool _startInProgress = false;
  int _cycleIndex = 0;
  int _repetition = 0;
  bool _isActive = true; // Guard against state updates after disposal
  static const int _blePauseByte = 0x02;
  static const int _bleResumeByte = 0x04;
  static const int _bleStopByte = 0x03;
  static const String _debugLightProtocolId = 'light-on';

  SessionEngine(this._ref) : super(const SessionEngineState());

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

  Duration get _effectiveElapsed =>
      _stopwatch.elapsed + _sessionClockOffset;

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
        await dio.post(
          ApiEndpoints.mqttPublish,
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
  }) {
    if (!_isActive) return; // Guard against updates after disposal

    appLogger.i('═══════════════════════════════════════════════════');
    appLogger.i('Session: loadSession()');
    appLogger.i('  Protocol: ${protocol.templateName} (id=${protocol.id})');
    appLogger.i('  Transport: $transport');
    appLogger.i('  Devices: $deviceIds');
    appLogger.i('  Cycles: ${protocol.cycles.length}');
    appLogger.i('  Total Duration: ${protocol.totalDurationSeconds}s');
    appLogger.i('═══════════════════════════════════════════════════');

    final selectedDeviceIds = List<String>.from(deviceIds);

    try {
      state = SessionEngineState(
        status: SessionStatus.idle,
        protocol: protocol,
        deviceIds: selectedDeviceIds,
        transport: transport,
        timer: TimerState(
          totalDuration: protocol.totalDuration,
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
    _startInProgress = false;
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
        appLogger.i(
          'Session: Starting WiFi session timer (devices=${state.deviceIds.length})',
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

      final protocol = state.protocol!;
      appLogger.i(
        'Session: start payload source '
        '(protocolId=${protocol.id}, name=${protocol.templateName}, sessions=${protocol.sessions}, cycles=${protocol.cycles.length})',
      );

      // For BLE we intentionally start UI timer only AFTER PLAY succeeds,
      // so elapsed time tracks physical device runtime.
      appLogger.i('Session: Starting BLE send sequence (timer starts after PLAY)');

      // Send protocol JSON to each connected device over BLE (RS232 bridge).
      final failed = <String>[];
      final bool singleBleDevice = actuallyConnectedIds.length == 1;
      var bleTimerStarted = false;
      _firstBlePlayAnchor = null;
      for (final mac in actuallyConnectedIds) {
      final legacyShape = _protocolToRs232Json(
        protocol,
        transportId: mac,
      );
      if (protocol.cycles.isNotEmpty) {
        final c0 = protocol.cycles.first;
        appLogger.i(
          'Session: protocol first-cycle '
          '(dur=${c0.durationSeconds}, rep=${c0.repetitions}, hot=${c0.hotPwm}, cold=${c0.coldPwm}, left=${c0.leftFunction}, right=${c0.rightFunction})',
        );
      }

      // Keep BLE payload identical to the web sender:
      // flattened RS35 fields (sessionCount/cycleRepetitions/pwmValues/...).
      final protocolFrame = jsonEncode(legacyShape);

      // Log the EXACT request we are sending over BLE.
      // Escape newlines/carriage returns so framing is visible in logs.
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
      appLogger.i('   - cycles: ${protocol.cycles.length}');
      appLogger.i('   - total duration: ${protocol.totalDurationSeconds}s');
      appLogger.i('   - payload size: ${protocolFrame.length} bytes');
      appLogger.i("🔥 CALLING BLE PAYLOAD NOW");
      final okProtocol = await _sendLargePayload(mac, protocolFrame);
      appLogger
          .i("🔥 BLE PAYLOAD RESULT: okProtocol=$okProtocol for device=$mac");

      if (!okProtocol) {
        appLogger.e("🔥 PAYLOAD FAILED FOR $mac - ADDING TO FAILED LIST");
        failed.add(mac);
        continue;
      }
      appLogger.i("✅ PAYLOAD SUCCESS FOR $mac");

      // Mirror web flow exactly for firmware compatibility:
      // config JSON -> fixed wait -> raw PLAY control byte.
      final prePlayDelay = const Duration(milliseconds: 2500);
      appLogger.i(
        'Session: web-parity pre-PLAY delay=${prePlayDelay.inMilliseconds}ms for $mac',
      );

      // The firmware expects a separate raw PLAY trigger after the JSON config
      // has been written. This mirrors the JS flow: config → wait → 0x01.
      await Future<void>.delayed(prePlayDelay);
      appLogger.i('Session: Sending raw PLAY command (0x01) to $mac');
      final playAnchor = DateTime.now();
      final okRawPlay = await connector.writeToDevice(mac, [0x01]);
      appLogger.i(
        'Session: BLE raw PLAY command result for $mac → $okRawPlay',
      );
      if (okRawPlay) {
        _firstBlePlayAnchor ??= playAnchor;
      }
      if (!okRawPlay) {
        failed.add(mac);
      } else if (singleBleDevice) {
        // Single-device: start UI clock as soon as PLAY succeeds; offset
        // catches BLE write latency so elapsed tracks the machine.
        bleTimerStarted = true;
        if (_firstBlePlayAnchor != null) {
          applySessionClockOffsetFromWallAnchor(_firstBlePlayAnchor!);
        }
        _beginRuntimeTimer();
      }

      await Future<void>.delayed(
          const Duration(milliseconds: 300)); // Gap between devices
      }

      if (failed.isNotEmpty) {
        _stopwatch.stop();
        _timer?.cancel();
        _timer = null;
        if (!_isActive) return;
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Failed to send protocol to: ${failed.join(', ')}',
        );
        appLogger.w('Session: Start aborted — protocol send failed');
        return;
      }

      if (!bleTimerStarted) {
        if (_firstBlePlayAnchor != null) {
          applySessionClockOffsetFromWallAnchor(_firstBlePlayAnchor!);
        }
        _beginRuntimeTimer();
      }
    } finally {
      _startInProgress = false;
    }
  }

  void _beginRuntimeTimer() {
    appLogger.i(
      'Session: Runtime timer started (clockOffset=$_sessionClockOffset)',
    );
    if (!_isActive) return;
    try {
      state = state.copyWith(status: SessionStatus.running, error: null);
    } catch (e) {
      appLogger.d('Session: timer start state update ignored (notifier disposed)');
      return;
    }
    final alreadyRunning = _stopwatch.isRunning;
    if (!alreadyRunning) {
      _stopwatch.reset();
      _stopwatch.start();
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    // Periodic timer does not fire until the first interval; sync once now
    // so remaining time and cycle/pad UI match the device immediately.
    _syncDisplayedTimerFromStopwatch();
  }

  Map<String, dynamic> _protocolToRs232Json(
    Protocol p, {
    required String transportId,
  }) {
    final cycles = p.cycles;
    return {
      // Match WiFi payload field order (device firmware expects this order)
      // In BLE mode web treats mac as optional/ignored by firmware.
      'mac': '',
      'sessionCount': p.sessions,
      'sessionPause': p.sessionPause.toInt(),
      'sDelay': 0,
      'cycle1': p.cycle1 ? 1 : 0,
      'cycle5': p.cycle5 ? 1 : 0,
      'edgeCycleDuration': p.edgecycleduration.toInt(),
      'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
      'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
      // Web maps pause_seconds -> cyclePauses and cycle_pause -> pauseIntervals.
      'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
      'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
      'leftFuncs': cycles.map((c) => c.leftFunction).toList(),
      'rightFuncs': cycles.map((c) => c.rightFunction).toList(),
      'pwmValues': {
        'hot': cycles.map((c) => c.hotPwm.toInt()).toList(),
        'cold': cycles.map((c) => c.coldPwm.toInt()).toList(),
      },
      'playCmd': 1,
      'led': 1,
      'hotDrop': p.hotdrop.toInt(),
      'coldDrop': p.colddrop.toInt(),
      'vibMin': p.vibmin.toInt(),
      'vibMax': p.vibmax.toInt(),
      'totalDuration': p.totalDurationSeconds,
    };
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

    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;

    try {
      state = state.copyWith(status: SessionStatus.paused);
      appLogger.i('🔥 PAUSE: State updated to paused');
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

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    _syncDisplayedTimerFromStopwatch();
    appLogger.i('🔄 RESUME: Timer restarted on app side');
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
    if (!_isActive) return;
    state = state.copyWith(status: SessionStatus.stopped);
  }

  SessionRecord? getSessionRecord({
    int? discomfortBefore,
    int? discomfortAfter,
    String? notes,
  }) {
    if (state.protocol == null) return null;
    return SessionRecord(
      id: const Uuid().v4(),
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: state.deviceIds,
      totalDurationSeconds: state.timer.totalDuration.inSeconds,
      elapsedSeconds: _effectiveElapsed.inSeconds,
      discomfortBefore: discomfortBefore,
      discomfortAfter: discomfortAfter,
      notes: notes,
      completedAt: DateTime.now(),
    );
  }

  void reset() {
    _timer?.cancel();
    _stopwatch.reset();
    _sessionClockOffset = Duration.zero;
    _firstBlePlayAnchor = null;
    _startInProgress = false;
    _cycleIndex = -1;
    _repetition = 0;
    state = const SessionEngineState();
  }

  void _onTick(Timer timer) {
    if (!_isActive || state.status != SessionStatus.running) {
      timer.cancel();
      _timer = null;
      return;
    }
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
      state = state.copyWith(
        status: SessionStatus.stopped,
        error: 'Session timer tick ignored — protocol is missing',
      );
      return;
    }

    if (elapsed >= protocol.totalDuration) {
      _completeSession();
      return;
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

    try {
      state = state.copyWith(
        timer: state.timer.copyWith(
          elapsed: elapsed,
          currentCycleIndex: _cycleIndex,
          currentRepetition: _repetition,
          lastVisualCycleIndex: newVisual,
          isRunning: true,
        ),
      );
    } catch (e) {
      appLogger.d('Session: tick state update ignored (notifier disposed)');
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
    state = state.copyWith(
      status: SessionStatus.completed,
      timer: state.timer.copyWith(
        elapsed: state.timer.totalDuration,
        isRunning: false,
      ),
    );
    appLogger.i('✅ SESSION COMPLETED: UI state updated, device stopped');
  }

  @override
  void dispose() {
    _isActive = false; // Mark as inactive before disposing
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
