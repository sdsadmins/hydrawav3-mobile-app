import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../ble/presentation/providers/ble_scan_provider.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/session_target_provider.dart';

final pairedDevicesProvider = StreamProvider((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairedDevices = ref.watch(pairedDevicesProvider);
    final target = ref.watch(sessionTargetProvider);
    final wifiAsync = ref.watch(wifiDevicesByOrgProvider);
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
                            Text('Devices',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Manage your Hydrawav3 devices',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: ThemeConstants.textSecondary)),
                          ],
                        ),
                        Row(children: [
                          _HeaderBtn(
                              icon: Icons.add_rounded,
                              filled: true,
                              onTap: () =>
                                  context.push(RoutePaths.deviceRegister)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Transport toggle + continue button
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 0,
                child: GradientCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transport',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ToggleButtons(
                        isSelected: [
                          target.transport == SessionTransport.wifi,
                          target.transport == SessionTransport.ble,
                        ],
                        onPressed: (idx) {
                          final transport = idx == 0
                              ? SessionTransport.wifi
                              : SessionTransport.ble;
                          ref
                              .read(sessionTargetProvider.notifier)
                              .setTransport(transport);
                          // Start scan automatically when Bluetooth is selected
                          if (idx == 1) {
                            Future.delayed(const Duration(milliseconds: 100),
                                () {
                              ref.read(startScanProvider)();
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        selectedColor: Colors.white,
                        fillColor:
                            ThemeConstants.accent.withValues(alpha: 0.18),
                        color: ThemeConstants.textSecondary,
                        constraints: const BoxConstraints(minHeight: 42),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Icon(Icons.wifi_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('WiFi'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Icon(Icons.bluetooth_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Bluetooth'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${target.deviceIds.length} selected',
                            style: const TextStyle(
                              fontSize: 12,
                              color: ThemeConstants.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: target.deviceIds.isEmpty
                                ? null
                                : () => context.go(RoutePaths.protocols),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: target.deviceIds.isEmpty
                                    ? ThemeConstants.surfaceVariant
                                    : ThemeConstants.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Continue to Protocols',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Display device types based on transport selection

          // === WiFi DEVICES SECTION (only when WiFi selected) ===
          if (target.transport == SessionTransport.wifi) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  index: 0,
                  child: SectionHeader(title: 'WiFi Devices'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: wifiAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Failed to load WiFi devices: $e',
                      style: const TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          'No WiFi devices found for your organization.',
                          style: TextStyle(
                            fontSize: 13,
                            color: ThemeConstants.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final d = list[i];
                        final selected =
                            target.deviceIds.contains(d.macAddress);
                        return AnimatedEntrance(
                          index: i + 1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WifiDeviceCard(
                              device: d,
                              selected: selected,
                              onTap: () => ref
                                  .read(sessionTargetProvider.notifier)
                                  .toggleDevice(d.macAddress),
                            ),
                          ),
                        );
                      },
                      childCount: list.length,
                    ),
                  );
                },
              ),
            ),
          ],

          // === BLUETOOTH DEVICES SECTION (only when Bluetooth selected) ===
          if (target.transport == SessionTransport.ble) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Bluetooth Devices'),
                    const SizedBox(height: 12),
                    // Scan button - always visible
                    GestureDetector(
                      onTap: () => ref.read(startScanProvider)(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: ThemeConstants.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.bluetooth_searching_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Scan for Devices',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // BLE Device List - Connected and Available
            pairedDevices.when(
              data: (devices) {
                final scanResults = ref.watch(bleScanResultsProvider);
                final connectedDevices = devices
                    .where((d) =>
                        ref.watch(bleDeviceStatusProvider(d.macAddress)) ==
                        BleConnectionStatus.connected)
                    .toList();

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Connected section
                      if (connectedDevices.isNotEmpty) ...[
                        const SectionHeader(title: 'Connected')
                      ],
                      ...connectedDevices.map((d) {
                        final selected =
                            target.deviceIds.contains(d.macAddress);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ConnectedDeviceCard(
                            name: d.name,
                            macAddress: d.macAddress,
                            selected: selected,
                            onSelect: () => ref
                                .read(sessionTargetProvider.notifier)
                                .toggleDevice(d.macAddress),
                            onDisconnect: () async {
                              await ref
                                  .read(bleRepositoryProvider)
                                  .disconnectDevice(d.macAddress);
                            },
                          ),
                        );
                      }).toList(),
                      if (connectedDevices.isNotEmpty)
                        const SizedBox(height: 8),
                      const SectionHeader(title: 'Available'),
                      // Scan results
                      scanResults.when(
                        data: (list) {
                          if (list.isEmpty) return const SizedBox(height: 0);
                          final byId = <String, ScanResult>{};
                          final sorted = [...list]
                            ..sort((a, b) => (b.rssi).compareTo(a.rssi));
                          for (final r in sorted) {
                            byId.putIfAbsent(r.device.remoteId.str, () => r);
                          }
                          final deduped = byId.values.toList();
                          return Column(
                            children: deduped.asMap().entries.map((entry) {
                              final i = entry.key;
                              final r = entry.value;
                              final name = r.device.platformName.isNotEmpty
                                  ? r.device.platformName
                                  : 'Unknown';
                              final id = r.device.remoteId.str;
                              return AnimatedEntrance(
                                index: i + 1,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AvailableBleDeviceCard(
                                    name: name,
                                    id: id,
                                    rssi: r.rssi,
                                    onConnect: () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final ok = await ref
                                          .read(bleRepositoryProvider)
                                          .connectDevice(r.device);

                                      // CRITICAL FIX: Allow database stream and connection state
                                      // stream to propagate before showing snackbar and allowing UI rebuild.
                                      // Without this delay, the device appears connected but the card
                                      // doesn't appear in the "Connected" section immediately.
                                      if (ok) {
                                        await Future<void>.delayed(
                                          const Duration(milliseconds: 150),
                                        );
                                      }

                                      if (!context.mounted) return;
                                      messenger.showSnackBar(SnackBar(
                                          content: Text(ok
                                              ? 'Connected to $name'
                                              : 'Failed to connect to $name')));
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('Scan error: $e',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: ThemeConstants.textSecondary)),
                        ),
                      ),
                    ]),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
              error: (e, _) => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Failed to load paired devices',
                    style: TextStyle(
                      fontSize: 13,
                      color: ThemeConstants.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  final String name;
  final String macAddress;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDisconnect;

  const _ConnectedDeviceCard({
    required this.name,
    required this.macAddress,
    required this.selected,
    required this.onSelect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      onTap: null,
      showGlow: true,
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ThemeConstants.accent.withValues(alpha: 0.9),
              ThemeConstants.accent.withValues(alpha: 0.7)
            ],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GlowIconBox(
                    icon: Icons.bluetooth_connected_rounded,
                    color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text('Device ID: $macAddress',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          width: 6,
                          height: 6,
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle))),
                      SizedBox(width: 6),
                      Text('Connected',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onSelect,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Center(
                          child: Text(selected ? 'Selected' : 'Select Device',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onDisconnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15))),
                    child: const Text('Disconnect',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableBleDeviceCard extends StatelessWidget {
  final String name;
  final String id;
  final int rssi;
  final VoidCallback onConnect;

  const _AvailableBleDeviceCard({
    required this.name,
    required this.id,
    required this.rssi,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      onTap: onConnect,
      showGlow: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const GlowIconBox(
              icon: Icons.bluetooth_rounded, color: ThemeConstants.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(id,
                        style: const TextStyle(
                            fontSize: 12, color: ThemeConstants.textTertiary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: ThemeConstants.surfaceVariant,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('RSSI $rssi',
                          style: const TextStyle(
                              fontSize: 10,
                              color: ThemeConstants.textSecondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: ThemeConstants.accent,
                borderRadius: BorderRadius.circular(10)),
            child: const Text('Connect',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
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
  const _HeaderBtn(
      {required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: filled
              ? ThemeConstants.accent
              : ThemeConstants.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: filled
              ? null
              : Border.all(
                  color: ThemeConstants.accent.withValues(alpha: 0.15)),
        ),
        child: Icon(icon,
            color: filled ? Colors.white : ThemeConstants.accent, size: 20),
      ),
    );
  }
}

class _WifiDeviceCard extends StatelessWidget {
  final DeviceInfo device;
  final bool selected;
  final VoidCallback onTap;

  const _WifiDeviceCard({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      onTap: onTap,
      showGlow: selected,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GlowIconBox(
            icon: Icons.wifi_rounded,
            color:
                selected ? ThemeConstants.accent : ThemeConstants.textSecondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.macAddress,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? ThemeConstants.accent.withValues(alpha: 0.16)
                  : ThemeConstants.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? ThemeConstants.accent.withValues(alpha: 0.35)
                    : ThemeConstants.border,
              ),
            ),
            child: Text(
              selected ? 'Selected' : 'Select',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? ThemeConstants.accent : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
