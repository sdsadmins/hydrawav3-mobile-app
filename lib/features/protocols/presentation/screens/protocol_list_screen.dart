import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final homePairedDevicesProvider = StreamProvider<List<PairedDevice>>((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

class ProtocolListScreen extends ConsumerWidget {
  const ProtocolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocolsAsync = ref.watch(protocolListProvider);
    final auth = ref.watch(authStateProvider);
    final connectionStates = ref.watch(bleConnectionStatesProvider);
    final connectedIds = connectionStates.maybeWhen(
      data: (map) => map.entries
          .where((e) => e.value == BleConnectionStatus.connected)
          .map((e) => e.key)
          .toList(),
      orElse: () => const <String>[],
    );
    final pairedAsync = ref.watch(homePairedDevicesProvider);
    final batteryAsync = ref.watch(bleBatteryLevelsProvider);
    final target = ref.watch(sessionTargetProvider);
    final wifiAsync = ref.watch(wifiDevicesByOrgProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          /// 🔥 HEADER
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
                        /// 🔥 LEFT SIDE
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Home',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),

                            const SizedBox(height: 6),

                            /// ✅ SHOW ORG NAME ONLY
                            Text(
                              auth.selectedOrgName ?? "No Organization",
                              style: const TextStyle(
                                fontSize: 13,
                                color: ThemeConstants.accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Select a protocol to begin',
                              style: TextStyle(
                                fontSize: 14,
                                color: ThemeConstants.textSecondary,
                              ),
                            ),
                          ],
                        ),

                        /// 🔥 RIGHT SIDE ICONS
                        Row(
                          children: [
                            _HeaderButton(
                              icon: Icons.smart_toy_outlined,
                              onTap: () =>
                                  context.push(RoutePaths.chat),
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

          /// ✅ ACTIVE DEVICES CARD (TOP)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 0,
                child: _ActiveDevicesCard(
                  connectedBleDeviceIds: connectedIds,
                  pairedDevicesAsync: pairedAsync,
                  batteryLevelsAsync: batteryAsync,
                  sessionTarget: target,
                  wifiDevicesAsync: wifiAsync,
                  onConnectTap: () => context.go(RoutePaths.devices),
                ),
              ),
            ),
          ),

          /// ✅ PROTOCOLS HEADER
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(title: 'All Protocols'),
            ),
          ),

          /// 🔥 LIST
          protocolsAsync.when(
            loading: () => const SliverFillRemaining(
              child: HwLoading(message: 'Loading protocols...'),
            ),
            error: (e, _) => SliverFillRemaining(
              child: HwErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(protocolListProvider),
              ),
            ),
            data: (protocols) {
              if (protocols.isEmpty) {
                return const SliverFillRemaining(
                  child: HwEmptyState(
                    icon: Icons.science_outlined,
                    title: 'No Protocols Yet',
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return AnimatedEntrance(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ProtocolCard(
                            protocol: protocols[index],
                          ),
                        ),
                      );
                    },
                    childCount: protocols.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActiveDevicesCard extends StatelessWidget {
  final List<String> connectedBleDeviceIds;
  final AsyncValue<List<PairedDevice>> pairedDevicesAsync;
  final AsyncValue<Map<String, int>> batteryLevelsAsync;
  final SessionTargetState sessionTarget;
  final AsyncValue<List<DeviceInfo>> wifiDevicesAsync;
  final VoidCallback onConnectTap;

  const _ActiveDevicesCard({
    required this.connectedBleDeviceIds,
    required this.pairedDevicesAsync,
    required this.batteryLevelsAsync,
    required this.sessionTarget,
    required this.wifiDevicesAsync,
    required this.onConnectTap,
  });

  @override
  Widget build(BuildContext context) {
    bool isWifiConnectedStatus(String? s) {
      final v = (s ?? '').trim().toLowerCase();
      if (v.isEmpty) return true; // backend often omits status
      if (v == '1' || v == 'true' || v == 'yes') return true;
      if (v.contains('connect')) return true;
      if (v.contains('online')) return true;
      if (v.contains('active')) return true;
      if (v.contains('ready')) return true;
      if (v.contains('up')) return true;
      if (v.contains('ok')) return true;
      if (v.contains('running')) return true;
      return false;
    }

    // IMPORTANT:
    // - BLE: connected devices come from the BLE connection state (always).
    // - WiFi: DO NOT treat "selected" as connected; only show devices that are
    //   actually online/connected according to backend `status`.
    //
    // Home banner must reflect real-time connectivity, independent of the
    // currently selected transport.
    final connectedBleIds = connectedBleDeviceIds;
    final connectedWifiMacs = wifiDevicesAsync.maybeWhen(
      data: (list) => list
          .where((d) =>
              sessionTarget.deviceIds.contains(d.macAddress) &&
              isWifiConnectedStatus(d.status))
          .map((d) => d.macAddress)
          .toList(),
      orElse: () => const <String>[],
    );
    final connectedCount = connectedBleIds.length + connectedWifiMacs.length;

    final bannerGradient = [
      ThemeConstants.surface,
      ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
    ];

    return GradientCard(
      showGlow: true,
      padding: const EdgeInsets.all(16),
      gradientColors: bannerGradient,
      child: Stack(
        children: [
          Positioned(
            top: -34,
            right: -34,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: ThemeConstants.accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const SizedBox(),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: ThemeConstants.accent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Active Devices',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    child: Text(
                      '$connectedCount Connected',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (connectedCount == 0) ...[
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'No devices connected',
                    style: TextStyle(
                      fontSize: 14,
                      color: ThemeConstants.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: onConnectTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: ThemeConstants.accent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: ThemeConstants.accent.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Text(
                        'Connect Device',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 2),
                _MixedConnectedDevicesList(
                  connectedBleIds: connectedBleIds,
                  connectedWifiMacs: connectedWifiMacs,
                  pairedDevicesAsync: pairedDevicesAsync,
                  wifiDevicesAsync: wifiDevicesAsync,
                  batteryLevelsAsync: batteryLevelsAsync,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _ConnType { ble, wifi }

class _ConnEntry {
  final String id;
  final String name;
  final _ConnType type;
  final String trailing;
  const _ConnEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.trailing,
  });
}

class _MixedConnectedDevicesList extends StatelessWidget {
  final List<String> connectedBleIds;
  final List<String> connectedWifiMacs;
  final AsyncValue<List<PairedDevice>> pairedDevicesAsync;
  final AsyncValue<List<DeviceInfo>> wifiDevicesAsync;
  final AsyncValue<Map<String, int>> batteryLevelsAsync;

  const _MixedConnectedDevicesList({
    required this.connectedBleIds,
    required this.connectedWifiMacs,
    required this.pairedDevicesAsync,
    required this.wifiDevicesAsync,
    required this.batteryLevelsAsync,
  });

  @override
  Widget build(BuildContext context) {
    // We need both BLE paired names and WiFi names. If either provider is still
    // loading, we still show rows with ids.
    final paired = pairedDevicesAsync.maybeWhen(
      data: (d) => d,
      orElse: () => const <PairedDevice>[],
    );
    final wifi = wifiDevicesAsync.maybeWhen(
      data: (d) => d,
      orElse: () => const <DeviceInfo>[],
    );
    final batteryMap = batteryLevelsAsync.maybeWhen(
      data: (m) => m,
      orElse: () => const <String, int>{},
    );

    String bleNameFor(String id) {
      final match = paired.where((p) => p.macAddress == id);
      return match.isNotEmpty ? match.first.name : id;
    }

    String wifiNameFor(String mac) {
      final match = wifi.where((d) => d.macAddress == mac);
      return match.isNotEmpty ? match.first.name : mac;
    }

    final entries = <_ConnEntry>[
      ...connectedBleIds.map(
        (id) => _ConnEntry(
          id: id,
          name: bleNameFor(id),
          type: _ConnType.ble,
          trailing: batteryMap[id] != null ? '${batteryMap[id]}%' : '--',
        ),
      ),
      ...connectedWifiMacs.map(
        (mac) => _ConnEntry(
          id: mac,
          name: wifiNameFor(mac),
          type: _ConnType.wifi,
          trailing: '--',
        ),
      ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    final shown = entries.take(2).toList();
    final remaining = entries.length - shown.length;

    return Column(
      children: [
        ...shown.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ConnectedDeviceRow(
              name: e.name,
              trailing: e.trailing,
              showPulse: true,
              leadingIcon: e.type == _ConnType.ble
                  ? Icons.bluetooth_connected_rounded
                  : Icons.wifi_rounded,
            ),
          ),
        ),
        if (remaining > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+$remaining more',
              style: const TextStyle(
                fontSize: 12,
                color: ThemeConstants.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectedDeviceView {
  final String id;
  final String name;
  const _ConnectedDeviceView({required this.id, required this.name});
}

class _ConnectedDeviceRow extends StatelessWidget {
  final String name;
  final String trailing;
  final IconData? leadingIcon;
  final bool showPulse;
  const _ConnectedDeviceRow({
    required this.name,
    required this.trailing,
    this.leadingIcon,
    this.showPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: ThemeConstants.border.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              showPulse ? const _PulseDot() : const _StaticDot(),
              const SizedBox(width: 10),
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 16,
                  color: ThemeConstants.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.battery_full,
                      size: 16, color: ThemeConstants.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    trailing,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ThemeConstants.textSecondary,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _StaticDot extends StatelessWidget {
  const _StaticDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: ThemeConstants.accent.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final alpha = (0.35 + 0.35 * t).clamp(0.0, 1.0);
        final glow = 6.0 + 6.0 * t;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: ThemeConstants.accent.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ThemeConstants.accent.withValues(alpha: alpha),
                blurRadius: glow,
                spreadRadius: 0,
              )
            ],
          ),
        );
      },
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ThemeConstants.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeConstants.accent.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(icon, color: ThemeConstants.accent, size: 20),
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final Protocol protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      onTap: () => context.push('/protocols/${protocol.id}'),
      showGlow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlowIconBox(icon: Icons.science_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      protocol.templateName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (protocol.description.isNotEmpty)
                      Text(
                        protocol.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ThemeConstants.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: ThemeConstants.textTertiary, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatChip(
                icon: Icons.timer_outlined,
                value: protocol.totalDuration.formatted,
              ),
              const SizedBox(width: 8),
              StatChip(
                icon: Icons.repeat_rounded,
                value: '${protocol.cycles.length}',
                label: 'cycles',
              ),
              const SizedBox(width: 8),
              StatChip(
                icon: Icons.play_circle_outline_rounded,
                value: '${protocol.sessions}',
                label: 'sess',
              ),
            ],
          ),
        ],
      ),
    );
  }
}