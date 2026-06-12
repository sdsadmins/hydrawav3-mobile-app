class Protocol {
  final String id;
  final String templateName;
  final String? goalTagName;
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
  final String? deviceId;

  /// True when this entry is actually a Protocol Plus template (the backend
  /// merges protocol-plus docs into the protocols list / by-id endpoint).
  final bool isProtocolPlus;

  /// Ordered sub-protocol ids when [isProtocolPlus] is true.
  final List<String> protocolPlusIds;

  /// Server-computed total duration (seconds) from the backend `totalDuration`
  /// field. Protocol Plus entries carry this and have **no** `cycles`, so the
  /// cycle-based computation would return 0 for them — [totalDurationSeconds]
  /// uses this value whenever it's present.
  final int apiTotalDurationSeconds;

  const Protocol({
    required this.id,
    required this.templateName,
    this.goalTagName,
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
    this.deviceId,
    this.isProtocolPlus = false,
    this.protocolPlusIds = const [],
    this.apiTotalDurationSeconds = 0,
  });

  factory Protocol.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    return Protocol(
      id: data['_id'] as String? ?? data['id'] as String? ?? '',
      templateName: data['template_name'] as String? ?? '',
      goalTagName: _parseGoalTagName(data),
      sessions: data['sessions'] as int? ?? 1,
      cycles: (data['cycles'] as List<dynamic>?)
              ?.map((e) => ProtocolCycle.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hotdrop: (data['hotdrop'] as num?)?.toDouble() ?? 0,
      colddrop: (data['colddrop'] as num?)?.toDouble() ?? 0,
      vibmin: (data['vibmin'] as num?)?.toDouble() ?? 0,
      vibmax: (data['vibmax'] as num?)?.toDouble() ?? 0,
      cycle1: data['cycle1'] as bool? ?? false,
      cycle5: data['cycle5'] as bool? ?? false,
      // Backend/web have used multiple spellings over time.
      // Web code also checks `edgeCycleDuration ?? edgecycleduration`.
      edgecycleduration: (data['edgeCycleDuration'] as num?)?.toDouble() ??
          (data['edge_cycle_duration'] as num?)?.toDouble() ??
          (data['edgecycleduration'] as num?)?.toDouble() ??
          0,
      sessionPause: (data['session_pause'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String? ?? '',
      deviceId: _parseDeviceId(data),
      isProtocolPlus: data['protocolPlus'] as bool? ?? false,
      protocolPlusIds: _parseProtocolPlusIds(data),
      apiTotalDurationSeconds: (data['totalDuration'] as num?)?.toInt() ?? 0,
    );
  }

  static List<String> _parseProtocolPlusIds(Map<String, dynamic> data) {
    final raw = data['protocolIds'];
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final item in raw) {
      if (item is String) {
        ids.add(item);
      } else if (item is Map) {
        final id = item['_id']?.toString() ?? item['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  static String? _parseDeviceId(Map<String, dynamic> json) {
    final rawDeviceId = json['deviceId'] ??
        json['device_id'] ??
        json['firmwareDeviceId'] ??
        json['firmware_device_id'] ??
        json['firmware_id'] ??
        json['firmwareid'] ??
        json['deviceid'];
    return rawDeviceId is String ? rawDeviceId : null;
  }

  static String? _parseGoalTagName(Map<String, dynamic> json) {
    final directGoalTagName = json['goalTagName'] ?? json['goal_tag_name'];
    if (directGoalTagName is String && directGoalTagName.trim().isNotEmpty) {
      return directGoalTagName.trim();
    }

    final rawGoalTag = json['goalTag'] ?? json['goal_tag'];
    if (rawGoalTag is Map<String, dynamic>) {
      final name = rawGoalTag['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'template_name': templateName,
      if (goalTagName != null) 'goalTagName': goalTagName,
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
    if (deviceId != null) {
      data['deviceId'] = deviceId;
    }
    return data;
  }

  Protocol copyWith({
    String? goalTagName,
  }) {
    return Protocol(
      id: id,
      templateName: templateName,
      goalTagName: goalTagName ?? this.goalTagName,
      sessions: sessions,
      cycles: cycles,
      hotdrop: hotdrop,
      colddrop: colddrop,
      vibmin: vibmin,
      vibmax: vibmax,
      cycle1: cycle1,
      cycle5: cycle5,
      edgecycleduration: edgecycleduration,
      sessionPause: sessionPause,
      description: description,
      deviceId: deviceId,
      isProtocolPlus: isProtocolPlus,
      protocolPlusIds: protocolPlusIds,
      apiTotalDurationSeconds: apiTotalDurationSeconds,
    );
  }

  /// Total duration in seconds across all cycles and sessions.
  ///
  /// Mirrors the backend computation in
  /// `Hydrawav3-Server` → `protocol.service.ts` `getProtocolsByGoalTagId`
  /// (the goal-tag list `duration`, which is the source of truth) so the
  /// home / "All" protocols list matches the goal-filtered list exactly.
  ///
  /// Per cycle: `repetitions * (duration_seconds + pause_seconds)`, plus the
  /// inter-cycle pause `cycle_pause` for every cycle **except the last**.
  /// Then scaled by sessions (+ session pauses) and the start/end edge cycles
  /// (`edgecycleduration + 30` each).
  int get totalDurationSeconds {
    // Protocol Plus entries (and the goal-tag list) carry a server-computed
    // total and have no cycles — use it directly so they don't read 00:00.
    if (apiTotalDurationSeconds > 0) return apiTotalDurationSeconds;

    double base = 0;
    for (var i = 0; i < cycles.length; i++) {
      final cycle = cycles[i];
      base += cycle.repetitions * (cycle.durationSeconds + cycle.pauseSeconds);
      if (i < cycles.length - 1) {
        base += cycle.cyclePause;
      }
    }

    base = base * sessions + sessionPause * (sessions - 1);

    if (cycle1) base += edgecycleduration + 30;
    if (cycle5) base += edgecycleduration + 30;

    return base.round();
  }

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
}

class ProtocolSelectionOption {
  final String id;
  final String templateName;
  final String description;
  final String? goalTagName;
  final int? durationSeconds;

  const ProtocolSelectionOption({
    required this.id,
    required this.templateName,
    this.description = '',
    this.goalTagName,
    this.durationSeconds,
  });

  factory ProtocolSelectionOption.fromProtocol(Protocol protocol) {
    return ProtocolSelectionOption(
      id: protocol.id,
      templateName: protocol.templateName,
      description: protocol.description,
      durationSeconds: protocol.totalDurationSeconds,
    );
  }

  factory ProtocolSelectionOption.fromGoalTagJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    return ProtocolSelectionOption(
      id: data['_id'] as String? ?? data['id'] as String? ?? '',
      templateName: data['template_name'] as String? ?? '',
      goalTagName: data['goalTagName'] as String?,
      durationSeconds: (data['duration'] as num?)?.toInt(),
    );
  }

  Duration? get totalDuration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);
}

class GoalTagOption {
  final String id;
  final String name;
  final bool isActive;

  const GoalTagOption({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory GoalTagOption.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    return GoalTagOption(
      id: data['_id'] as String? ?? data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
    );
  }
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
        durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
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
