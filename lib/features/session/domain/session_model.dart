enum SessionStatus { idle, running, paused, stopped, completed }

class SessionRecord {
  final String id;
  final String protocolId;
  final String protocolName;
  final List<String> deviceIds;
  final int totalDurationSeconds;
  final int elapsedSeconds;
  final int? discomfortBefore;
  final int? discomfortAfter;
  final String? notes;
  final bool synced;
  final DateTime completedAt;

  const SessionRecord({
    required this.id,
    required this.protocolId,
    required this.protocolName,
    required this.deviceIds,
    required this.totalDurationSeconds,
    required this.elapsedSeconds,
    this.discomfortBefore,
    this.discomfortAfter,
    this.notes,
    this.synced = false,
    required this.completedAt,
  });

  Map<String, dynamic> toIntakeJson() => {
        'protocols': [
          {
            'protocol': protocolId,
            'duration': elapsedSeconds,
            'deviceName': deviceIds.join(', '),
          }
        ],
        if (discomfortBefore != null || discomfortAfter != null)
          'discomfortAreas': [
            {
              'discomfortBefore': discomfortBefore ?? 0,
              'discomfortAfter': discomfortAfter ?? 0,
            }
          ],
        if (notes != null) 'sessionNotes': notes,
      };
}

class TimerState {
  final Duration elapsed;
  final Duration totalDuration;
  final int currentCycleIndex;
  final int currentRepetition;
  final int totalCycles;
  final bool isRunning;

  const TimerState({
    this.elapsed = Duration.zero,
    this.totalDuration = Duration.zero,
    this.currentCycleIndex = 0,
    this.currentRepetition = 0,
    this.totalCycles = 0,
    this.isRunning = false,
  });

  Duration get remaining => totalDuration - elapsed;
  double get progress =>
      totalDuration.inSeconds > 0
          ? elapsed.inSeconds / totalDuration.inSeconds
          : 0;

  TimerState copyWith({
    Duration? elapsed,
    Duration? totalDuration,
    int? currentCycleIndex,
    int? currentRepetition,
    int? totalCycles,
    bool? isRunning,
  }) {
    return TimerState(
      elapsed: elapsed ?? this.elapsed,
      totalDuration: totalDuration ?? this.totalDuration,
      currentCycleIndex: currentCycleIndex ?? this.currentCycleIndex,
      currentRepetition: currentRepetition ?? this.currentRepetition,
      totalCycles: totalCycles ?? this.totalCycles,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}
