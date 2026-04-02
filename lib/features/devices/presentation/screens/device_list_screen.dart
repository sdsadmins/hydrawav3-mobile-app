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
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(icon: const Icon(Icons.bluetooth_searching_rounded, color: ThemeConstants.accent), onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning for devices...')));
          }),
          IconButton(icon: const Icon(Icons.add_rounded, color: ThemeConstants.accent), onPressed: () => context.push(RoutePaths.deviceRegister)),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const HwLoading(message: 'Loading devices...'),
        error: (e, _) => HwErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(pairedDevicesProvider)),
        data: (devices) {
          if (devices.isEmpty) {
            return HwEmptyState(
              icon: Icons.bluetooth_disabled_rounded,
              title: 'No Devices Found',
              subtitle: 'Scan for nearby devices or register manually.',
              action: ElevatedButton.icon(
                onPressed: () => context.push(RoutePaths.deviceRegister),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Register Device'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Section header
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('AVAILABLE DEVICES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
              ),
              // Device list — matching reference design
              ...devices.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DeviceTile(device: device),
              )),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final PairedDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeConstants.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/devices/${device.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeConstants.border),
          ),
          child: Row(
            children: [
              // BLE icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bluetooth_rounded, color: ThemeConstants.accent, size: 20),
              ),
              const SizedBox(width: 14),
              // Name + MAC
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(device.macAddress, style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: ThemeConstants.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                          child: const Text('v1.0.0', style: TextStyle(fontSize: 10, color: ThemeConstants.textSecondary)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Connect button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: ThemeConstants.accent, borderRadius: BorderRadius.circular(8)),
                child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
