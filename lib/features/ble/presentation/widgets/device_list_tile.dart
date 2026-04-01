import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../domain/ble_device_model.dart';

class BleDeviceListTile extends StatelessWidget {
  final ScanResult scanResult;
  final BleConnectionStatus status;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const BleDeviceListTile({
    super.key,
    required this.scanResult,
    this.status = BleConnectionStatus.disconnected,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final device = scanResult.device;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : 'Unknown Device';
    final isConnected = status == BleConnectionStatus.connected;
    final isConnecting = status == BleConnectionStatus.connecting;

    return Card(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSm),
      child: ListTile(
        leading: Icon(
          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
          color: isConnected
              ? ThemeConstants.bleConnected
              : isConnecting
                  ? ThemeConstants.bleDiscovered
                  : ThemeConstants.bleDisconnected,
        ),
        title: Text(name),
        subtitle: Text(
          '${device.remoteId.str} | RSSI: ${scanResult.rssi}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: isConnecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isConnected
                ? TextButton(
                    onPressed: onDisconnect,
                    child: const Text('Disconnect'),
                  )
                : TextButton(
                    onPressed: onConnect,
                    child: const Text('Connect'),
                  ),
      ),
    );
  }
}

class ConnectionStatusBadge extends StatelessWidget {
  final BleConnectionStatus status;
  final double size;

  const ConnectionStatusBadge({
    super.key,
    required this.status,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BleConnectionStatus.connected => ThemeConstants.bleConnected,
      BleConnectionStatus.connecting => ThemeConstants.bleDiscovered,
      BleConnectionStatus.disconnecting => ThemeConstants.bleDiscovered,
      BleConnectionStatus.error => ThemeConstants.error,
      BleConnectionStatus.disconnected => ThemeConstants.bleDisconnected,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
