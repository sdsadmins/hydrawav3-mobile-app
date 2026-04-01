import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/glass_container.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/utils/extensions.dart';

final localSessionsProvider = StreamProvider<List<LocalSession>>((ref) {
  return ref.read(databaseProvider).watchLocalSessions();
});

class HistoryListScreen extends ConsumerWidget {
  const HistoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(localSessionsProvider);

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
                        const Text('📊 History',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Text(
                          '📈 Track your therapy progress',
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
          sessionsAsync.when(
            loading: () => const SliverFillRemaining(
                child: HwLoading(message: '🔄 Loading sessions...')),
            error: (error, _) => SliverFillRemaining(
                child: HwErrorWidget(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(localSessionsProvider))),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const SliverFillRemaining(
                  child: HwEmptyState(
                    icon: Icons.history_rounded,
                    title: '📭 No Sessions Yet',
                    subtitle:
                        'Complete your first therapy session and it will appear here.',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(ThemeConstants.spacingMd),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final session = sessions[index];
                      final duration =
                          Duration(seconds: session.elapsedSeconds);
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 400 + index * 60),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - value)),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            onTap: () =>
                                context.push('/history/${session.id}'),
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: ThemeConstants.darkTeal
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                      Icons.play_circle_outline_rounded,
                                      color: ThemeConstants.darkTeal,
                                      size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('🧪 ${session.protocolName}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '📅 ${_formatDate(session.completedAt)}  ·  ⏱️ ${duration.formatted}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  session.synced
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_off_rounded,
                                  color: session.synced
                                      ? ThemeConstants.success
                                      : ThemeConstants.warning,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: sessions.length,
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

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
