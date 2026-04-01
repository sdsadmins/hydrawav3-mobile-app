import 'dart:convert';

import '../../../core/constants/ble_constants.dart';

enum CommandType { start, pause, resume, stop }

class BleCommand {
  final String macAddress;
  final CommandType type;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  BleCommand({
    required this.macAddress,
    required this.type,
    this.payload,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get playCmd => switch (type) {
        CommandType.start => BleConstants.cmdResume,
        CommandType.pause => BleConstants.cmdPause,
        CommandType.resume => BleConstants.cmdResume,
        CommandType.stop => BleConstants.cmdStop,
      };

  /// JSON for HTTP fallback (send_treatment2.php)
  Map<String, dynamic> toHttpPayload() => {
        'mac': macAddress,
        'playCmd': playCmd,
        if (payload != null) 'payload': payload,
      };

  /// JSON for MQTT fallback
  Map<String, dynamic> toMqttPayload() => {
        'topic': 'HydraWav3Pro/config',
        'payload': jsonEncode({
          'mac': macAddress,
          'playCmd': playCmd,
          ...?payload,
        }),
      };

  /// Bytes for BLE characteristic write
  List<int> toBytes() {
    final json = jsonEncode({
      'playCmd': playCmd,
      ...?payload,
    });
    return utf8.encode(json);
  }

  String toJson() => jsonEncode({
        'macAddress': macAddress,
        'type': type.name,
        'playCmd': playCmd,
        'payload': payload,
      });

  factory BleCommand.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return BleCommand(
      macAddress: map['macAddress'] as String,
      type: CommandType.values.byName(map['type'] as String),
      payload: map['payload'] as Map<String, dynamic>?,
    );
  }
}
