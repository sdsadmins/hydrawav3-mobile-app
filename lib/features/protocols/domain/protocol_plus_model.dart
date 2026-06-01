import 'protocol_model.dart';

/// A Protocol Plus template: an ordered sequence of protocols the device runs
/// back-to-back. Mirrors the Node `ProtocolPlus` schema.
///
/// `protocolIds` always holds the ordered id list. `protocols` is only filled
/// when the endpoint returns populated protocol objects (the list/detail
/// endpoints currently return ids only, so the first protocol is fetched
/// separately via the normal protocol-detail endpoint to start it locally).
class ProtocolPlus {
  final String id;
  final String templateName;
  final String description;
  final int delay;
  final int totalDuration;
  final List<String> protocolIds;
  final List<Protocol> protocols;

  const ProtocolPlus({
    required this.id,
    required this.templateName,
    this.description = '',
    this.delay = 0,
    this.totalDuration = 0,
    this.protocolIds = const [],
    this.protocols = const [],
  });

  int get protocolCount =>
      protocols.isNotEmpty ? protocols.length : protocolIds.length;

  String? get firstProtocolId =>
      protocolIds.isNotEmpty ? protocolIds.first : null;

  Duration get totalDurationFormatted => Duration(seconds: totalDuration);

  factory ProtocolPlus.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    final rawProtocols = data['protocolIds'];
    final ids = <String>[];
    final protocols = <Protocol>[];
    if (rawProtocols is List) {
      for (final item in rawProtocols) {
        if (item is String) {
          ids.add(item);
        } else if (item is Map) {
          final map = item.cast<String, dynamic>();
          final id = map['_id']?.toString() ?? map['id']?.toString();
          if (id != null && id.isNotEmpty) ids.add(id);
          // Populated protocol object (has cycles/template_name).
          if (map.containsKey('cycles') || map.containsKey('template_name')) {
            protocols.add(Protocol.fromJson(map));
          }
        }
      }
    }

    return ProtocolPlus(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      templateName: data['template_name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      delay: (data['delay'] as num?)?.toInt() ?? 0,
      totalDuration: (data['totalDuration'] as num?)?.toInt() ?? 0,
      protocolIds: ids,
      protocols: protocols,
    );
  }
}
