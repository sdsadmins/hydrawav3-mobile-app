/// One warranty line item, as `GET warranty/:orgId` returns per feature/
/// coverage entry within a record — `{title, description}`.
class WarrantyDetail {
  final String title;
  final String description;

  const WarrantyDetail({this.title = '', this.description = ''});

  factory WarrantyDetail.fromJson(Map<String, dynamic> json) => WarrantyDetail(
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
      );
}

/// A device's warranty status, `GET warranty/:orgId` — one entry per sensor.
class WarrantyRecord {
  final int sensorId;
  final String macAddress;
  final String deviceName;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Raw status from the backend — `NO_WARRANTY`, `ACTIVE`, and whatever else
  /// it sends (e.g. an expired one). No enum: the wording/tone mapping in
  /// [WarrantyScreen] falls back to a neutral pill for anything unrecognized,
  /// so a new backend status never renders as a crash or a blank pill.
  final String status;
  final bool isActive;
  final String? product;
  final String? edition;
  final int? warrantyDurationMonths;
  final List<WarrantyDetail> features;
  final List<WarrantyDetail> coverage;

  const WarrantyRecord({
    required this.sensorId,
    required this.macAddress,
    required this.deviceName,
    this.startDate,
    this.endDate,
    required this.status,
    required this.isActive,
    this.product,
    this.edition,
    this.warrantyDurationMonths,
    this.features = const [],
    this.coverage = const [],
  });

  factory WarrantyRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
    List<WarrantyDetail> parseDetails(dynamic v) => v is List
        ? v
            .whereType<Map>()
            .map((e) => WarrantyDetail.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const [];

    return WarrantyRecord(
      sensorId: (json['sensorId'] as num?)?.toInt() ?? 0,
      macAddress: (json['macAddress'] ?? '').toString(),
      deviceName: (json['deviceName'] ?? '').toString(),
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      status: (json['status'] ?? '').toString(),
      isActive: json['isActive'] == true,
      product: (json['product'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['product'] as String,
      edition: (json['edition'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['edition'] as String,
      warrantyDurationMonths: (json['warrantyDurationMonths'] as num?)?.toInt(),
      features: parseDetails(json['features']),
      coverage: parseDetails(json['coverage']),
    );
  }
}
