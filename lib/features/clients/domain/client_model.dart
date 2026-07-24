/// A client (patient) owned by an organization. Mirrors the backend
/// `Client` schema (`Hydrawav3-Server/src/modules/client/client.schema.ts`)
/// and the web `Client` type. Height is stored in centimetres and weight in
/// kilograms (the backend is metric; the web converts only for display).
class Client {
  final String id;
  final String clientName;
  final String? nickname;
  final int? age;
  final String? gender; // Male | Female | Other
  final double? height; // cm
  final double? weight; // kg
  final String? phone;
  final int? organizationId;

  // Device-lease fields (parity with the web `Client` type + backend
  // `client.schema.ts`). A lease binds one client to one physical device.
  // `leaseId` is server-generated; `macAddress` is the firmware-reported MAC
  // (identical across web/iOS/Android — never the OS BLE identifier).
  final String? leaseId;
  final bool leaseActive;
  final String? macAddress;
  final DateTime? leaseDate;
  final bool isActive;

  // Member discriminator + player-only fields (university/sports-club orgs).
  // A "Player" is a client created with `memberType: "Player"` — it carries a
  // sport, optional jersey number, and Position ObjectIds.
  final String? memberType; // "Client" | "Player"
  final String? sport;
  final int? jerseyNumber;
  final List<String>? positions; // Position ObjectId strings

  const Client({
    required this.id,
    required this.clientName,
    this.nickname,
    this.age,
    this.gender,
    this.height,
    this.weight,
    this.phone,
    this.organizationId,
    this.leaseId,
    this.leaseActive = false,
    this.macAddress,
    this.leaseDate,
    this.isActive = false,
    this.memberType,
    this.sport,
    this.jerseyNumber,
    this.positions,
  });

  /// True for members created as players (`memberType: "Player"`).
  bool get isPlayer => (memberType ?? '').toLowerCase() == 'player';

  /// Display label: "Name - Nickname" (matches the web client picker).
  String get displayName =>
      nickname != null && nickname!.trim().isNotEmpty
          ? '$clientName - $nickname'
          : clientName;

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      clientName: (json['clientName'] ?? json['name'] ?? '').toString(),
      nickname: json['nickname']?.toString(),
      age: _toInt(json['age']),
      gender: json['gender']?.toString(),
      height: _toDouble(json['height']),
      weight: _toDouble(json['weight']),
      phone: json['phone']?.toString(),
      organizationId: _toInt(json['organizationId']),
      leaseId: json['leaseId']?.toString(),
      leaseActive: _toBool(json['leaseActive']),
      macAddress: json['macAddress']?.toString(),
      leaseDate: _toDate(json['leaseDate']),
      isActive: _toBool(json['isActive']),
      memberType: json['memberType']?.toString(),
      sport: json['sport']?.toString(),
      jerseyNumber: _toInt(json['jerseyNumber']),
      positions: json['positions'] is List
          ? (json['positions'] as List).map((e) => e.toString()).toList()
          : null,
    );
  }

  /// The lease is fully live on both the server and the device.
  bool get isLeaseActive => leaseActive;

  /// A lease has been registered (server issued a `leaseId` + MAC) but has not
  /// yet been loaded onto / confirmed by the device (web "Pending" state).
  bool get isLeasePending =>
      !leaseActive &&
      (leaseId != null && leaseId!.isNotEmpty) &&
      (macAddress != null && macAddress!.isNotEmpty);

  Client copyWith({
    String? leaseId,
    bool? leaseActive,
    String? macAddress,
    DateTime? leaseDate,
    bool? isActive,
  }) {
    return Client(
      id: id,
      clientName: clientName,
      nickname: nickname,
      age: age,
      gender: gender,
      height: height,
      weight: weight,
      phone: phone,
      organizationId: organizationId,
      leaseId: leaseId ?? this.leaseId,
      leaseActive: leaseActive ?? this.leaseActive,
      macAddress: macAddress ?? this.macAddress,
      leaseDate: leaseDate ?? this.leaseDate,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Body for `POST /clients` (`CreateClientDto`). The `memberType` discriminator
/// selects a **clinic Client** (omit / "Client": `clientName` is auto-generated,
/// `organizationName` builds it) or a **Player** (`memberType: "Player"`:
/// `clientName` + `sport` required, `positions` are Position ObjectIds).
class CreateClientRequest {
  final int age;
  final double height; // cm
  final double weight; // kg
  final int organizationId;
  final String? memberType; // null / "Client" | "Player"
  final String? organizationName; // clinic only (builds the auto name)
  final String? clientName; // auto for clinic; required + stored as-is for player
  final String? nickname;
  final String? gender;
  final String? phone;
  final String? primaryPractitioner; // clinic only
  final String? sport; // player only (sport name)
  final int? jerseyNumber; // player only
  final List<String>? positions; // player only — Position ObjectId strings

  const CreateClientRequest({
    required this.age,
    required this.height,
    required this.weight,
    required this.organizationId,
    this.memberType,
    this.organizationName,
    this.clientName,
    this.nickname,
    this.gender,
    this.phone,
    this.primaryPractitioner,
    this.sport,
    this.jerseyNumber,
    this.positions,
  });

  /// Convenience for the university Add Player flow.
  factory CreateClientRequest.player({
    required String clientName,
    required int organizationId,
    required int age,
    required double height,
    required double weight,
    required String sport,
    String? gender,
    String? nickname,
    int? jerseyNumber,
    List<String>? positions,
  }) =>
      CreateClientRequest(
        memberType: 'Player',
        clientName: clientName,
        organizationId: organizationId,
        age: age,
        height: height,
        weight: weight,
        sport: sport,
        gender: gender,
        nickname: nickname,
        jerseyNumber: jerseyNumber,
        positions: positions,
      );

  Map<String, dynamic> toJson() => {
        if (memberType != null && memberType!.trim().isNotEmpty)
          'memberType': memberType,
        'age': age,
        'height': height,
        'weight': weight,
        'organizationId': organizationId,
        if (organizationName != null && organizationName!.trim().isNotEmpty)
          'organizationName': organizationName,
        if (clientName != null && clientName!.trim().isNotEmpty)
          'clientName': clientName,
        if (nickname != null && nickname!.trim().isNotEmpty)
          'nickname': nickname,
        if (gender != null && gender!.trim().isNotEmpty) 'gender': gender,
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone,
        if (primaryPractitioner != null &&
            primaryPractitioner!.trim().isNotEmpty)
          'primaryPractitioner': primaryPractitioner,
        if (sport != null && sport!.trim().isNotEmpty) 'sport': sport,
        if (jerseyNumber != null) 'jerseyNumber': jerseyNumber,
        if (positions != null && positions!.isNotEmpty) 'positions': positions,
      };
}
