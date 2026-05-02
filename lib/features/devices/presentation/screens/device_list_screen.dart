import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/constants/ble_constants.dart';
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

final _bleConnectingIdsProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairedDevices = ref.watch(pairedDevicesProvider);
    final target = ref.watch(sessionTargetProvider);
    final wifiAsync = ref.watch(wifiDevicesByOrgProvider);
    final connectingIds = ref.watch(_bleConnectingIdsProvider);
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
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
                        Row(
                          children: [
                            if (target.deviceIds.isNotEmpty)
                              GestureDetector(
                                onTap: () => context.go(RoutePaths.protocols),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ThemeConstants.accent,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ThemeConstants.accent
                                            .withValues(alpha: 0.22),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.check_rounded,
                                          size: 18, color: Colors.white),
                                      SizedBox(width: 6),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(width: 10),
                            _HeaderBtn(
                              icon: Icons.add_rounded,
                              filled: true,
                              onTap: () =>
                                  context.push(RoutePaths.deviceRegister),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Transport segmented toggle (UI only)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ThemeConstants.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentBtn(
                          active: target.transport == SessionTransport.ble,
                          icon: Icons.bluetooth_rounded,
                          label: 'Bluetooth',
                          onTap: () {
                            ref
                                .read(sessionTargetProvider.notifier)
                                .setTransport(SessionTransport.ble);
                            Future.delayed(const Duration(milliseconds: 100),
                                () {
                              ref.read(startScanProvider)();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _SegmentBtn(
                          active: target.transport == SessionTransport.wifi,
                          icon: Icons.wifi_rounded,
                          label: 'Wi‑Fi',
                          onTap: () => ref
                              .read(sessionTargetProvider.notifier)
                              .setTransport(SessionTransport.wifi),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Scan button (BLE only)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerRight,
                child: _ScanButton(
                  visible: target.transport == SessionTransport.ble,
                  onTap: () => ref.read(startScanProvider)(),
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
                  child: const SectionHeader(title: 'Connected'),
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
                  final selected =
                      list.where((d) => target.deviceIds.contains(d.macAddress));
                  if (selected.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: _EmptyDashed(
                        icon: Icons.wifi_rounded,
                        title: 'No devices connected',
                        subtitle: 'Select a Wi‑Fi device below to continue',
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final d = selected.elementAt(i);
                        return AnimatedEntrance(
                          index: i + 1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ConnectedGradientCard(
                              typeIcon: Icons.wifi_rounded,
                              typeLabel: 'Wi‑Fi',
                              name: d.name,
                              subtitle: 'SN: ${d.macAddress}',
                              batteryText: '--',
                              primaryActionLabel: 'Disconnect',
                              onPrimaryAction: () => ref
                                  .read(sessionTargetProvider.notifier)
                                  .toggleDevice(d.macAddress),
                            ),
                          ),
                        );
                      },
                      childCount: selected.length,
                    ),
                  );
                },
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: const SectionHeader(title: 'Available Wi‑Fi Devices'),
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
                      child: _EmptyDashed(
                        icon: Icons.wifi_rounded,
                        title: 'No devices found',
                        subtitle: 'Make sure your device is turned on',
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
                            child: _AvailableDeviceRow(
                              icon: Icons.wifi_rounded,
                              name: d.name,
                              metaLeft: 'Strong',
                              metaRight: d.firmware != null
                                  ? 'v${d.firmware}'
                                  : 'v—',
                              buttonLabel: selected ? 'Selected' : 'Select',
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
            // BLE Device List - Connected and Available
            pairedDevices.when(
              data: (devices) {
                final scanResults = ref.watch(bleScanResultsProvider);

                final connectedDevices = scanResults.when(
                  data: (list) => list.where((r) {
                    final state = ref.watch(
                      bleDeviceStatusProvider(r.device.remoteId.str),
                    );
                    return state == BleConnectionStatus.connected;
                  }).toList(),
                  loading: () => [],
                  error: (_, __) => [],
                );

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Connected section
                      if (connectedDevices.isNotEmpty) ...[
                        const SectionHeader(title: 'Connected')
                      ],
                      ...connectedDevices.map((r) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ConnectedGradientCard(
                            typeIcon: Icons.bluetooth_rounded,
                            typeLabel: 'BLE',
                            name: r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : 'Unknown Device',
                            subtitle: 'SN: ${r.device.remoteId.str}',
                            batteryText: '--',
                            primaryActionLabel: 'Disconnect',
                            onPrimaryAction: () async {
                              await ref
                                  .read(bleRepositoryProvider)
                                  .disconnectDevice(r.device.remoteId.str);
                              ref
                                  .read(sessionTargetProvider.notifier)
                                  .ensureDeselected(r.device.remoteId.str);
                            },
                          ),
                        );
                      }).toList(),
                      if (connectedDevices.isNotEmpty)
                        const SizedBox(height: 8),
                      const SectionHeader(title: 'Available Bluetooth Devices'),
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
                          final connectedIdSet = connectedDevices
                              .map((r) => r.device.remoteId.str)
                              .toSet();
                          final deduped = byId.values
                              .where((r) =>
                                  !connectedIdSet.contains(r.device.remoteId.str))
                              .toList();
                          if (deduped.isEmpty) {
                            return const _EmptyDashed(
                              icon: Icons.bluetooth_rounded,
                              title: 'No devices found',
                              subtitle: 'Make sure your device is turned on',
                            );
                          }
                          return Column(
                            children: deduped.asMap().entries.map((entry) {
                              final i = entry.key;
                              final r = entry.value;
                              final name = r.device.platformName.isNotEmpty
                                  ? r.device.platformName
                                  : 'Unknown';
                              final id = r.device.remoteId.str;
                              final strictEnabled =
                                  BleConstants.strictHydraGattProfile &&
                                      BleConstants.preferredServiceUuid != null;
                              final targetService = strictEnabled
                                  ? BleConstants.normalizeUuid(
                                      BleConstants.preferredServiceUuid!,
                                    )
                                  : null;
                              final advertisedServices = r
                                  .advertisementData.serviceUuids
                                  .map((u) => BleConstants.normalizeUuid(u.str));
                              final uuidAllowed = !strictEnabled ||
                                  advertisedServices.contains(targetService);
                              return AnimatedEntrance(
                                index: i + 1,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AvailableDeviceRow(
                                    icon: Icons.bluetooth_rounded,
                                    name: name,
                                    metaLeft: 'Strong',
                                    metaRight: 'v—',
                                    buttonLabel: connectingIds.contains(id)
                                        ? 'Connecting...'
                                        : 'Connect',
                                    isLoading: connectingIds.contains(id),
                                    onTap: () async {
                                      if (connectingIds.contains(id)) return;
                                      if (!uuidAllowed) {
                                        final expectedUuid =
                                            BleConstants.preferredServiceUuid;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              expectedUuid == null
                                                  ? 'Cannot connect: this device does not match the required Hydrawav profile.'
                                                  : 'Cannot connect: this device does not advertise the required Hydrawav service.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      ref
                                          .read(_bleConnectingIdsProvider.notifier)
                                          .state = {...connectingIds, id};
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      try {
                                        final ok = await ref
                                            .read(bleRepositoryProvider)
                                            .connectDevice(r.device);

                                        if (ok) {
                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 150),
                                          );
                                          ref
                                              .read(
                                                sessionTargetProvider.notifier,
                                              )
                                              .ensureSelected(id);
                                        }

                                        if (!context.mounted) return;
                                        messenger.showSnackBar(SnackBar(
                                          content: Text(
                                            ok
                                                ? 'Connected to $name'
                                                : 'Failed to connect to $name',
                                          ),
                                        ));
                                      } finally {
                                        final current =
                                            ref.read(_bleConnectingIdsProvider);
                                        ref
                                            .read(
                                                _bleConnectingIdsProvider.notifier)
                                            .state = {
                                          ...current
                                        }..remove(id);
                                      }
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

class _SegmentBtn extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SegmentBtn({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? ThemeConstants.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: ThemeConstants.accent.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : ThemeConstants.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends ConsumerWidget {
  final bool visible;
  final VoidCallback onTap;
  const _ScanButton({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();
    final scanning = ref.watch(isScanningProvider);
    return GestureDetector(
      onTap: scanning ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scanning
                ? ThemeConstants.accent.withValues(alpha: 0.45)
                : ThemeConstants.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh_rounded,
              size: 16,
              color: scanning ? ThemeConstants.accent : ThemeConstants.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              scanning ? 'Scanning...' : 'Scan for Devices',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scanning ? ThemeConstants.accent : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedGradientCard extends StatelessWidget {
  final IconData typeIcon;
  final String typeLabel;
  final String name;
  final String subtitle;
  final String batteryText;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;

  const _ConnectedGradientCard({
    required this.typeIcon,
    required this.typeLabel,
    required this.name,
    required this.subtitle,
    required this.batteryText,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ThemeConstants.accent, Color(0xFFE09060)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.accent.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Positioned(
              top: -8,
              right: -8,
              child: Icon(
                typeIcon,
                size: 96,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(typeIcon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.battery_full,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            batteryText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onPrimaryAction,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              primaryActionLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: const Icon(Icons.settings_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableDeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String metaLeft;
  final String metaRight;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback onTap;

  const _AvailableDeviceRow({
    required this.icon,
    required this.name,
    required this.metaLeft,
    required this.metaRight,
    required this.buttonLabel,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ThemeConstants.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ThemeConstants.border),
            ),
            child: Icon(icon, color: ThemeConstants.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.network_wifi_rounded,
                            size: 14, color: Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(
                          metaLeft,
                          style: const TextStyle(
                            fontSize: 11,
                            color: ThemeConstants.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Text('•',
                        style: TextStyle(
                            fontSize: 11,
                            color: ThemeConstants.textTertiary)),
                    const SizedBox(width: 8),
                    Text(
                      metaRight,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isLoading ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ThemeConstants.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeConstants.border),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
              ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDashed extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyDashed({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ThemeConstants.border.withValues(alpha: 0.8),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 44, color: ThemeConstants.textTertiary),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: ThemeConstants.textTertiary,
              ),
            ),
          ],
        ),
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
    // Kept for backward compatibility (no longer used in new UI).
    return _AvailableDeviceRow(
      icon: Icons.wifi_rounded,
      name: device.name,
      metaLeft: 'Strong',
      metaRight: device.firmware != null ? 'v${device.firmware}' : 'v—',
      buttonLabel: selected ? 'Selected' : 'Select',
      onTap: onTap,
    );
  }
}
