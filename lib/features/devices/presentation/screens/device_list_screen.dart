import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';

class _DemoDevice {
  final String id, name, mac, version;
  final bool connected;
  _DemoDevice(this.id, this.name, this.mac, this.version, {this.connected = false});
}

final _devices = [
  _DemoDevice('d1', 'Hydrawav3 Pro - AI', 'A4:C1:38:XX:XX:01', 'v1.0.2', connected: true),
  _DemoDevice('d2', 'Hydrawav3 Mini - B2', 'A4:C1:38:XX:XX:02', 'v1.1.5'),
  _DemoDevice('d3', 'Hydrawav3 Pro - C3', 'A4:C1:38:XX:XX:03', 'v1.2.1'),
];

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3040), ThemeConstants.background],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: AnimatedEntrance(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Devices', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Manage your Hydrawav3 devices', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                          ],
                        ),
                        Row(children: [
                          _HeaderBtn(icon: Icons.bluetooth_searching_rounded, onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning...')));
                          }),
                          const SizedBox(width: 8),
                          _HeaderBtn(icon: Icons.add_rounded, filled: true, onTap: () => context.push(RoutePaths.deviceRegister)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Connected section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(index: 0, child: const SectionHeader(title: 'Connected')),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final d = _devices.where((d) => d.connected).toList();
                if (i >= d.length) return null;
                return AnimatedEntrance(
                  index: i + 1,
                  child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _DeviceCard(device: d[i])),
                );
              }, childCount: _devices.where((d) => d.connected).length),
            ),
          ),

          // Available section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(index: 2, child: const SectionHeader(title: 'Available')),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final d = _devices.where((d) => !d.connected).toList();
                if (i >= d.length) return null;
                return AnimatedEntrance(
                  index: i + 3,
                  child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _DeviceCard(device: d[i])),
                );
              }, childCount: _devices.where((d) => !d.connected).length),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _HeaderBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: filled ? ThemeConstants.accent : ThemeConstants.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: ThemeConstants.accent.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: filled ? Colors.white : ThemeConstants.accent, size: 20),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final _DemoDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      onTap: () => context.push('/devices/${device.id}'),
      showGlow: device.connected,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GlowIconBox(
            icon: device.connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
            color: device.connected ? ThemeConstants.success : ThemeConstants.accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(device.mac, style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(device.version, style: const TextStyle(fontSize: 10, color: ThemeConstants.textSecondary)),
                  ),
                ]),
              ],
            ),
          ),
          if (device.connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ThemeConstants.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ThemeConstants.success.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: ThemeConstants.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Connected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ThemeConstants.success)),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: ThemeConstants.accent, borderRadius: BorderRadius.circular(8)),
              child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
