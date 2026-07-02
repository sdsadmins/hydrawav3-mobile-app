import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../data/notification_remote_source.dart';
import '../../domain/app_notification.dart';

/// The current user's notifications (newest first).
///
/// Live refresh: when an AI report finishes generating, the server emits a
/// `credits:update` on the /payments socket (same trigger the web uses). The
/// [tokenBalanceProvider] already listens to that socket, so re-watching it
/// here refetches notifications the moment the new one lands — no extra socket.
final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  ref.watch(tokenBalanceProvider);
  final userId = await ref.read(secureStorageProvider).getUserId();
  if (userId == null || userId.isEmpty) return const <AppNotification>[];
  return ref.read(notificationRemoteSourceProvider).getNotifications(userId);
});

/// Unread count for the AI-screen bell badge.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsProvider).maybeWhen(
        data: (list) => list.where((n) => !n.read).length,
        orElse: () => 0,
      );
});

/// Mark one notification read on the server, then refresh the list.
Future<void> markNotificationRead(WidgetRef ref, String id) async {
  await ref.read(notificationRemoteSourceProvider).markRead(id);
  ref.invalidate(notificationsProvider);
}
