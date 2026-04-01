import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/glass_container.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/utils/extensions.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';

class ProtocolListScreen extends ConsumerWidget {
  const ProtocolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocolsAsync = ref.watch(protocolListProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.cream,
      body: CustomScrollView(
        slivers: [
          // 🌊 Premium header
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
                            const Text(
                              '⚗️ Protocols',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Row(
                              children: [
                                _HeaderIconButton(
                                  icon: Icons.bookmark_outline_rounded,
                                  emoji: '📌',
                                  onTap: () => context.push(RoutePaths.presets),
                                ),
                                const SizedBox(width: 8),
                                _HeaderIconButton(
                                  icon: Icons.smart_toy_outlined,
                                  emoji: '🤖',
                                  onTap: () => context.push(RoutePaths.chat),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '🎯 Select a protocol to begin your session',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 📋 Protocol list
          protocolsAsync.when(
            loading: () => const SliverFillRemaining(
              child: HwLoading(message: '🔄 Loading protocols...'),
            ),
            error: (error, _) => SliverFillRemaining(
              child: HwErrorWidget(
                message: error.toString(),
                onRetry: () => ref.invalidate(protocolListProvider),
              ),
            ),
            data: (protocols) {
              if (protocols.isEmpty) {
                return const SliverFillRemaining(
                  child: HwEmptyState(
                    icon: Icons.science_outlined,
                    title: '🔬 No Protocols Yet',
                    subtitle:
                        'Protocols will appear here once configured on the web platform.',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(ThemeConstants.spacingMd),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
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
                          padding: const EdgeInsets.only(
                              bottom: ThemeConstants.spacingSm),
                          child: _ProtocolCard(protocol: protocols[index]),
                        ),
                      );
                    },
                    childCount: protocols.length,
                  ),
                ),
              );
            },
          ),

          // Bottom padding for nav bar
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String emoji;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Icon(icon, color: ThemeConstants.tanLight, size: 22),
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final Protocol protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => context.push('/protocols/${protocol.id}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ThemeConstants.darkTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.science_rounded,
                    color: ThemeConstants.darkTeal, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      protocol.templateName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '⏱️ ${protocol.totalDuration.formatted}  ·  🔄 ${protocol.cycles.length} cycles',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ThemeConstants.copper.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '▶️ Start',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.copper,
                  ),
                ),
              ),
            ],
          ),
          if (protocol.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              protocol.description,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
