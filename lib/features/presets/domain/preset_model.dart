import '../../advanced_settings/domain/advanced_settings_model.dart';

class PresetData {
  final String id;
  final String name;
  final List<String> deviceIds;
  final String protocolId;
  final AdvancedSettings advancedSettings;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PresetData({
    required this.id,
    required this.name,
    this.deviceIds = const [],
    required this.protocolId,
    this.advancedSettings = const AdvancedSettings(),
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });
}
