import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import '../providers/protocol_plus_detail_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../payments/presentation/widgets/token_balance_badge.dart';

final homePairedDevicesProvider = StreamProvider<List<PairedDevice>>((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

class ProtocolListScreen extends ConsumerStatefulWidget {
  const ProtocolListScreen({super.key});

  @override
  ConsumerState<ProtocolListScreen> createState() => _ProtocolListScreenState();
}

class _ProtocolListScreenState extends ConsumerState<ProtocolListScreen> {
  String? _selectedGoalTagId;

  @override
  void initState() {
    super.initState();
    // Ensure the token balance feed is running for the badge in the header
    // (idempotent if the app bootstrap already started it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authStateProvider);
      final orgId = auth.selectedOrgId ?? auth.user?.organizationId;
      if (orgId != null && orgId.isNotEmpty) {
        ref.read(tokenBalanceProvider.notifier).start(orgId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedGoalTagId = _selectedGoalTagId?.trim().isEmpty ?? true
        ? null
        : _selectedGoalTagId!.trim();
    final protocolsAsync = ref.watch(protocolListProvider);
    final goalTagsAsync = ref.watch(goalTagListProvider);
    final filteredProtocolIdsAsync = selectedGoalTagId == null
        ? const AsyncValue.data(<String>{})
        : ref
            .watch(protocolSelectionOptionsProvider(selectedGoalTagId))
            .whenData((protocols) => protocols.map((p) => p.id).toSet());
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

    final List<String> setupDeviceIds = () {
      if (target.transport == SessionTransport.ble) {
        // If the user hasn't picked explicit BLE targets yet, treat all currently
        // connected BLE devices as setup targets (matches the banner list).
        if (target.deviceIds.isEmpty) {
          return connectedIds;
        }
        return target.deviceIds
            .where((id) => connectedIds.contains(id))
            .toList();
      }

      // WiFi: if the user hasn't picked explicit targets, keep empty.
      if (target.deviceIds.isEmpty) return const <String>[];
      return wifiAsync.maybeWhen(
        data: (list) => list
            .where((d) =>
                target.deviceIds.contains(d.macAddress) &&
                isWifiConnectedStatus(d.status))
            .map((d) => d.macAddress)
            .toList(),
        orElse: () => const <String>[],
      );
    }();

    final canContinue = setupDeviceIds.isNotEmpty;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: RefreshIndicator(
        color: ThemeConstants.accent,
        onRefresh: () async {
          ref.invalidate(protocolListProvider);
          ref.invalidate(goalTagListProvider);
          await ref.read(protocolListProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics()),
          slivers: [
          /// 🔥 HEADER
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(color: ThemeConstants.background),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// 🔥 TOP BAR — full-width logo on its own row, then a
                        /// row below it with "Home" (left) + token badge (right).
                        const _HomeLogo(),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Home',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ThemeConstants.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            // Token chip — tap for the full plan/usage
                            // breakdown (web parity).
                            const TokenBalanceBadge(),
                          ],
                        ),

                        const SizedBox(height: 2),

                        Text(
                          'Select a protocol to begin',
                          style: TextStyle(
                            fontSize: 14,
                            color: ThemeConstants.textSecondary,
                          ),
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                  canContinue: canContinue,
                  onContinueTap: () => context.go(RoutePaths.devices),
                ),
              ),
            ),
          ),

          /// ✅ PROTOCOLS HEADER
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.science_rounded,
                        color: ThemeConstants.accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Protocols',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// 🔥 LIST
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 38,
                    child: goalTagsAsync.when(
                      loading: () => ListView(
                        scrollDirection: Axis.horizontal,
                        children: const [
                          _GoalFilterChip(
                            label: 'All',
                            selected: true,
                          ),
                        ],
                      ),
                      error: (e, _) => const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Failed to load goals',
                          style: TextStyle(
                            color: ThemeConstants.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      data: (goalTags) {
                        final activeGoalTags =
                            goalTags.where((goal) => goal.isActive).toList();

                        return ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _GoalFilterChip(
                                label: 'All',
                                selected: selectedGoalTagId == null,
                                onTap: () =>
                                    setState(() => _selectedGoalTagId = null),
                              ),
                            ),
                            ...activeGoalTags.map(
                              (goal) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _GoalFilterChip(
                                  label: goal.name,
                                  selected: selectedGoalTagId == goal.id,
                                  onTap: () => setState(
                                    () => _selectedGoalTagId = goal.id,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          protocolsAsync.when(
            loading: () => const _ProtocolListSkeleton(),
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

              if (selectedGoalTagId != null) {
                return filteredProtocolIdsAsync.when(
                  loading: () => const _ProtocolListSkeleton(),
                  error: (e, _) => SliverFillRemaining(
                    child: HwErrorWidget(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(
                        protocolSelectionOptionsProvider(selectedGoalTagId),
                      ),
                    ),
                  ),
                  data: (filteredProtocolIds) {
                    final visibleProtocols = protocols
                        .where((protocol) =>
                            filteredProtocolIds.contains(protocol.id))
                        .toList()
                      ..sort((a, b) =>
                          naturalCompare(a.templateName, b.templateName));

                    if (visibleProtocols.isEmpty) {
                      return const SliverFillRemaining(
                        child: HwEmptyState(
                          icon: Icons.filter_alt_off_rounded,
                          title: 'No Protocols For This Goal',
                        ),
                      );
                    }

                    return _ProtocolList(protocols: visibleProtocols);
                  },
                );
              }

              final sortedProtocols = [...protocols]
                ..sort((a, b) =>
                    naturalCompare(a.templateName, b.templateName));

              return _ProtocolList(protocols: sortedProtocols);
            },
          ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolList extends StatelessWidget {
  final List<Protocol> protocols;

  const _ProtocolList({required this.protocols});

  @override
  Widget build(BuildContext context) {
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
  }
}

class _ProtocolListSkeleton extends StatelessWidget {
  const _ProtocolListSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _ProtocolCardSkeleton(),
          ),
          childCount: 6,
        ),
      ),
    );
  }
}

class _ProtocolCardSkeleton extends StatelessWidget {
  const _ProtocolCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? ThemeConstants.surface
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox(width: 44, height: 44, borderRadius: 12),
              SizedBox(width: 14),
              Expanded(
                child: ShimmerBox(
                    width: double.infinity, height: 15, borderRadius: 6),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              ShimmerBox(width: 72, height: 28, borderRadius: 10),
              SizedBox(width: 8),
              ShimmerBox(width: 72, height: 28, borderRadius: 10),
              SizedBox(width: 8),
              ShimmerBox(width: 72, height: 28, borderRadius: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _GoalFilterChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // Match the Devices list segmented control: dark-slate selected in
          // light mode, tan in dark mode (segmentActiveBg handles both).
          color: selected
              ? ThemeConstants.segmentActiveBg
              : ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? ThemeConstants.segmentActiveBg
                : ThemeConstants.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? ThemeConstants.onNav
                : ThemeConstants.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
  final bool canContinue;
  final VoidCallback onContinueTap;

  const _ActiveDevicesCard({
    required this.connectedBleDeviceIds,
    required this.pairedDevicesAsync,
    required this.batteryLevelsAsync,
    required this.sessionTarget,
    required this.wifiDevicesAsync,
    required this.onConnectTap,
    required this.canContinue,
    required this.onContinueTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? ThemeConstants.surface
        : Colors.white;

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

    return GradientCard(
      showGlow: true,
      padding: const EdgeInsets.all(16),
      gradientColors: [cardColor, cardColor],
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded,
                      color: ThemeConstants.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active Devices',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ThemeConstants.borderLight),
                    ),
                    child: Text(
                      '$connectedCount Connected',
                      style: TextStyle(
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
                Center(
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
                            color:
                                ThemeConstants.accent.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Text(
                        'Connect Device',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary,
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
                if (canContinue) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onContinueTap,
                      child: Text('Choose Protocol'),
                    ),
                  ),
                ],
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
  const _ConnEntry({
    required this.id,
    required this.name,
    required this.type,
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
        ),
      ),
      ...connectedWifiMacs.map(
        (mac) => _ConnEntry(
          id: mac,
          name: wifiNameFor(mac),
          type: _ConnType.wifi,
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
              style: TextStyle(
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
  final IconData? leadingIcon;
  final bool showPulse;
  const _ConnectedDeviceRow({
    required this.name,
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
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ThemeConstants.borderLight.withValues(alpha: 0.85),
            ),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
              ),
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

/// Hydrawav3 wordmark in the home header. Theme-aware so it stays visible on
/// both backgrounds: the black logo on light, the white logo on dark.
class _HomeLogo extends StatelessWidget {
  const _HomeLogo();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Both logos are SVGs sharing the SAME viewBox (643.8 x 226.2 — tall relative
    // to the single-line wordmark, so it carries a lot of top/bottom whitespace).
    // Render full-width via BoxFit.fitWidth, then crop the empty bands above/below
    // with ClipRect + Align(heightFactor) so the logo isn't surrounded by big
    // vertical margins. Tune [_logoHeightFactor] (→1.0 = no crop, less = tighter).
    const double logoHeightFactor = 0.62;
    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        heightFactor: logoHeightFactor,
        child: SizedBox(
          width: double.infinity,
          child: SvgPicture.asset(
            isDark
                ? 'assets/images/Hydrawav3_White_Logo.svg'
                : 'assets/images/Hydrawav3_Black_Logo.svg',
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}

class _ProtocolCard extends ConsumerWidget {
  final Protocol protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? ThemeConstants.surface
        : Colors.white;

    // Plan gating (web parity): a protocol not included in the org's plan is
    // shown disabled (greyed + a lock) and can't be opened.
    final locked = !protocol.active;

    // A Protocol Plus entry has no cycles of its own and the backend defaults
    // its sessions to 1 — both wrong for the card. Pull the populated sequence
    // and show the SUMMED cycles/sessions across its sub-protocols instead.
    final isPlus = protocol.isProtocolPlus;
    var cyclesCount = protocol.cycles.length;
    var sessionsCount = protocol.sessions;
    var countsReady = !isPlus;
    if (isPlus) {
      final detail = ref.watch(protocolPlusDetailProvider(protocol.id)).asData?.value;
      if (detail != null) {
        final totals = protocolPlusTotals(detail);
        if (totals.cycles != null) {
          cyclesCount = totals.cycles!;
          sessionsCount = totals.sessions!;
          countsReady = true;
        }
      }
    }

    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: GradientCard(
        onTap: () {
          if (locked) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This protocol isn\'t included in your plan.'),
              ),
            );
            return;
          }
          context.push(
              RoutePaths.protocolDetail.replaceFirst(':id', protocol.id));
        },
        // Flat web-style card: solid fill + thin border, no drop shadow.
        showShadow: false,
        gradientColors: [cardColor, cardColor],
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlowIconBox(
                  icon: isPlus ? Icons.layers_rounded : Icons.science_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    protocol.templateName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : Icons.chevron_right_rounded,
                  color: ThemeConstants.textTertiary,
                  size: 20,
                ),
              ],
            ),
            // Full description shown on the list card too (not just the detail
            // screen), so users can tell protocols apart without opening each.
            if (protocol.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                protocol.description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  color: ThemeConstants.textSecondary,
                ),
              ),
            ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatChip(
                icon: Icons.timer_outlined,
                value: protocol.totalDuration.formatted,
              ),
              // For a Plus entry these are the summed totals across the
              // sequence; hidden until the detail resolves so we never flash a
              // wrong "0 cycles / 1 sess".
              if (countsReady) ...[
                StatChip(
                  icon: Icons.repeat_rounded,
                  value: '$cyclesCount',
                  label: 'cycles',
                ),
                StatChip(
                  icon: Icons.play_circle_outline_rounded,
                  value: '$sessionsCount',
                  label: 'sess',
                ),
              ],
            ],
          ),
          ],
        ),
      ),
    );
  }
}
