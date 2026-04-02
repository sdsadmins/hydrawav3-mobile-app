import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';

/// Demo device data for when DB is unavailable
class _DemoDevice {
  final String id;
  final String name;
  final String mac;
  final String version;
  _DemoDevice(this.id, this.name, this.mac, this.version);
}

final _demoDevices = [
  _DemoDevice('d1', 'Hydrawav3 Pro - AI', 'A4:C1:38:XX:XX:01', 'v1.0.2'),
  _DemoDevice('d2', 'Hydrawav3 Mini - B2', 'A4:C1:38:XX:XX:02', 'v1.1.5'),
  _DemoDevice('d3', 'Hydrawav3 Pro - C3', 'A4:C1:38:XX:XX:03', 'v1.2.1'),
];

final deviceListProvider = FutureProvider<List<_DemoDevice>>((ref) async {
  // In production, this reads from BLE + DB. For demo/web, return demo data.
  try {
    // Try DB — will fail on web
    final db = await ref.read(
      // ignore: avoid_dynamic_calls
      Provider<dynamic>((ref) => null),
    );
    return _demoDevices; // fallback
  } catch (_) {
    return _demoDevices;
  }
});

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _demoDevices; // always show demo for now

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('AVAILABLE DEVICES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
          ),
          ...devices.map((device) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DeviceTile(device: device),
          )),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('SCAN FOR DEVICES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning for nearby Hydrawav3 devices...')));
              },
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
              label: const Text('Scan for Devices'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final _DemoDevice device;
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
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bluetooth_rounded, color: ThemeConstants.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(device.mac, style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: ThemeConstants.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                        child: Text(device.version, style: const TextStyle(fontSize: 10, color: ThemeConstants.textSecondary)),
                      ),
                    ]),
                  ],
                ),
              ),
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
