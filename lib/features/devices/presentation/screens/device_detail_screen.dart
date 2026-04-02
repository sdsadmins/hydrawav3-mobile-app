import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class DeviceDetailScreen extends ConsumerWidget {
  final String deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Device Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
            child: Column(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: ThemeConstants.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.bluetooth_rounded, color: ThemeConstants.accent, size: 28),
                ),
                const SizedBox(height: 16),
                const Text('Hydrawav3 Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(deviceId, style: const TextStyle(fontSize: 13, color: ThemeConstants.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoSection(items: [
            _InfoRow('Device ID', deviceId),
            _InfoRow('Firmware', 'v1.0.0'),
            _InfoRow('Warranty', 'Active'),
            _InfoRow('Status', 'Connected'),
          ]),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Rename Device'))),
          const SizedBox(height: 10),
          SizedBox(height: 48, child: ElevatedButton.icon(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.error), icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Forget Device'))),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
      child: Column(
        children: items.asMap().entries.map((e) => Column(
          children: [
            e.value,
            if (e.key < items.length - 1) const Divider(height: 1, indent: 16, endIndent: 16, color: ThemeConstants.border),
          ],
        )).toList(),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
    );
  }
}
