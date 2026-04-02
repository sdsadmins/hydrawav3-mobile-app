import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/extensions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';

// ---------------------------------------------------------------------------
// Session goal filter options
// ---------------------------------------------------------------------------
enum _SessionGoal { all, activate, recovery, spa, sleep, performance }

extension on _SessionGoal {
  String get label => switch (this) {
        _SessionGoal.all => 'All',
        _SessionGoal.activate => 'Activate',
        _SessionGoal.recovery => 'Recovery',
        _SessionGoal.spa => 'Spa',
        _SessionGoal.sleep => 'Sleep',
        _SessionGoal.performance => 'Performance',
      };
}

// ---------------------------------------------------------------------------
// Demo preset data
// ---------------------------------------------------------------------------
class _Preset {
  final String? name;
  final String? protocolName;
  final int deviceCount;
  final bool isEmpty;

  const _Preset({this.name, this.protocolName, this.deviceCount = 0}) : isEmpty = false;
  const _Preset.empty() : name = null, protocolName = null, deviceCount = 0, isEmpty = true;
}

const _demoPresets = [
  _Preset(name: 'Morning Flow', protocolName: 'Activate Pro', deviceCount: 2),
  _Preset(name: 'Post-Workout', protocolName: 'Deep Recovery', deviceCount: 1),
  _Preset(name: 'Evening Wind', protocolName: 'Sleep Cycle', deviceCount: 1),
];

// ---------------------------------------------------------------------------
// Protocol category helpers
// ---------------------------------------------------------------------------
Color _categoryColor(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('recover')) return ThemeConstants.success;
  if (lower.contains('perform') || lower.contains('activat')) return ThemeConstants.error;
  if (lower.contains('relax') || lower.contains('spa') || lower.contains('sleep')) {
    return const Color(0xFF8B5CF6); // purple
  }
  return ThemeConstants.info;
}

String _categoryLabel(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('recover')) return 'Recovery';
  if (lower.contains('perform') || lower.contains('activat')) return 'Performance';
  if (lower.contains('relax') || lower.contains('spa')) return 'Relaxation';
  if (lower.contains('sleep')) return 'Sleep';
  return 'General';
}

bool _isPremium(Protocol p) {
  final lower = p.templateName.toLowerCase();
  return lower.contains('pro') || lower.contains('premium') || lower.contains('deep');
}

// ===========================================================================
// PROTOCOL LIST SCREEN (Dashboard-style)
// ===========================================================================
class ProtocolListScreen extends ConsumerStatefulWidget {
  const ProtocolListScreen({super.key});

  @override
  ConsumerState<ProtocolListScreen> createState() => _ProtocolListScreenState();
}

class _ProtocolListScreenState extends ConsumerState<ProtocolListScreen> {
  _SessionGoal _activeGoal = _SessionGoal.all;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  List<Protocol> _filterProtocols(List<Protocol> protocols) {
    if (_activeGoal == _SessionGoal.all) return protocols;
    final goalLower = _activeGoal.label.toLowerCase();
    return protocols.where((p) {
      final lower = '${p.templateName} ${p.description}'.toLowerCase();
      return lower.contains(goalLower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final protocolsAsync = ref.watch(protocolListProvider);
    final userName = authState.user?.firstName ?? authState.user?.displayName ?? 'User';
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 1. HEADER ──
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: AnimatedEntrance(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting().toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeConstants.accentLight,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                userName,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeConstants.textPrimary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Plan badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                                  border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'Free Plan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ThemeConstants.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _HeaderButton(icon: Icons.bookmark_outline_rounded, onTap: () => context.push(RoutePaths.presets)),
                            const SizedBox(width: 8),
                            _HeaderButton(icon: Icons.smart_toy_outlined, onTap: () => context.push(RoutePaths.chat)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 2. DEVICE STATUS BANNER ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AnimatedEntrance(
                index: 1,
                child: _DeviceStatusBanner(
                  onConnect: () => context.go(RoutePaths.devices),
                ),
              ),
            ),
          ),

          // ── 3. QUICK PRESETS ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: AnimatedEntrance(
                index: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'QUICK PRESETS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(3, (i) {
                        final preset = i < _demoPresets.length ? _demoPresets[i] : const _Preset.empty();
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i > 0 ? 10 : 0),
                            child: _PresetButton(
                              preset: preset,
                              onTap: () => context.push(RoutePaths.presets),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 4. SESSION GOALS FILTER ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: AnimatedEntrance(
                index: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SESSION GOALS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _SessionGoal.values.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final goal = _SessionGoal.values[index];
                          final isActive = goal == _activeGoal;
                          return GestureDetector(
                            onTap: () => setState(() => _activeGoal = goal),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color: isActive ? ThemeConstants.accentDark : ThemeConstants.surface,
                                borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                                border: isActive ? null : Border.all(color: ThemeConstants.border),
                                boxShadow: isActive
                                    ? [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.3), blurRadius: 8)]
                                    : null,
                              ),
                              child: Text(
                                goal.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? Colors.white : ThemeConstants.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 5. PROTOCOL CARDS ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
              child: AnimatedEntrance(
                index: 4,
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: ThemeConstants.accent,
                        borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Protocols',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          protocolsAsync.when(
            loading: () => const SliverFillRemaining(child: HwLoading(message: 'Loading protocols...')),
            error: (e, _) => SliverFillRemaining(
              child: HwErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(protocolListProvider)),
            ),
            data: (protocols) {
              final filtered = _filterProtocols(protocols);
              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  child: HwEmptyState(icon: Icons.science_outlined, title: 'No Protocols Found'),
                );
              }

              if (isTablet) {
                // 2-column grid for tablets
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => AnimatedEntrance(
                        index: index + 5,
                        child: _ProtocolCard(protocol: filtered[index], isFreeUser: true),
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => AnimatedEntrance(
                      index: index + 5,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ProtocolCard(protocol: filtered[index], isFreeUser: true),
                      ),
                    ),
                    childCount: filtered.length,
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

// ===========================================================================
// HEADER BUTTON
// ===========================================================================
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
          border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: ThemeConstants.accent, size: 20),
      ),
    );
  }
}

