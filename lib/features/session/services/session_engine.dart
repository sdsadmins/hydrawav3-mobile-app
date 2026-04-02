import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/logger.dart';
import '../../ble/domain/ble_command.dart';
import '../../protocols/domain/protocol_model.dart';
import '../domain/session_model.dart';

final sessionEngineProvider =
    StateNotifierProvider<SessionEngine, SessionEngineState>((ref) {
  return SessionEngine();
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
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  int _cycleIndex = 0;
  int _repetition = 0;

  SessionEngine() : super(const SessionEngineState());

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

  Future<void> start() async {
    if (state.protocol == null || state.status == SessionStatus.running) return;

    appLogger.i('Session: Starting');
    state = state.copyWith(status: SessionStatus.running);

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  Future<void> pause() async {
    if (state.status != SessionStatus.running) return;
    _stopwatch.stop();
    _timer?.cancel();
    state = state.copyWith(status: SessionStatus.paused);
  }

  Future<void> resume() async {
    if (state.status != SessionStatus.paused) return;
    state = state.copyWith(status: SessionStatus.running);
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  Future<void> stop() async {
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
    final protocol = state.protocol!;

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
