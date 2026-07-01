import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/storage/local_db.dart';
import '../domain/session_history_model.dart';
import 'history_remote_source.dart';
import '../../auth/presentation/providers/auth_provider.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(
    remoteSource: ref.read(historyRemoteSourceProvider),
    db: ref.read(databaseProvider),
    isOnline: ref.read(isOnlineProvider),
  );
});

/// All saved sessions fetched from the backend database (`GET /intake/all`).
final allSessionsProvider =
    FutureProvider.autoDispose<List<SessionHistoryItem>>((ref) async {
  final auth = ref.read(authStateProvider);
  final userId = auth.user?.id;
  final all = await ref.read(historyRepositoryProvider).getAllSessions();
  // If no logged-in user id, return everything (fallback).
  if (userId == null || userId.isEmpty) return all;
  // Only show sessions that were created by this user (createdBy may be numeric
  // in the backend, so compare via string form).
  return all
      .where((s) => s.createdBy != null && s.createdBy == userId)
      .toList();
});

class HistoryRepository {
  final HistoryRemoteSource _remoteSource;
  final AppDatabase _db;
  final bool _isOnline;

  HistoryRepository({
    required HistoryRemoteSource remoteSource,
    required AppDatabase db,
    required bool isOnline,
  })  : _remoteSource = remoteSource,
        _db = db,
        _isOnline = isOnline;

  /// Watch local sessions (always available, offline-safe).
  Stream<List<LocalSession>> watchLocalSessions() => _db.watchLocalSessions();

  /// Get every saved session from the backend database (online only).
  Future<List<SessionHistoryItem>> getAllSessions() async {
    if (!_isOnline) return [];
    return _remoteSource.getAllIntakes();
  }

  /// Get remote history for a client (online only).
  Future<List<SessionHistoryItem>> getClientHistory(
    String clientId, {
    int page = 1,
  }) async {
    if (!_isOnline) return [];
    return _remoteSource.getClientHistory(clientId, page: page);
  }

  /// Get dashboard stats (online only).
  Future<DashboardStats> getDashboard(String orgId) async {
    if (!_isOnline) {
      return const DashboardStats();
    }
    return _remoteSource.getDashboard(orgId);
  }
}
