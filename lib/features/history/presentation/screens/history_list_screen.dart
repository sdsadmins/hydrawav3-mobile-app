import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';

class _Session {
  final String id, protocol, date, duration;
  final bool synced;
  final int discomfortBefore, discomfortAfter;
  _Session(this.id, this.protocol, this.date, this.duration, this.synced, this.discomfortBefore, this.discomfortAfter);
}

final _sessions = [
  _Session('s1', 'Full Body Recovery', '1 Apr 2026', '15:00', true, 7, 3),
  _Session('s2', 'Lower Back Relief', '31 Mar 2026', '16:00', true, 6, 2),
  _Session('s3', 'Neck & Shoulder', '30 Mar 2026', '09:00', false, 5, 4),
  _Session('s4', 'Athletic Performance', '28 Mar 2026', '30:00', true, 8, 3),
  _Session('s5', 'Relaxation', '26 Mar 2026', '10:00', true, 4, 1),
];

class HistoryListScreen extends ConsumerWidget {
  const HistoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // Header
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Session History', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        const Text('Track your therapy progress', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                        const SizedBox(height: 16),
                        // Summary stats
                        Row(children: [
                          _SummaryChip(value: '${_sessions.length}', label: 'Sessions', icon: Icons.play_circle_outline_rounded),
                          const SizedBox(width: 10),
                          const _SummaryChip(value: '-4.2', label: 'Avg Relief', icon: Icons.trending_down_rounded),
                          const SizedBox(width: 10),
                          const _SummaryChip(value: '1h 20m', label: 'Total Time', icon: Icons.timer_outlined),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Sessions
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => AnimatedEntrance(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SessionCard(session: _sessions[i]),
                  ),
                ),
                childCount: _sessions.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _SummaryChip({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 18),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: ThemeConstants.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final _Session session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final improvement = session.discomfortBefore - session.discomfortAfter;
    return GradientCard(
      onTap: () => context.push('/history/${session.id}'),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const GlowIconBox(icon: Icons.play_circle_outline_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.protocol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${session.date}  ·  ${session.duration}', style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ThemeConstants.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('-$improvement', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ThemeConstants.success)),
              ),
              const SizedBox(height: 4),
              Icon(session.synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 14, color: session.synced ? ThemeConstants.success.withValues(alpha: 0.5) : ThemeConstants.textTertiary),
            ],
          ),
        ],
      ),
    );
  }
}
