import 'package:flutter/foundation.dart';
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
import '../../../ble/services/ble_scanner.dart';

final pairedDevicesProvider = StreamProvider((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

final _bleConnectingIdsProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});

final _hydrawaveOnlyProvider = StateProvider<bool>((ref) => true);

final _autoConnectEnabledProvider = StateProvider<bool>((ref) => false);

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize auto-scan for BLE devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scanner = ref.read(bleScannerProvider);
      scanner.initializeAutoScan();

      scanner.onDeviceFound = (result) async {
        if (!ref.read(_autoConnectEnabledProvider)) return;

        final id = result.device.remoteId.str;
        final alreadyConnecting =
            ref.read(_bleConnectingIdsProvider).contains(id);
        if (alreadyConnecting) return;

        final state = ref.read(
          bleDeviceStatusProvider(id),
        );
        if (state == BleConnectionStatus.connected) return;

        final expectedUuid = BleConstants.preferredServiceUuid;
        if (expectedUuid == null) return;

        final targetUuid = BleConstants.normalizeUuid(expectedUuid);
        final matches = result.advertisementData.serviceUuids.any(
          (u) => BleConstants.normalizeUuid(u.str) == targetUuid,
        );
        if (!matches) return;

        ref.read(_bleConnectingIdsProvider.notifier).state = {
          ...ref.read(_bleConnectingIdsProvider),
          id,
        };

        try {
          final ok = await ref
              .read(bleRepositoryProvider)
              .connectDevice(result.device);

          if (ok) {
            ref.read(sessionTargetProvider.notifier).ensureSelected(id);
          }
        } finally {
          final current = ref.read(_bleConnectingIdsProvider);
          ref.read(_bleConnectingIdsProvider.notifier).state = {
            ...current,
          }..remove(id);
        }
      };
    });

    final pairedDevices = ref.watch(pairedDevicesProvider);
    final target = ref.watch(sessionTargetProvider);
    final wifiAsync = ref.watch(wifiDevicesByOrgProvider);
    final bleScanResultsAsync = ref.watch(bleScanResultsProvider);
    final connectingIds = ref.watch(_bleConnectingIdsProvider);
    final hydrawaveOnly = ref.watch(_hydrawaveOnlyProvider);
    final autoConnectEnabled = ref.watch(_autoConnectEnabledProvider);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    Future<void> _connectAllHydrawaveDevices() async {
      if (!hydrawaveOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable the Hydrawav3 filter before auto-connecting devices.',
            ),
          ),
        );
        return;
      }

      final scanResults = bleScanResultsAsync.maybeWhen(
        data: (list) => list,
        orElse: () => const <ScanResult>[],
      );

      final expectedUuid = BleConstants.preferredServiceUuid;
      if (expectedUuid == null || expectedUuid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hydrawav3 service UUID is not configured.'),
          ),
        );
        return;
      }

      final targetUuid = BleConstants.normalizeUuid(expectedUuid);
      final filtered = scanResults.where((r) {
        final id = r.device.remoteId.str;
        if (connectingIds.contains(id)) return false;
        final advertised = r.advertisementData.serviceUuids;
        return advertised.any(
          (u) => BleConstants.normalizeUuid(u.str) == targetUuid,
        );
      }).toList();

      if (filtered.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Hydrawav3 devices available to auto-connect.'),
          ),
        );
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      final connected = <String>[];
      final failed = <String>[];

      for (final result in filtered) {
        final id = result.device.remoteId.str;
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : id;

        ref.read(_bleConnectingIdsProvider.notifier).state = {
          ...ref.read(_bleConnectingIdsProvider),
          id,
        };

        try {
          final ok = await ref.read(bleRepositoryProvider).connectDevice(
                result.device,
              );
          if (ok) {
            connected.add(name);
            await Future<void>.delayed(const Duration(milliseconds: 150));
            ref.read(sessionTargetProvider.notifier).ensureSelected(id);
          } else {
            failed.add(name);
          }
        } finally {
          final current = ref.read(_bleConnectingIdsProvider);
          ref.read(_bleConnectingIdsProvider.notifier).state = {
            ...current,
          }..remove(id);
        }
      }

      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Auto-connect complete: ${connected.length} connected'
          '${failed.isNotEmpty ? ', ${failed.length} failed' : ''}.',
        ),
      ));
    }

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(color: ThemeConstants.background),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: AnimatedEntrance(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Devices',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: ThemeConstants.textPrimary,
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
                                  child: Row(
                                    children: [
                                      Text(
                                        'Next',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: ThemeConstants.textPrimary,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Icon(Icons.arrow_forward_rounded,
                                          size: 18,
                                          color: ThemeConstants.textPrimary),
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
                                .setTransport(SessionTransport.ble, ref);
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
                              .setTransport(SessionTransport.wifi, ref),
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
              child: Row(
                children: [
                  if (target.transport == SessionTransport.ble) ...[
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: hydrawaveOnly
                                ? ThemeConstants.accent
                                : ThemeConstants.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Hydrawav3',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: hydrawaveOnly
                                  ? ThemeConstants.accent
                                  : ThemeConstants.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 22,
                            child: Center(
                              child: Transform.scale(
                                scale: 0.68,
                                child: Switch.adaptive(
                                  value: hydrawaveOnly,
                                  activeColor: ThemeConstants.accent,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => ref
                                      .read(_hydrawaveOnlyProvider.notifier)
                                      .state = v,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (hydrawaveOnly) ...[
                      GestureDetector(
                        onTap: () async {
                          ref.read(_autoConnectEnabledProvider.notifier).state =
                              !autoConnectEnabled;
                          if (!autoConnectEnabled) {
                            await _connectAllHydrawaveDevices();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: autoConnectEnabled
                                ? ThemeConstants.accent
                                : ThemeConstants.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: autoConnectEnabled
                                  ? ThemeConstants.accent
                                  : ThemeConstants.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.usb_rounded,
                                size: 16,
                                color: autoConnectEnabled
                                    ? ThemeConstants.textPrimary
                                    : ThemeConstants.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                autoConnectEnabled ? 'ON' : 'Auto-connect',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: autoConnectEnabled
                                      ? ThemeConstants.textPrimary
                                      : ThemeConstants.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                  _ScanButton(
                    visible: target.transport == SessionTransport.ble,
                    onTap: () => ref.read(startScanProvider)(),
                  ),
                ],
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
                loading: () => SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ThemeConstants.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Failed to load WiFi devices: $e',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SliverToBoxAdapter(
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
                  final selected = list
                      .where((d) => target.deviceIds.contains(d.macAddress));
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
                              subtitle: 'MAC: ${d.macAddress}',
                              batteryText: '--',
                              primaryActionLabel: 'Disconnect',
                              onPrimaryAction: () async {
                                await ref
                                    .read(bleRepositoryProvider)
                                    .disconnectDevice(d.macAddress);
                                ref
                                    .read(sessionTargetProvider.notifier)
                                    .ensureDeselected(d.macAddress);
                              },
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
                loading: () => SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ThemeConstants.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Failed to load WiFi devices: $e',
                      style: TextStyle(
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
                            target.filteredDeviceIds.contains(d.macAddress);
                        return AnimatedEntrance(
                          index: i + 1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AvailableDeviceRow(
                              icon: Icons.wifi_rounded,
                              name: d.name,
                              idText: d.macAddress,
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

                final connectedDevices = devices.where((d) {
                  final state = ref.watch(
                    bleDeviceStatusProvider(d.id),
                  );
                  return state == BleConnectionStatus.connected;
                }).toList();

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Connected section
                      if (connectedDevices.isNotEmpty) ...[
                        const SectionHeader(title: 'Connected')
                      ],
                      ...connectedDevices.map((d) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ConnectedGradientCard(
                            typeIcon: Icons.bluetooth_rounded,
                            typeLabel: 'BLE',
                            name: d.name,
                            subtitle:
                                isIos ? 'Connected Device' : 'MAC: ${d.id}',
                            batteryText: '--',
                            primaryActionLabel: 'Disconnect',
                            onPrimaryAction: () async {
                              await ref
                                  .read(bleRepositoryProvider)
                                  .disconnectDevice(d.id);
                              ref
                                  .read(sessionTargetProvider.notifier)
                                  .ensureDeselected(d.id);
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
                          final connectedIdSet =
                              connectedDevices.map((d) => d.id).toSet();
                          final deduped = byId.values
                              .where((r) => !connectedIdSet
                                  .contains(r.device.remoteId.str))
                              .where((r) {
                            if (!hydrawaveOnly) return true;
                            final expected = BleConstants.preferredServiceUuid;
                            if (expected == null || expected.isEmpty) {
                              return false;
                            }
                            final targetUuid =
                                BleConstants.normalizeUuid(expected);
                            final advertised = r.advertisementData.serviceUuids;
                            for (final u in advertised) {
                              final adv = BleConstants.normalizeUuid(u.str);
                              if (adv == targetUuid) return true;
                            }
                            return false;
                          }).toList();
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
                              final advertisedServices =
                                  r.advertisementData.serviceUuids.map(
                                      (u) => BleConstants.normalizeUuid(u.str));
                              final uuidAllowed = !strictEnabled ||
                                  advertisedServices.contains(targetService);
                              return AnimatedEntrance(
                                index: i + 1,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AvailableDeviceRow(
                                    icon: Icons.bluetooth_rounded,
                                    name: name,
                                    idText: isIos ? '' : id,
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
                                          .read(_bleConnectingIdsProvider
                                              .notifier)
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
                                            .read(_bleConnectingIdsProvider
                                                .notifier)
                                            .state = {...current}..remove(id);
                                      }
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                        loading: () => Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ThemeConstants.accent,
                                  ))),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('Scan error: $e',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: ThemeConstants.textSecondary)),
                        ),
                      ),
                    ]),
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeConstants.accent,
                      ),
                    ),
                  ),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
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
            Icon(icon,
                size: 18,
                color: active
                    ? ThemeConstants.textPrimary
                    : ThemeConstants.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active
                    ? ThemeConstants.textPrimary
                    : ThemeConstants.textSecondary,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              color: scanning
                  ? ThemeConstants.accent
                  : ThemeConstants.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              scanning ? 'Scanning...' : 'Scan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scanning
                    ? ThemeConstants.accent
                    : ThemeConstants.textSecondary,
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
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeConstants.borderLight.withValues(alpha: 0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.accent.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
                color: ThemeConstants.accentLight.withValues(alpha: 0.22),
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
                        Icon(typeIcon,
                            size: 18, color: ThemeConstants.textPrimary),
                        const SizedBox(width: 8),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    // Container(
                    //   padding: const EdgeInsets.symmetric(
                    //       horizontal: 10, vertical: 6),
                    //   decoration: BoxDecoration(
                    //     color: Colors.black.withValues(alpha: 0.12),
                    //     borderRadius: BorderRadius.circular(10),
                    //     border: Border.all(
                    //       color: Colors.black.withValues(alpha: 0.10),
                    //     ),
                    //   ),
                    //   // child: Row(
                    //   //   mainAxisSize: MainAxisSize.min,
                    //   //   // children: [
                    //   //   //   Icon(Icons.battery_full,
                    //   //   //       size: 14, color: ThemeConstants.textPrimary),
                    //   //   //   const SizedBox(width: 6),
                    //   //   //   Text(
                    //   //   //     batteryText,
                    //   //   //     style: TextStyle(
                    //   //   //       fontSize: 12,
                    //   //   //       fontWeight: FontWeight.w700,
                    //   //   //       color: ThemeConstants.textPrimary,
                    //   //   //     ),
                    //   //   //   ),
                    //   //   // ],
                    //   // ),
                    // ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: ThemeConstants.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onPrimaryAction,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: ThemeConstants.accent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  ThemeConstants.accent.withValues(alpha: 0.9),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              primaryActionLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ThemeConstants.textPrimary,
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
                        color: ThemeConstants.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ThemeConstants.borderLight,
                        ),
                      ),
                      child: Icon(Icons.settings_rounded,
                          color: ThemeConstants.textPrimary, size: 20),
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
  final String idText;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback onTap;

  const _AvailableDeviceRow({
    required this.icon,
    required this.name,
    required this.idText,
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  idText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeConstants.textSecondary,
                    height: 1.2,
                  ),
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
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeConstants.accent,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
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
            color: filled ? ThemeConstants.textPrimary : ThemeConstants.accent,
            size: 20),
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
      idText: device.macAddress,
      buttonLabel: selected ? 'Selected' : 'Select',
      onTap: onTap,
    );
  }
}
