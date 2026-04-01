import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum BleConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class BleDeviceInfo {
  final String id;
  final String name;
  final String macAddress;
  final int? rssi;
  final BleConnectionStatus status;
  final BluetoothDevice? nativeDevice;
  final bool autoReconnect;
  final DateTime? lastConnected;

  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.macAddress,
    this.rssi,
    this.status = BleConnectionStatus.disconnected,
    this.nativeDevice,
    this.autoReconnect = true,
    this.lastConnected,
  });

  BleDeviceInfo copyWith({
    String? id,
    String? name,
    String? macAddress,
    int? rssi,
    BleConnectionStatus? status,
    BluetoothDevice? nativeDevice,
    bool? autoReconnect,
    DateTime? lastConnected,
  }) {
    return BleDeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      macAddress: macAddress ?? this.macAddress,
      rssi: rssi ?? this.rssi,
      status: status ?? this.status,
      nativeDevice: nativeDevice ?? this.nativeDevice,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  bool get isConnected => status == BleConnectionStatus.connected;
}
