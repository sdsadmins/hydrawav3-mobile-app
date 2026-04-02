import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
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
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Session History')),
      body: sessionsAsync.when(
        loading: () => const HwLoading(message: 'Loading history...'),
        error: (e, _) => HwErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(localSessionsProvider)),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const HwEmptyState(icon: Icons.history_rounded, title: 'No Sessions Yet', subtitle: 'Complete a session and it will appear here.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final dur = Duration(seconds: s.elapsedSeconds);
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
                              Text('${_fmtDate(s.completedAt)}  ·  ${dur.formatted}', style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
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
          );
        },
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
