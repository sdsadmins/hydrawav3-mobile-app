class DeviceInfo {
  final String? id;
  final String name;
  final String macAddress;
  final List<int> organizationIds;
  final String? firmware;
  final String? warrantyStatus;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DeviceInfo({
    this.id,
    required this.name,
    required this.macAddress,
    this.organizationIds = const [],
    this.firmware,
    this.warrantyStatus,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id']?.toString(),
        name: json['name'] as String? ?? 'Unknown',
        macAddress: json['macAddress'] as String? ?? '',
        organizationIds: (json['organizationIds'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        firmware: json['firmware'] as String?,
        warrantyStatus: json['warrantyStatus'] as String?,
        status: json['status'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'macAddress': macAddress,
        'organizationIds': organizationIds,
      };
}
