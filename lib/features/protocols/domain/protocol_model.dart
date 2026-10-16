import 'dart:math';

/// One preset answer option for a post-session question: the answer text plus
/// its admin-assigned [rank] (1–5). The backend stores options as objects
/// (`answers: [{answer, rank}]`) and REQUIRES the rank back on the submitted
/// intake, so the rank must be carried through — not just the answer string.
class ProtocolAnswerOption {
  final String answer;
  final int rank;

  const ProtocolAnswerOption({required this.answer, this.rank = 0});

  Map<String, dynamic> toJson() => {'answer': answer, 'rank': rank};

  /// Parse one option. [index] is the option's position, used as the rank
  /// fallback (`i + 1`) for a plain-string option or a missing rank — matching
  /// the web (`rank = a.rank ?? i + 1`).
  factory ProtocolAnswerOption.fromJson(dynamic raw, int index) {
    if (raw is Map) {
      final rank = (raw['rank'] as num?)?.toInt() ?? (index + 1);
      return ProtocolAnswerOption(
        answer: (raw['answer'] ?? '').toString().trim(),
        rank: rank,
      );
    }
    return ProtocolAnswerOption(
      answer: (raw ?? '').toString().trim(),
      rank: index + 1,
    );
  }
}

/// An admin-defined post-session question and its preset answer options
/// (web parity: `protocol.questions[] = { question, answers: [{answer, rank}] }`).
/// [answers] is empty when the question is free-text.
class ProtocolQuestion {
  final String text;
  final List<ProtocolAnswerOption> answers;

  const ProtocolQuestion({required this.text, this.answers = const []});

  Map<String, dynamic> toJson() =>
      {'question': text, 'answers': answers.map((a) => a.toJson()).toList()};

  factory ProtocolQuestion.fromJson(Map<String, dynamic> j) {
    final rawAnswers = j['answers'];
    final answers = <ProtocolAnswerOption>[];
    if (rawAnswers is List) {
      for (var i = 0; i < rawAnswers.length; i++) {
        final opt = ProtocolAnswerOption.fromJson(rawAnswers[i], i);
        if (opt.answer.isNotEmpty) answers.add(opt);
      }
    }
    return ProtocolQuestion(
      text: (j['question'] ?? j['text'] ?? '').toString().trim(),
      answers: answers,
    );
  }

  /// The rank of the option whose answer matches [answer], or null when there's
  /// no match (e.g. a free-text response). Mirrors the web's `matched?.rank`.
  int? rankForAnswer(String answer) {
    for (final o in answers) {
      if (o.answer == answer) return o.rank;
    }
    return null;
  }
}

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

  /// Whether this protocol is unlocked by the org's current plan. The backend
  /// sets this on the protocol-list endpoints (`active = product.protocols
  /// .includes(_id)`). Locked protocols are shown disabled (web parity).
  final bool active;

  /// Admin-defined post-session questions asked after this protocol runs
  /// (web parity: `protocol.questions[]`). Empty when none configured.
  final List<ProtocolQuestion> questions;

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
    this.active = true,
    this.questions = const [],
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
      // Plan gating: backend sets `active` per protocol. Default true so a
      // protocol is usable when the field is absent (matches the backend's
      // regular-protocol default).
      active: data['active'] as bool? ?? true,
      questions: _parseQuestions(data),
    );
  }

  /// Parse admin-defined post-session questions. Tolerant of the web shape
  /// (`[{question, answers}]`) and a plain `[String]` list; trims, drops blanks,
  /// and de-dupes by question text while preserving order.
  static List<ProtocolQuestion> _parseQuestions(Map<String, dynamic> data) {
    final raw = data['questions'];
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <ProtocolQuestion>[];
    for (final item in raw) {
      ProtocolQuestion? q;
      if (item is String) {
        final t = item.trim();
        if (t.isNotEmpty) q = ProtocolQuestion(text: t);
      } else if (item is Map) {
        q = ProtocolQuestion.fromJson(Map<String, dynamic>.from(item));
      }
      if (q != null && q.text.isNotEmpty && seen.add(q.text)) out.add(q);
    }
    return out;
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
    List<ProtocolQuestion>? questions,
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
      active: active,
      questions: questions ?? this.questions,
    );
  }

  /// Total duration in seconds across all cycles and sessions.
  ///
  /// This mirrors the firmware payload calculation used by the web flow, so the
  /// selected protocol / session preview shows the same runtime the device will
  /// actually execute.
  ///
  /// The device-side payload logic is:
  /// - start-edge cycle: add `edgeCycleDuration + 30` when `cycle1`
  /// - for each session, sum the first 3 cycles using
  ///   `reps * duration + (reps - 1) * pause` and the inter-cycle pause between
  ///   cycle blocks
  /// - add session pause between sessions
  /// - finish-edge cycle: add `sessionPause + edgeCycleDuration` when `cycle5`
  ///   (matches the backend's buildPadTimeline — this is the protocol's own
  ///   sessionPause, not a fixed 30s)
  ///
  /// Protocol Plus entries do not carry cycles, so those still fall back to the
  /// server-provided `apiTotalDurationSeconds`.
  int get totalDurationSeconds {
    // Protocol Plus entries (and the goal-tag list) carry a server-computed
    // total and have no cycles — use it directly so they don't read 00:00.
    if (cycles.isEmpty && apiTotalDurationSeconds > 0) {
      return apiTotalDurationSeconds;
    }

    if (cycles.length < 3) {
      return apiTotalDurationSeconds > 0 ? apiTotalDurationSeconds : 0;
    }

    int total = 0;

    if (cycle1) {
      total += edgecycleduration.toInt() + 30;
    }

    for (var session = 0; session < sessions; session++) {
      for (var i = 0; i < 3; i++) {
        final cycle = cycles[i];
        final reps = max(1, cycle.repetitions);
        total += reps * cycle.durationSeconds.toInt();
        total += (reps - 1) * cycle.pauseSeconds.toInt();

        if (i < 2) {
          total += cycle.cyclePause.toInt();
        }
      }

      if (session < sessions - 1) {
        total += sessionPause.toInt();
      }
    }

    if (cycle5) {
      // Matches the backend's buildPadTimeline (session.service.ts) and
      // SessionEngine._computeFirmwareTotalDurationSeconds: the trailing
      // edge cycle's lead-in pause is this protocol's own sessionPause, not
      // a fixed 30s — kept in sync with those so every duration prediction
      // in the app agrees with what the real device actually runs.
      total += sessionPause.toInt() + edgecycleduration.toInt();
    }

    return total;
  }

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
}

class ProtocolSelectionOption {
  final String id;
  final String templateName;
  final String description;
  final String? goalTagName;
  final int? durationSeconds;

  /// Whether this protocol is unlocked by the org's current plan (web parity).
  final bool active;

  const ProtocolSelectionOption({
    required this.id,
    required this.templateName,
    this.description = '',
    this.goalTagName,
    this.durationSeconds,
    this.active = true,
  });

  factory ProtocolSelectionOption.fromProtocol(Protocol protocol) {
    return ProtocolSelectionOption(
      id: protocol.id,
      templateName: protocol.templateName,
      description: protocol.description,
      durationSeconds: protocol.totalDurationSeconds,
      active: protocol.active,
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
      active: data['active'] as bool? ?? true,
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
