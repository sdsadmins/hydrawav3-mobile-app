import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/logger.dart';
import '../../ble/data/ble_repository.dart';
import '../../ble/domain/ble_command.dart';
import '../../protocols/domain/protocol_model.dart';
import '../domain/session_model.dart';

final sessionEngineProvider =
    StateNotifierProvider<SessionEngine, SessionEngineState>((ref) {
  return SessionEngine(ref.read(bleRepositoryProvider));
});

class SessionEngineState {
  final SessionStatus status;
  final TimerState timer;
  final Protocol? protocol;
  final List<String> deviceIds;
  final String? error;

  const SessionEngineState({
    this.status = SessionStatus.idle,
    this.timer = const TimerState(),
    this.protocol,
    this.deviceIds = const [],
    this.error,
  });

  SessionEngineState copyWith({
    SessionStatus? status,
    TimerState? timer,
    Protocol? protocol,
    List<String>? deviceIds,
    String? error,
  }) {
    return SessionEngineState(
      status: status ?? this.status,
      timer: timer ?? this.timer,
      protocol: protocol ?? this.protocol,
      deviceIds: deviceIds ?? this.deviceIds,
      error: error,
    );
  }
}

class SessionEngine extends StateNotifier<SessionEngineState> {
  final BleRepository _bleRepository;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  int _cycleIndex = 0;
  int _repetition = 0;

  SessionEngine(this._bleRepository) : super(const SessionEngineState());

  /// Load a protocol and prepare for execution.
  void loadSession(Protocol protocol, List<String> deviceIds) {
    state = SessionEngineState(
      status: SessionStatus.idle,
      protocol: protocol,
      deviceIds: deviceIds,
      timer: TimerState(
        totalDuration: protocol.totalDuration,
        totalCycles: protocol.cycles.length,
      ),
    );
    _cycleIndex = 0;
    _repetition = 0;
  }

  /// Start the session.
  Future<void> start() async {
    if (state.protocol == null) return;
    if (state.status == SessionStatus.running) return;

    appLogger.i('Session: Starting');
    state = state.copyWith(status: SessionStatus.running);

    // Send start command to all devices
    await _sendCommandToDevices(CommandType.start, _getCurrentCyclePayload());

    // Start timer
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  /// Pause the session.
  Future<void> pause() async {
    if (state.status != SessionStatus.running) return;

    appLogger.i('Session: Pausing');
    _stopwatch.stop();
    _timer?.cancel();

    await _sendCommandToDevices(CommandType.pause);
    state = state.copyWith(status: SessionStatus.paused);
  }

  /// Resume a paused session.
  Future<void> resume() async {
    if (state.status != SessionStatus.paused) return;

    appLogger.i('Session: Resuming');
    state = state.copyWith(status: SessionStatus.running);

    await _sendCommandToDevices(CommandType.resume);

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  /// Stop the session (user-initiated).
  Future<void> stop() async {
    appLogger.i('Session: Stopping');
    _stopwatch.stop();
    _timer?.cancel();

    await _sendCommandToDevices(CommandType.stop);
    state = state.copyWith(status: SessionStatus.stopped);
  }

  /// Get the completed session record.
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

  /// Reset engine for a new session.
  void reset() {
    _timer?.cancel();
    _stopwatch.reset();
    _cycleIndex = 0;
    _repetition = 0;
    state = const SessionEngineState();
  }

  void _onTick(Timer timer) {
    final elapsed = _stopwatch.elapsed;
    final protocol = state.protocol!;

    // Check if session is complete
    if (elapsed >= protocol.totalDuration) {
      _completeSession();
      return;
    }

    // Calculate current cycle and repetition
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
          if (_cycleIndex != c || _repetition != r) {
            _cycleIndex = c;
            _repetition = r;
            // Cycle changed — send new cycle params
            _sendCommandToDevices(CommandType.start, _getCurrentCyclePayload());
          }
          return;
        }
        // Add cycle pause between repetitions
        if (r < cycle.repetitions - 1) {
          accumulatedSeconds += cycle.cyclePause.toInt();
        }
      }
    }
  }

  Map<String, dynamic>? _getCurrentCyclePayload() {
    final protocol = state.protocol;
    if (protocol == null || _cycleIndex >= protocol.cycles.length) return null;

    final cycle = protocol.cycles[_cycleIndex];
    return {
      'hot_pwm': cycle.hotPwm,
      'cold_pwm': cycle.coldPwm,
      'left_function': cycle.leftFunction,
      'right_function': cycle.rightFunction,
      'duration_seconds': cycle.durationSeconds,
      'vibmin': protocol.vibmin,
      'vibmax': protocol.vibmax,
    };
  }

  Future<void> _completeSession() async {
    appLogger.i('Session: Completed');
    _stopwatch.stop();
    _timer?.cancel();

    await _sendCommandToDevices(CommandType.stop);
    state = state.copyWith(
      status: SessionStatus.completed,
      timer: state.timer.copyWith(
        elapsed: state.timer.totalDuration,
        isRunning: false,
      ),
    );
  }

  Future<void> _sendCommandToDevices(
    CommandType type, [
    Map<String, dynamic>? payload,
  ]) async {
    for (final deviceId in state.deviceIds) {
      final command = BleCommand(
        macAddress: deviceId,
        type: type,
        payload: payload,
      );
      await _bleRepository.sendCommand(command);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