// ===========================================================================
// DEVICE STATUS BANNER
// ===========================================================================
class _DeviceStatusBanner extends StatelessWidget {
  final VoidCallback onConnect;
  const _DeviceStatusBanner({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    // Demo: no devices connected
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ThemeConstants.surface, ThemeConstants.surfaceVariant],
        ),
        borderRadius: BorderRadius.circular(ThemeConstants.radiusXl),
        border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, color: ThemeConstants.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Active Devices',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ThemeConstants.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ThemeConstants.textTertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                ),
                child: const Text(
                  '0 connected',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: ThemeConstants.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'No devices connected',
            style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.bluetooth_rounded, size: 18),
              label: const Text('Connect Device'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeConstants.accent,
                side: const BorderSide(color: ThemeConstants.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// PRESET BUTTON
// ===========================================================================
class _PresetButton extends StatelessWidget {
  final _Preset preset;
  final VoidCallback onTap;
  const _PresetButton({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (preset.isEmpty) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeConstants.radiusLg),
            border: Border.all(
              color: ThemeConstants.border,
              style: BorderStyle.solid,
            ),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: ThemeConstants.textTertiary.withValues(alpha: 0.4),
              radius: ThemeConstants.radiusLg,
            ),
            child: const Center(
              child: Text(
                'Empty',
                style: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusLg),
          border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              preset.name ?? '',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.accent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              preset.protocolName ?? '',
              style: const TextStyle(fontSize: 11, color: ThemeConstants.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${preset.deviceCount} device${preset.deviceCount == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 10, color: ThemeConstants.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed border painter for empty preset slots
// ---------------------------------------------------------------------------
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// PROTOCOL CARD
// ===========================================================================
class _ProtocolCard extends StatelessWidget {
  final Protocol protocol;
  final bool isFreeUser;
  const _ProtocolCard({required this.protocol, this.isFreeUser = false});

  @override
  Widget build(BuildContext context) {
    final premium = _isPremium(protocol);
    final locked = premium && isFreeUser;
    final catColor = _categoryColor(protocol.templateName);
    final catLabel = _categoryLabel(protocol.templateName);

    return GestureDetector(
      onTap: locked ? null : () => context.push('/protocols/${protocol.id}'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusXl),
          border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Card content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top badges row
                  Row(
                    children: [
                      // Category badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                        ),
                        child: Text(
                          catLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: catColor),
                        ),
                      ),
                      if (premium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [ThemeConstants.accent, ThemeConstants.accentDark],
                            ),
                            borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.white),
                              SizedBox(width: 3),
                              Text('PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Duration badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, size: 13, color: ThemeConstants.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              protocol.totalDuration.formatted,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: ThemeConstants.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Protocol name
                  Text(
                    protocol.templateName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                  if (protocol.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      protocol.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),

                  // View Details CTA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: ThemeConstants.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Details',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeConstants.accent),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.play_arrow_rounded, size: 16, color: ThemeConstants.accent),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Premium lock overlay
            if (locked)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ThemeConstants.radiusXl),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      color: ThemeConstants.background.withValues(alpha: 0.6),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: ThemeConstants.surface,
                            borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
                            border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 16, color: ThemeConstants.accent),
                              SizedBox(width: 8),
                              Text(
                                'Upgrade to Unlock',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeConstants.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
