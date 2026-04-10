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
  int _cycleIndex = 0;
  int _repetition = 0;

  SessionEngine(this._ref) : super(const SessionEngineState());

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
    state = state.copyWith(
      deviceIds: deviceIds,
      transport: transport,
    );
    appLogger.i(
      'Session: prepareSession(transport=$transport, deviceIds=$deviceIds)',
    );
  }

  void loadSession(
    Protocol protocol,
    List<String> deviceIds, {
    SessionTransport transport = SessionTransport.ble,
  }) {
    appLogger.i(
      'Session: loadSession(protocol=${protocol.id}, transport=$transport, deviceIds=$deviceIds)',
    );
    state = SessionEngineState(
      status: SessionStatus.idle,
      protocol: protocol,
      deviceIds: deviceIds,
      transport: transport,
      timer: TimerState(
        totalDuration: protocol.totalDuration,
        totalCycles: protocol.cycles.length,
      ),
    );
    _cycleIndex = 0;
    _repetition = 0;
  }

  Future<void> start() async {
    if (state.status == SessionStatus.running) return;

    appLogger.i(
      'Session: start() transport=${state.transport} deviceIds=${state.deviceIds}',
    );

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
      state = state.copyWith(status: SessionStatus.running, error: null);
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
      return;
    }

    final connector = _ref.read(bleConnectorProvider);
    final targetDeviceIds =
        state.deviceIds.isNotEmpty ? state.deviceIds : connector.connectedDeviceIds;

    if (targetDeviceIds.isEmpty) {
      state = state.copyWith(
        error: 'No BLE device selected/connected',
      );
      appLogger.w('Session: Start aborted — no target BLE devices');
      return;
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
        'to ${targetDeviceIds.length} device(s)',
      );

      for (final mac in targetDeviceIds) {
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
      state = state.copyWith(status: SessionStatus.stopped, error: null);
      return;
    }

    if (state.protocol == null) return;

    final protocol = state.protocol!;

    // Send protocol JSON to each device over BLE (RS232 bridge).
    final failed = <String>[];
    for (final mac in targetDeviceIds) {
      // Special-case: the "Light On (Debug)" protocol can optionally send the
      // raw control byte first (matching web: Uint8Array([0x01])).
      if (protocol.id == 'light-on') {
        final control = <int>[BleConstants.lightOnControlByte];
        appLogger.i(
          'Session: BLE raw control write (device=$mac, bytes=$control)',
        );
        final okRaw = await connector.writeToDevice(mac, control);
        appLogger.i('Session: BLE raw control write result for $mac → $okRaw');
        if (!okRaw) failed.add(mac);
        // Small gap to mimic typical UART bridge timing.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      // Firmware "deviceId" should come from the BLE connect/event handshake.
      // If we haven't captured it yet, fall back to the configured default.
      final capturedFirmwareId = connector.getFirmwareSessionId(mac);
      final deviceIdForJson = capturedFirmwareId ??
          BleConstants.jsonDeviceIdForSession(
            bleTransportId: mac,
            discoveredWriteCharacteristicUuid:
                connector.getGattInfo(mac)?.writeUuid,
          );
      final inner = _protocolToRs232Json(
        protocol,
        transportId: mac,
        deviceId: deviceIdForJson,
      );
      // Match the web payload shape: a Map keyed by firmware deviceId.
      // We send JSON without the "new Map(...)" wrapper:
      // { "<deviceId>": { ...payload... } }\n
      final payload = <String, dynamic>{
        deviceIdForJson: inner,
      };
      final protocolFrame =
          '${jsonEncode(payload)}${BleConstants.sessionJsonLineSuffix}';

      // Log the EXACT request we are sending over BLE.
      // Escape newlines/carriage returns so framing is visible in logs.
      final escapedFrame = protocolFrame
          .replaceAll('\r', r'\r')
          .replaceAll('\n', r'\n');
      appLogger.i(
        'Session: BLE request (device=$mac, deviceIdKey=$deviceIdForJson, '
        'deviceIdSource=${capturedFirmwareId != null ? 'captured' : 'fallback'}): '
        '$escapedFrame',
      );

      appLogger.i(
        'Session: Sending protocol to $mac (json deviceId=$deviceIdForJson, '
        'mac key=$mac, ${protocolFrame.length} bytes)',
      );
      final okProtocol =
          await connector.writeToDevice(mac, utf8.encode(protocolFrame));
      appLogger.i('Session: Protocol frame sent to $mac → $okProtocol');
      if (!okProtocol) failed.add(mac);
    }

    if (failed.isNotEmpty) {
      state = state.copyWith(
        error: 'Failed to send protocol to: ${failed.join(', ')}',
      );
      appLogger.w('Session: Start aborted — protocol send failed');
      return;
    }

    appLogger.i('Session: Starting');
    state = state.copyWith(status: SessionStatus.running, error: null);

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  Map<String, dynamic> _protocolToRs232Json(
    Protocol p, {
    required String transportId,
    required String deviceId,
  }) {
    final cycles = p.cycles;
    return {
      // Web format uses the deviceId as the OUTER map key, so the inner object
      // does not include `deviceId`.
      // Keep `mac` empty to match the web payload exactly.
      'mac': '',
      // Include start command directly in protocol JSON as requested.
      'playCmd': 1,
      'sessionCount': p.sessions,
      'sessionPause': p.sessionPause.toInt(),
      'sDelay': 0,
      'cycle1': p.cycle1 ? 1 : 0,
      'cycle5': p.cycle5 ? 1 : 0,
      'edgeCycleDuration': p.edgecycleduration.toInt(),
      'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
      'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
      'cyclePauses': cycles.map((c) => c.cyclePause.toInt()).toList(),
      'pauseIntervals': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
      'leftFuncs': cycles.map((c) => c.leftFunction).toList(),
      'rightFuncs': cycles.map((c) => c.rightFunction).toList(),
      'pwmValues': {
        'hot': cycles.map((c) => c.hotPwm.toInt()).toList(),
        'cold': cycles.map((c) => c.coldPwm.toInt()).toList(),
      },
      'led': 1,
      'hotDrop': p.hotdrop.toInt(),
      'coldDrop': p.colddrop.toInt(),
      'vibMin': p.vibmin.toInt(),
      'vibMax': p.vibmax.toInt(),
      'totalDuration': p.totalDurationSeconds,
    };
  }

  Future<void> pause() async {
    if (state.status != SessionStatus.running) return;

    if (state.transport == SessionTransport.wifi) {
      // User-specified WiFi pause command.
      await _publishWifiPlayCmd(3);
    }

    _stopwatch.stop();
    _timer?.cancel();
    state = state.copyWith(status: SessionStatus.paused);
  }

  Future<void> resume() async {
    if (state.status != SessionStatus.paused) return;
    state = state.copyWith(status: SessionStatus.running);

    if (state.transport == SessionTransport.wifi) {
      // User-specified WiFi resume command.
      await _publishWifiPlayCmd(4);
    }

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  Future<void> stop() async {
    // For WiFi sessions, stopping should also send the STOP command to the
    // device(s) via MQTT/API.
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmd(2);
    }

    _stopwatch.stop();
    _timer?.cancel();
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
      elapsedSeconds: _stopwatch.elapsed.inSeconds,
      discomfortBefore: discomfortBefore,
      discomfortAfter: discomfortAfter,
      notes: notes,
      completedAt: DateTime.now(),
    );
  }

  void reset() {
    _timer?.cancel();
    _stopwatch.reset();
    _cycleIndex = 0;
    _repetition = 0;
    state = const SessionEngineState();
  }

  void _onTick(Timer timer) {
    final elapsed = _stopwatch.elapsed;
    final protocol = state.protocol;
    if (protocol == null) {
      // Guard against a stale timer running after protocol was cleared.
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
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

    state = state.copyWith(
      timer: state.timer.copyWith(
        elapsed: elapsed,
        currentCycleIndex: _cycleIndex,
        currentRepetition: _repetition,
        isRunning: true,
      ),
    );
  }

  void _calculateCurrentPosition(Duration elapsed) {
    final protocol = state.protocol!;
    int accumulatedSeconds = 0;

    for (int c = 0; c < protocol.cycles.length; c++) {
      final cycle = protocol.cycles[c];
      for (int r = 0; r < cycle.repetitions; r++) {
        accumulatedSeconds += cycle.durationSeconds.toInt();
        if (elapsed.inSeconds < accumulatedSeconds) {
          _cycleIndex = c;
          _repetition = r;
          return;
        }
        if (r < cycle.repetitions - 1) {
          accumulatedSeconds += cycle.cyclePause.toInt();
        }
      }
    }
  }

  Future<void> _completeSession() async {
    _stopwatch.stop();
    _timer?.cancel();
    state = state.copyWith(
      status: SessionStatus.completed,
      timer: state.timer.copyWith(
        elapsed: state.timer.totalDuration,
        isRunning: false,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
