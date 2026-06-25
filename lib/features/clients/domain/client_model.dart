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
  });

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
    );
  }
}

/// Body for `POST /clients` (`CreateClientDto`). `age`, `height`, `weight`,
/// `organizationId` and `organizationName` are required server-side.
class CreateClientRequest {
  final int age;
  final double height; // cm
  final double weight; // kg
  final int organizationId;
  final String organizationName;
  final String? clientName;
  final String? nickname;
  final String? gender;
  final String? phone;

  const CreateClientRequest({
    required this.age,
    required this.height,
    required this.weight,
    required this.organizationId,
    required this.organizationName,
    this.clientName,
    this.nickname,
    this.gender,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'height': height,
        'weight': weight,
        'organizationId': organizationId,
        'organizationName': organizationName,
        if (clientName != null && clientName!.trim().isNotEmpty)
          'clientName': clientName,
        if (nickname != null && nickname!.trim().isNotEmpty)
          'nickname': nickname,
        if (gender != null && gender!.trim().isNotEmpty) 'gender': gender,
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone,
      };
}
