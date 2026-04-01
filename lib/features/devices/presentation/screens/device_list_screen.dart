import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/glass_container.dart';
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
      backgroundColor: ThemeConstants.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: true,
            snap: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ThemeConstants.darkTeal, ThemeConstants.teal],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('📡 Devices',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.5)),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            const Text('🔍 Scanning for devices...'),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        backgroundColor: ThemeConstants.darkTeal,
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                        Icons.bluetooth_searching_rounded,
                                        color: ThemeConstants.tanLight,
                                        size: 22),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () =>
                                      context.push(RoutePaths.deviceRegister),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: ThemeConstants.copper,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.add_rounded,
                                        color: Colors.white, size: 22),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '🔗 Manage your Hydrawav3 devices',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          devicesAsync.when(
            loading: () => const SliverFillRemaining(
                child: HwLoading(message: '🔄 Loading devices...')),
            error: (error, _) => SliverFillRemaining(
                child: HwErrorWidget(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(pairedDevicesProvider))),
            data: (devices) {
              if (devices.isEmpty) {
                return SliverFillRemaining(
                  child: HwEmptyState(
                    icon: Icons.bluetooth_disabled_rounded,
                    title: '📡 No Devices Found',
                    subtitle:
                        'Tap the scan button to discover nearby Hydrawav3 devices, or register one manually.',
                    action: ElevatedButton.icon(
                      onPressed: () => context.push(RoutePaths.deviceRegister),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('➕ Register Device'),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(ThemeConstants.spacingMd),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = devices[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 400 + index * 80),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            onTap: () => context.push('/devices/${device.id}'),
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: ThemeConstants.success
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                      Icons.bluetooth_connected_rounded,
                                      color: ThemeConstants.success,
                                      size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('🏷️ ${device.name}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(device.macAddress,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: ThemeConstants.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: devices.length,
                  ),
                ),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}
