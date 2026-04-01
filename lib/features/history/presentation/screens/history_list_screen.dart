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
      appBar: AppBar(title: const Text('Session History')),
      body: sessionsAsync.when(
        loading: () => const HwLoading(message: 'Loading history...'),
        error: (error, _) => HwErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(localSessionsProvider),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const HwEmptyState(
              icon: Icons.history,
              title: 'No Sessions Yet',
              subtitle:
                  'Your session history will appear here after your first session.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(ThemeConstants.spacingMd),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final duration = Duration(seconds: session.elapsedSeconds);
              return Card(
                margin:
                    const EdgeInsets.only(bottom: ThemeConstants.spacingSm),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        ThemeConstants.primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.play_circle,
                        color: ThemeConstants.primaryColor),
                  ),
                  title: Text(session.protocolName),
                  subtitle: Text(
                    '${_formatDate(session.completedAt)} - ${duration.formatted}',
                  ),
                  trailing: session.synced
                      ? const Icon(Icons.cloud_done,
                          color: ThemeConstants.success, size: 20)
                      : const Icon(Icons.cloud_off,
                          color: ThemeConstants.warning, size: 20),
                  onTap: () => context.push('/history/${session.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
