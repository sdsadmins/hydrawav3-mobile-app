class SessionHistoryItem {
  final String? id;
  final String? clientId;
  final List<HistoryProtocol> protocols;
  final List<HistoryDiscomfort> discomfortAreas;
  final String? sessionNotes;
  final DateTime? createdAt;

  const SessionHistoryItem({
    this.id,
    this.clientId,
    this.protocols = const [],
    this.discomfortAreas = const [],
    this.sessionNotes,
    this.createdAt,
  });

  factory SessionHistoryItem.fromJson(Map<String, dynamic> json) {
    return SessionHistoryItem(
      id: json['_id'] as String? ?? json['id'] as String?,
      clientId: json['clientId'] as String?,
      protocols: (json['protocols'] as List<dynamic>?)
              ?.map(
                  (e) => HistoryProtocol.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      discomfortAreas: (json['discomfortAreas'] as List<dynamic>?)
              ?.map((e) =>
                  HistoryDiscomfort.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sessionNotes: json['sessionNotes'] as String?,
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

  const HistoryProtocol({
    this.bodyPart,
    this.protocol,
    this.duration,
    this.deviceName,
  });

  factory HistoryProtocol.fromJson(Map<String, dynamic> json) {
    return HistoryProtocol(
      bodyPart: json['bodyPart'] as String?,
      protocol: json['protocol'] as String?,
      duration: json['duration'] as int?,
      deviceName: json['deviceName'] as String?,
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
      bodyPart: json['discompfortbodyPart'] as String? ??
          json['bodyPart'] as String?,
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
