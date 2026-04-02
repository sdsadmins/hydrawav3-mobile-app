import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_loading.dart';

class _DemoSession {
  final String id, protocolName, date, duration;
  final bool synced;
  _DemoSession(this.id, this.protocolName, this.date, this.duration, this.synced);
}

final _demoSessions = [
  _DemoSession('s1', 'Full Body Recovery', '1 Apr 2026', '15:00', true),
  _DemoSession('s2', 'Lower Back Relief', '31 Mar 2026', '16:00', true),
  _DemoSession('s3', 'Neck & Shoulder', '30 Mar 2026', '09:00', false),
  _DemoSession('s4', 'Athletic Performance', '28 Mar 2026', '30:00', true),
  _DemoSession('s5', 'Relaxation', '26 Mar 2026', '10:00', true),
];

class HistoryListScreen extends ConsumerWidget {
  const HistoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Session History')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _demoSessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final s = _demoSessions[index];
          return Material(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => context.push('/history/${s.id}'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: ThemeConstants.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.play_circle_outline_rounded, color: ThemeConstants.accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.protocolName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('${s.date}  ·  ${s.duration}', style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                        ],
                      ),
                    ),
                    Icon(s.synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 18, color: s.synced ? ThemeConstants.success : ThemeConstants.textTertiary),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
