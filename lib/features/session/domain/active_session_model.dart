class ActiveSession {
  final String id;
  final String protocolId;
  final String protocolName;
  final List<String> deviceIds;
  final String transport; // 'ble' or 'wifi'
  final DateTime createdAt;
  final SessionStatus status;
  final Map<String, SessionStatus> deviceStatuses;
  final Map<String, String> deviceNames;
  final int totalDurationSeconds;
  final int elapsedSeconds;

  /// Per-device Protocol Plus bindings (serverSessionId / serverDeviceId /
  /// plusId / localMac) needed to re-attach the socket and stop the server-side
  /// schedule when the session is re-opened from history. Empty for normal runs.
  final List<Map<String, String>> protocolPlusBindings;

  const ActiveSession({
    required this.id,
    required this.protocolId,
    required this.protocolName,
    required this.deviceIds,
    required this.transport,
    required this.createdAt,
    required this.status,
    this.deviceStatuses = const {},
    this.deviceNames = const {},
    this.totalDurationSeconds = 0,
    this.elapsedSeconds = 0,
    this.protocolPlusBindings = const [],
  });

  ActiveSession copyWith({
    String? id,
    String? protocolId,
    String? protocolName,
    List<String>? deviceIds,
    String? transport,
    DateTime? createdAt,
    SessionStatus? status,
    Map<String, SessionStatus>? deviceStatuses,
    Map<String, String>? deviceNames,
    int? totalDurationSeconds,
    int? elapsedSeconds,
    List<Map<String, String>>? protocolPlusBindings,
  }) {
    return ActiveSession(
      id: id ?? this.id,
      protocolId: protocolId ?? this.protocolId,
      protocolName: protocolName ?? this.protocolName,
      deviceIds: deviceIds ?? this.deviceIds,
      transport: transport ?? this.transport,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      deviceStatuses: deviceStatuses ?? this.deviceStatuses,
      deviceNames: deviceNames ?? this.deviceNames,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      protocolPlusBindings: protocolPlusBindings ?? this.protocolPlusBindings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocolId': protocolId,
      'protocolName': protocolName,
      'deviceIds': deviceIds,
      'transport': transport,
      'createdAt': createdAt.toIso8601String(),
      'status': status.toString(),
      'deviceStatuses': deviceStatuses.map((k, v) => MapEntry(k, v.toString())),
      'deviceNames': deviceNames,
      'totalDurationSeconds': totalDurationSeconds,
      'elapsedSeconds': elapsedSeconds,
      'protocolPlusBindings': protocolPlusBindings,
    };
  }

  factory ActiveSession.fromJson(Map<String, dynamic> json) {
    return ActiveSession(
      id: json['id'] as String,
      protocolId: json['protocolId'] as String,
      protocolName: json['protocolName'] as String,
      deviceIds: (json['deviceIds'] as List<dynamic>).cast<String>(),
      transport: json['transport'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: SessionStatus.values.firstWhere(
        (s) => s.toString() == json['status'],
        orElse: () => SessionStatus.idle,
      ),
      deviceStatuses: (json['deviceStatuses'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(
              k,
              SessionStatus.values.firstWhere(
                (s) => s.toString() == v,
                orElse: () => SessionStatus.idle,
              ),
            ),
          ) ??
          {},
      deviceNames: Map<String, String>.from(json['deviceNames'] ?? {}),
      totalDurationSeconds: json['totalDurationSeconds'] as int? ?? 0,
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
      protocolPlusBindings: (json['protocolPlusBindings'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          const [],
    );
  }

  List<Object?> get props => [
        id,
        protocolId,
        protocolName,
        deviceIds,
        transport,
        createdAt,
        status,
        deviceStatuses,
        deviceNames,
        totalDurationSeconds,
        elapsedSeconds,
        protocolPlusBindings,
      ];
}

enum SessionStatus { idle, running, paused, stopped, completed }
