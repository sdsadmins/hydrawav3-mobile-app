import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/hw_loading.dart';

final pairedDevicesProvider = StreamProvider<List<PairedDevice>>((ref) {
  return ref.read(databaseProvider).watchPairedDevices();
});

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(pairedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: () {
              // TODO: Trigger BLE scan
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scanning for devices...')),
              );
            },
            tooltip: 'Scan for devices',
          ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const HwLoading(message: 'Loading devices...'),
        error: (error, _) => HwErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(pairedDevicesProvider),
        ),
        data: (devices) {
          if (devices.isEmpty) {
            return HwEmptyState(
              icon: Icons.bluetooth_disabled,
              title: 'No Devices Found',
              subtitle: 'Tap the scan button to discover nearby devices, or register a device manually.',
              action: ElevatedButton.icon(
                onPressed: () => context.push(RoutePaths.deviceRegister),
                icon: const Icon(Icons.add),
                label: const Text('Register Device'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(ThemeConstants.spacingMd),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSm),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth,
                      color: ThemeConstants.bleConnected),
                  title: Text(device.name),
                  subtitle: Text(device.macAddress),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: ThemeConstants.bleConnected,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: ThemeConstants.spacingSm),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => context.push('/devices/${device.id}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(RoutePaths.deviceRegister),
        child: const Icon(Icons.add),
      ),
    );
  }
}
