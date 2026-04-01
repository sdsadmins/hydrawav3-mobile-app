class Protocol {
  final String id;
  final String templateName;
  final int sessions;
  final List<ProtocolCycle> cycles;
  final double hotdrop;
  final double colddrop;
  final double vibmin;
  final double vibmax;
  final bool cycle1;
  final bool cycle5;
  final double edgecycleduration;
  final double sessionPause;
  final String description;

  const Protocol({
    required this.id,
    required this.templateName,
    this.sessions = 1,
    this.cycles = const [],
    this.hotdrop = 0,
    this.colddrop = 0,
    this.vibmin = 0,
    this.vibmax = 0,
    this.cycle1 = false,
    this.cycle5 = false,
    this.edgecycleduration = 0,
    this.sessionPause = 0,
    this.description = '',
  });

  factory Protocol.fromJson(Map<String, dynamic> json) => Protocol(
        id: json['_id'] as String? ?? json['id'] as String? ?? '',
        templateName: json['template_name'] as String? ?? '',
        sessions: json['sessions'] as int? ?? 1,
        cycles: (json['cycles'] as List<dynamic>?)
                ?.map((e) => ProtocolCycle.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        hotdrop: (json['hotdrop'] as num?)?.toDouble() ?? 0,
        colddrop: (json['colddrop'] as num?)?.toDouble() ?? 0,
        vibmin: (json['vibmin'] as num?)?.toDouble() ?? 0,
        vibmax: (json['vibmax'] as num?)?.toDouble() ?? 0,
        cycle1: json['cycle1'] as bool? ?? false,
        cycle5: json['cycle5'] as bool? ?? false,
        edgecycleduration:
            (json['edgecycleduration'] as num?)?.toDouble() ?? 0,
        sessionPause: (json['session_pause'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'template_name': templateName,
        'sessions': sessions,
        'cycles': cycles.map((c) => c.toJson()).toList(),
        'hotdrop': hotdrop,
        'colddrop': colddrop,
        'vibmin': vibmin,
        'vibmax': vibmax,
        'cycle1': cycle1,
        'cycle5': cycle5,
        'edgecycleduration': edgecycleduration,
        'session_pause': sessionPause,
        'description': description,
      };

  /// Total duration in seconds across all cycles and sessions.
  int get totalDurationSeconds {
    int cycleDuration = 0;
    for (final cycle in cycles) {
      cycleDuration += (cycle.durationSeconds * cycle.repetitions).toInt();
      cycleDuration += (cycle.cyclePause * (cycle.repetitions - 1)).toInt();
    }
    return (cycleDuration * sessions + sessionPause * (sessions - 1)).toInt();
  }

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
}

class ProtocolCycle {
  final double hotPwm;
  final double coldPwm;
  final double cyclePause;
  final int repetitions;
  final String leftFunction;
  final double pauseSeconds;
  final String rightFunction;
  final double durationSeconds;

  const ProtocolCycle({
    this.hotPwm = 0,
    this.coldPwm = 0,
    this.cyclePause = 0,
    this.repetitions = 1,
    this.leftFunction = '',
    this.pauseSeconds = 0,
    this.rightFunction = '',
    this.durationSeconds = 0,
  });

  factory ProtocolCycle.fromJson(Map<String, dynamic> json) => ProtocolCycle(
        hotPwm: (json['hot_pwm'] as num?)?.toDouble() ?? 0,
        coldPwm: (json['cold_pwm'] as num?)?.toDouble() ?? 0,
        cyclePause: (json['cycle_pause'] as num?)?.toDouble() ?? 0,
        repetitions: json['repetitions'] as int? ?? 1,
        leftFunction: json['left_function'] as String? ?? '',
        pauseSeconds: (json['pause_seconds'] as num?)?.toDouble() ?? 0,
        rightFunction: json['right_function'] as String? ?? '',
        durationSeconds:
            (json['duration_seconds'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'hot_pwm': hotPwm,
        'cold_pwm': coldPwm,
        'cycle_pause': cyclePause,
        'repetitions': repetitions,
        'left_function': leftFunction,
        'pause_seconds': pauseSeconds,
        'right_function': rightFunction,
        'duration_seconds': durationSeconds,
      };
}
