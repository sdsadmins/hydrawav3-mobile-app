import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/extensions.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart'; // ✅ ADDED

class ProtocolListScreen extends ConsumerWidget {
  const ProtocolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocolsAsync = ref.watch(protocolListProvider);
    final auth = ref.watch(authStateProvider); // ✅ ADDED

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Premium gradient header
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Protocols',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                /// ✅ ORGANIZATION NAME ADDED HERE
                                Text(
                                  auth.selectedOrgName ?? "No Organization",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: ThemeConstants.accent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text(
                                  'Select a protocol to begin',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: ThemeConstants.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            Row(children: [
                              _HeaderButton(
                                icon: Icons.bookmark_outline_rounded,
                                onTap: () =>
                                    context.push(RoutePaths.presets),
                              ),
                              const SizedBox(width: 8),
                              _HeaderButton(
                                icon: Icons.smart_toy_outlined,
                                onTap: () =>
                                    context.push(RoutePaths.chat),
                              ),
                            ]),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Protocol list
          protocolsAsync.when(
            loading: () => const SliverFillRemaining(
                child: HwLoading(message: 'Loading protocols...')),
            error: (e, _) => SliverFillRemaining(
                child: HwErrorWidget(
                    message: e.toString(),
                    onRetry: () =>
                        ref.invalidate(protocolListProvider))),
            data: (protocols) {
              if (protocols.isEmpty) {
                return const SliverFillRemaining(
                    child: HwEmptyState(
                        icon: Icons.science_outlined,
                        title: 'No Protocols Yet'));
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
                          child:
                              _ProtocolCard(protocol: protocols[index]),
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

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderButton(
      {required this.icon, required this.onTap});

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
              color:
                  ThemeConstants.accent.withValues(alpha: 0.15)),
        ),
        child:
            Icon(icon, color: ThemeConstants.accent, size: 20),
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
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(protocol.templateName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    if (protocol.description.isNotEmpty)
                      Text(
                        protocol.description,
                        style: const TextStyle(
                            fontSize: 13,
                            color:
                                ThemeConstants.textSecondary,
                            height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: ThemeConstants.textTertiary,
                  size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatChip(
                  icon: Icons.timer_outlined,
                  value: protocol.totalDuration.formatted),
              const SizedBox(width: 8),
              StatChip(
                  icon: Icons.repeat_rounded,
                  value: '${protocol.cycles.length}',
                  label: 'cycles'),
              const SizedBox(width: 8),
              StatChip(
                  icon: Icons.play_circle_outline_rounded,
                  value: '${protocol.sessions}',
                  label: 'sess'),
            ],
          ),
        ],
      ),
    );
  }
}