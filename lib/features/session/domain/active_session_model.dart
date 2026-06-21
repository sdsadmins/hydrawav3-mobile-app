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

  /// Per-device live state sourced from the BACKEND (active-sessions feed /
  /// SESSION_UPDATED): timer + sun/moon pad state. Populated for sessions read
  /// from the org-wide live feed; empty for purely-local view models. The app
  /// renders these values verbatim and does not compute timing or pad state.
  final List<LiveDeviceState> liveDevices;

  /// True when this phone owns the live run (it has the local engine driving
  /// the hardware). False for sessions started on the web or another phone —
  /// those are foreign and may be read-only (BLE) or remote-controllable (WiFi).
  final bool isOwn;

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
    this.liveDevices = const [],
    this.isOwn = true,
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
    List<LiveDeviceState>? liveDevices,
    bool? isOwn,
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
      liveDevices: liveDevices ?? this.liveDevices,
      isOwn: isOwn ?? this.isOwn,
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
        liveDevices,
        isOwn,
      ];
}

/// Per-device live state as reported by the backend (active-sessions feed /
/// SESSION_UPDATED). Timing and pad (sun/moon) are taken verbatim — never
/// computed on-device.
class LiveDeviceState {
  /// Device address — Wi-Fi macAddress or BLE bluetoothId, as the backend keys.
  final String deviceId;
  final String? deviceName;
  final String? bodyPart;
  final String? protocol;
  final String? slotId;
  final SessionStatus status;
  final int remainingSeconds;
  final int elapsedSeconds;
  final int totalDurationSeconds;
  final String? sun;
  final String? moon;

  /// 'ble' or 'wifi', inferred from whether the backend reported a bluetoothId.
  final String transport;

  const LiveDeviceState({
    required this.deviceId,
    this.deviceName,
    this.bodyPart,
    this.protocol,
    this.slotId,
    this.status = SessionStatus.running,
    this.remainingSeconds = 0,
    this.elapsedSeconds = 0,
    this.totalDurationSeconds = 0,
    this.sun,
    this.moon,
    this.transport = 'wifi',
  });
}

enum SessionStatus { idle, running, paused, stopped, completed }
