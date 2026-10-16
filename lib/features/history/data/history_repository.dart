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
    ref: ref,
  );
});

/// The FULL session list, for consumers that need everything at once (hub
/// dashboard stats, the users screen, pending-outcomes sync) rather than the
/// History tab's incremental scroll — those never paged before this endpoint
/// required pagination, to keep their behaviour unchanged. Filtered to the
/// signed-in practitioner's own sessions (createdBy may be numeric in the
/// backend, so compared via string form), same as before.
///
/// The backend caps `perPage` at 100 regardless of what's requested (echoes
/// `perPage: 100` back even when asked for 500), so a large org genuinely
/// needs multiple requests — fetching them one at a time was the actual
/// source of "the client tab takes forever": 5 sequential round trips for a
/// 484-session org. Page 1 is fetched alone (it's the only way to learn
/// `totalPages`), then every remaining page fires CONCURRENTLY via
/// `Future.wait` instead of awaited one by one — wall-clock time drops from
/// roughly `pages × latency` to about `2 × latency`.
final allSessionsProvider =
    FutureProvider.autoDispose<List<SessionHistoryItem>>((ref) async {
  final auth = ref.read(authStateProvider);
  final orgId = auth.selectedOrgId;
  if (orgId == null || orgId.isEmpty) return const [];

  const chunk = 100;
  final repo = ref.read(historyRepositoryProvider);
  final first = await repo.getAllSessions(orgId, page: 1, perPage: chunk);
  final all = <SessionHistoryItem>[...first.items];

  if (first.totalPages > 1) {
    final rest = await Future.wait([
      for (var page = 2; page <= first.totalPages; page++)
        repo.getAllSessions(orgId, page: page, perPage: chunk),
    ]);
    for (final page in rest) {
      all.addAll(page.items);
    }
  }

  final userId = auth.user?.id;
  if (userId == null || userId.isEmpty) return all;
  return all
      .where((s) => s.createdBy != null && s.createdBy == userId)
      .toList();
});

/// Scroll-paginated state for the "All" history tab
/// (`GET /intake/all/:organizationId?page=&perPage=`).
class HistoryPageState {
  final List<SessionHistoryItem> items;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  const HistoryPageState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  HistoryPageState copyWith({
    List<SessionHistoryItem>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return HistoryPageState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the "All" history tab's infinite scroll. Filters to the
/// signed-in practitioner's own sessions client-side (createdBy may be
/// numeric in the backend, so compared via string form) — same behaviour
/// the old single-shot [FutureProvider] had, just applied per page now.
class HistoryPagingNotifier extends StateNotifier<HistoryPageState> {
  HistoryPagingNotifier(this._ref) : super(const HistoryPageState()) {
    loadFirstPage();
  }

  final Ref _ref;
  static const _perPage = 10;

  String? get _organizationId => _ref.read(authStateProvider).selectedOrgId;
  String? get _userId => _ref.read(authStateProvider).user?.id;

  List<SessionHistoryItem> _filterOwn(List<SessionHistoryItem> raw) {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return raw;
    return raw.where((s) => s.createdBy != null && s.createdBy == userId).toList();
  }

  Future<void> loadFirstPage() async {
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) {
      state = const HistoryPageState(hasMore: false);
      return;
    }
    state = const HistoryPageState(isLoading: true);
    try {
      final result = await _ref
          .read(historyRepositoryProvider)
          .getAllSessions(orgId, page: 1, perPage: _perPage);
      state = HistoryPageState(
        items: _filterOwn(result.items),
        page: 1,
        hasMore: result.hasNextPage,
      );
    } catch (e) {
      state = HistoryPageState(error: e, hasMore: false);
    }
  }

  /// Called by the list's scroll listener near the bottom. No-op while
  /// already loading or once the backend returned a short (final) page.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final nextPage = state.page + 1;
      final result = await _ref
          .read(historyRepositoryProvider)
          .getAllSessions(orgId, page: nextPage, perPage: _perPage);
      state = state.copyWith(
        items: [...state.items, ..._filterOwn(result.items)],
        page: nextPage,
        hasMore: result.hasNextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      // Leave existing items in place — only surface the error via a flag
      // the list can show as a small inline retry, not a full-screen error.
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  Future<void> refresh() => loadFirstPage();
}

final historyPagingProvider =
    StateNotifierProvider.autoDispose<HistoryPagingNotifier, HistoryPageState>(
        (ref) {
  return HistoryPagingNotifier(ref);
});

/// One client's sessions, newest first (`GET /intake/client/:clientId`).
///
/// Unlike [allSessionsProvider] this is **not** filtered to the signed-in
/// practitioner — a client's history is theirs regardless of who ran each
/// session, which is what a portfolio needs to show.
final clientHistoryProvider =
    FutureProvider.autoDispose.family<List<SessionHistoryItem>, String>(
        (ref, clientId) async {
  if (clientId.isEmpty) return const [];
  final list =
      await ref.read(historyRepositoryProvider).getClientHistory(clientId);
  list.sort((a, b) {
    final ad = a.createdAt;
    final bd = b.createdAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return list;
});

class HistoryRepository {
  final HistoryRemoteSource _remoteSource;
  final AppDatabase _db;
  final Ref _ref;

  HistoryRepository({
    required HistoryRemoteSource remoteSource,
    required AppDatabase db,
    required Ref ref,
  })  : _remoteSource = remoteSource,
        _db = db,
        _ref = ref;

  bool get _isOnline => _ref.read(isOnlineProvider);

  /// Watch local sessions (always available, offline-safe).
  Stream<List<LocalSession>> watchLocalSessions() => _db.watchLocalSessions();

  /// Get one page of saved sessions for an organization (online only).
  Future<IntakePage> getAllSessions(
    String organizationId, {
    int page = 1,
    int perPage = 10,
  }) async {
    if (!_isOnline) {
      return const IntakePage(
          items: [], hasNextPage: false, total: 0, totalPages: 0);
    }
    return _remoteSource.getAllIntakes(
      organizationId,
      page: page,
      perPage: perPage,
    );
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
