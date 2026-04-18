enum SessionStatus { idle, running, paused, stopped, completed }

/// How this session was started (BLE vs WiFi/MQTT).
enum SessionTransport { ble, wifi }

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

  /// Last cycle index while the device was in an active treatment segment
  /// (not in a timed pause gap). Used for moon/sun pad colors when
  /// [currentCycleIndex] is `-1` during those gaps so UI matches hardware.
  final int lastVisualCycleIndex;

  const TimerState({
    this.elapsed = Duration.zero,
    this.totalDuration = Duration.zero,
    this.currentCycleIndex = -1,
    this.currentRepetition = 0,
    this.totalCycles = 0,
    this.isRunning = false,
    this.lastVisualCycleIndex = -1,
  });

  Duration get remaining {
    final r = totalDuration - elapsed;
    return r.isNegative ? Duration.zero : r;
  }
  double get progress =>
      totalDuration.inMilliseconds > 0
          ? (elapsed.inMilliseconds / totalDuration.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0;

  TimerState copyWith({
    Duration? elapsed,
    Duration? totalDuration,
    int? currentCycleIndex,
    int? currentRepetition,
    int? totalCycles,
    bool? isRunning,
    int? lastVisualCycleIndex,
  }) {
    return TimerState(
      elapsed: elapsed ?? this.elapsed,
      totalDuration: totalDuration ?? this.totalDuration,
      currentCycleIndex: currentCycleIndex ?? this.currentCycleIndex,
      currentRepetition: currentRepetition ?? this.currentRepetition,
      totalCycles: totalCycles ?? this.totalCycles,
      isRunning: isRunning ?? this.isRunning,
      lastVisualCycleIndex:
          lastVisualCycleIndex ?? this.lastVisualCycleIndex,
    );
  }
}
