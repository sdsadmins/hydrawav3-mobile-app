import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/storage/local_db.dart';
import '../domain/session_history_model.dart';
import 'history_remote_source.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(
    remoteSource: ref.read(historyRemoteSourceProvider),
    db: ref.read(databaseProvider),
    isOnline: ref.read(isOnlineProvider),
  );
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
  Stream<List<LocalSession>> watchLocalSessions() =>
      _db.watchLocalSessions();

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
