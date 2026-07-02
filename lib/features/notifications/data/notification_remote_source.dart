import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../domain/app_notification.dart';

final notificationRemoteSourceProvider =
    Provider<NotificationRemoteSource>((ref) {
  return NotificationRemoteSource(ref.read(nodeDioProvider));
});

/// Talks to the Node notifications endpoints (web parity: actions/notification.ts).
class NotificationRemoteSource {
  final Dio _dio;

  NotificationRemoteSource(this._dio);

  /// `GET notifications/:userId` — newest first (server sorts).
  Future<List<AppNotification>> getNotifications(String userId) async {
    final res = await _dio.get(ApiEndpoints.notificationsByUser(userId));
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['data'] is List)
            ? data['data'] as List
            : (data is Map && data['notifications'] is List)
                ? data['notifications'] as List
                : const [];
    final items = list
        .whereType<Map>()
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    // Ensure newest-first regardless of server order.
    items.sort((a, b) => (b.createdAt ?? DateTime(0))
        .compareTo(a.createdAt ?? DateTime(0)));
    return items;
  }

  /// `POST notifications/read/:id` — marks a single notification read.
  Future<void> markRead(String id) async {
    await _dio.post(ApiEndpoints.notificationRead(id));
  }
}
