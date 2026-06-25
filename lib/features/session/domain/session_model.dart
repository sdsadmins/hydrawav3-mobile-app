import '../../intake/domain/intake_models.dart';

enum SessionStatus { idle, running, paused, stopped, completed }

/// How this session was started (BLE vs WiFi/MQTT).
enum SessionTransport { ble, wifi }

class SessionRecord {
  final String id;
  final String protocolId;
  final String protocolName;
  final List<String> deviceIds;

  /// Per-device protocol (deviceId -> protocol name + its duration in seconds).
  /// Lets a single session store a different protocol per device. Falls back to
  /// [protocolName] / overall duration for any device missing from the map.
  final Map<String, ({String name, int durationSeconds})> protocolByDeviceId;

  final int totalDurationSeconds;
  final int elapsedSeconds;
  final int? discomfortBefore;
  final int? discomfortAfter;
  final String? notes;
  final String clientType;

  /// Backend client id when [clientType] == 'client' (null for guest).
  final String? clientId;

  /// Guided Assessment intake captured for this session (null for Quick Start).
  final GuidedAssessmentData? intake;

  final String? createdBy;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;
  final DateTime completedAt;

  const SessionRecord({
    required this.id,
    required this.protocolId,
    required this.protocolName,
    required this.deviceIds,
    this.protocolByDeviceId = const {},
    required this.totalDurationSeconds,
    required this.elapsedSeconds,
    this.discomfortBefore,
    this.discomfortAfter,
    this.notes,
    this.clientType = 'guest',
    this.clientId,
    this.intake,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
    required this.completedAt,
  });

  /// Build the `POST /intake` body. Only fields declared on the backend
  /// `CreateIntakeDto` are allowed — the server rejects anything else
  /// (`whitelist + forbidNonWhitelisted`). `createdBy`/`updatedBy`/timestamps
  /// are derived server-side from the authenticated user, so we don't send them.
  Map<String, dynamic> toIntakeJson() {
    final fallbackRaw =
        elapsedSeconds > 0 ? elapsedSeconds : totalDurationSeconds;
    final fallbackDuration = fallbackRaw > 0 ? fallbackRaw : 1;

    final protocolEntries = <Map<String, dynamic>>[];
    for (final deviceId in deviceIds) {
      final info = protocolByDeviceId[deviceId];
      final rawDuration = info?.durationSeconds ?? fallbackDuration;
      protocolEntries.add({
        'bodyPart': 'General',
        'protocol': info?.name ?? protocolName,
        'duration': rawDuration > 0 ? rawDuration : 1, // DTO requires @Min(1)
        'deviceName': deviceId,
      });
    }

    final body = <String, dynamic>{
      'clientType': clientType,
      if (clientId != null && clientId!.isNotEmpty) 'clientId': clientId,
      'protocols': protocolEntries,
    };

    // Guided Assessment intake (real ROM / activities / posture / areas).
    final intakeFields = intake?.toIntakeFields();
    if (intakeFields != null) body.addAll(intakeFields);

    // Fall back to a synthetic discomfort area only when the guided intake did
    // not supply real areas (e.g. Quick Start) but pre/post pain was recorded.
    final hasGuidedAreas = body['discomfortAreas'] != null;
    if (!hasGuidedAreas &&
        (discomfortBefore != null || discomfortAfter != null)) {
      body['discomfortAreas'] = [
        {
          'discompfortbodyPart': 'General',
          'side': 'Both',
          'discomfortBefore': discomfortBefore ?? 0,
          'discomfortAfter': discomfortAfter ?? 0,
          'temporalDuration': 'Less than 6 weeks',
          'behavior': 'Comes and Goes',
        }
      ];
    }

    // Session-level notes (separate from the intake's missingRemark).
    if (notes != null && notes!.isNotEmpty && body['sessionNotes'] == null) {
      body['sessionNotes'] = notes;
    }

    return body;
  }
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

  double get progress => totalDuration.inMilliseconds > 0
      ? (elapsed.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
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
      lastVisualCycleIndex: lastVisualCycleIndex ?? this.lastVisualCycleIndex,
    );
  }
}
