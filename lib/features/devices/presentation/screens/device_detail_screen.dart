import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';

class DeviceDetailScreen extends ConsumerWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Fetch device details from DB and API
    return Scaffold(
      appBar: AppBar(title: const Text('Device Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(Icons.bluetooth, size: 80,
                  color: ThemeConstants.primaryColor),
            ),
            const SizedBox(height: ThemeConstants.spacingLg),
            _DetailTile(title: 'Device ID', value: deviceId),
            _DetailTile(title: 'Name', value: 'Hydrawav3 Device'),
            _DetailTile(title: 'MAC Address', value: 'AA:BB:CC:DD:EE:FF'),
            _DetailTile(title: 'Firmware', value: 'v1.0.0'),
            _DetailTile(title: 'Warranty', value: 'Active until Dec 2027'),
            _DetailTile(title: 'Status', value: 'Connected'),
            const SizedBox(height: ThemeConstants.spacingLg),
            HwButton(
              label: 'Rename Device',
              icon: Icons.edit,
              isOutlined: true,
              onPressed: () {
                // TODO: Show rename dialog
              },
            ),
            const SizedBox(height: ThemeConstants.spacingSm),
            HwButton(
              label: 'Forget Device',
              icon: Icons.delete_outline,
              backgroundColor: ThemeConstants.error,
              onPressed: () {
                // TODO: Remove from paired devices
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String title;
  final String value;

  const _DetailTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConstants.spacingSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
