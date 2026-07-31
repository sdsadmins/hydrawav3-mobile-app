class SessionHistoryItem {
  final String? id;
  final String? clientId;
  final String? clientType;
  final List<HistoryProtocol> protocols;
  final List<HistoryDiscomfort> discomfortAreas;
  final String? sessionNotes;
  final DateTime? createdAt;
  final String? createdBy;

  const SessionHistoryItem({
    this.id,
    this.clientId,
    this.clientType,
    this.createdBy,
    this.protocols = const [],
    this.discomfortAreas = const [],
    this.sessionNotes,
    this.createdAt,
  });

  bool get isGuest => (clientType ?? '').toLowerCase() == 'guest';

  factory SessionHistoryItem.fromJson(Map<String, dynamic> json) {
    return SessionHistoryItem(
      id: json['_id'] as String? ?? json['id'] as String?,
      clientId: json['clientId'] as String?,
      clientType: json['clientType'] as String?,
      protocols: (json['protocols'] as List<dynamic>?)
              ?.map((e) => HistoryProtocol.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      discomfortAreas: (json['discomfortAreas'] as List<dynamic>?)
              ?.map(
                  (e) => HistoryDiscomfort.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sessionNotes: json['sessionNotes'] as String?,
      createdBy: json['createdBy']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

class HistoryProtocol {
  final String? bodyPart;
  final String? protocol;
  final int? duration;
  final String? deviceName;

  /// The post-session outcome check, as answered on the outcomes sheet and
  /// POSTed inside `protocols[].questionAnswers`. This — not the discomfort
  /// scores — is what the outcomes sheet actually collects, so it's the only
  /// source the history row can read an outcome from.
  final List<HistoryQuestionAnswer> questionAnswers;

  const HistoryProtocol({
    this.bodyPart,
    this.protocol,
    this.duration,
    this.deviceName,
    this.questionAnswers = const [],
  });

  factory HistoryProtocol.fromJson(Map<String, dynamic> json) {
    return HistoryProtocol(
      bodyPart: json['bodyPart'] as String?,
      protocol: json['protocol'] as String?,
      duration: json['duration'] as int?,
      deviceName: json['deviceName'] as String?,
      questionAnswers: (json['questionAnswers'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => HistoryQuestionAnswer.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }
}

/// One answered outcome-check question logged against a protocol.
class HistoryQuestionAnswer {
  final String question;
  final String answer;

  /// 1–5 for a preset answer (higher = better outcome), 0 for free text.
  final int rank;

  const HistoryQuestionAnswer({
    required this.question,
    required this.answer,
    this.rank = 0,
  });

  factory HistoryQuestionAnswer.fromJson(Map<String, dynamic> json) {
    return HistoryQuestionAnswer(
      question: (json['question'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
      rank: (json['rank'] as num?)?.toInt() ?? 0,
    );
  }
}

class HistoryDiscomfort {
  final String? bodyPart;
  final String? side;
  final int? discomfortBefore;
  final int? discomfortAfter;
  final String? behavior;
  final String? notes;

  const HistoryDiscomfort({
    this.bodyPart,
    this.side,
    this.discomfortBefore,
    this.discomfortAfter,
    this.behavior,
    this.notes,
  });

  factory HistoryDiscomfort.fromJson(Map<String, dynamic> json) {
    return HistoryDiscomfort(
      bodyPart:
          json['discompfortbodyPart'] as String? ?? json['bodyPart'] as String?,
      side: json['side'] as String?,
      discomfortBefore: json['discomfortBefore'] as int?,
      discomfortAfter: json['discomfortAfter'] as int?,
      behavior: json['behavior'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class DashboardStats {
  final int totalSessions;
  final int totalClients;
  final Map<String, dynamic> raw;

  const DashboardStats({
    this.totalSessions = 0,
    this.totalClients = 0,
    this.raw = const {},
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalSessions: json['totalSessions'] as int? ?? 0,
      totalClients: json['totalClients'] as int? ?? 0,
      raw: json,
    );
  }
}
