import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../history/data/history_repository.dart';
import '../../data/session_repository.dart';
import '../../domain/pending_session_outcome_model.dart';
import '../../domain/question_answer_model.dart';
import '../../domain/session_model.dart';

/// Queue of completed sessions awaiting a post-session outcomes review.
///
/// Persisted to SharedPreferences so a "needs review" session survives its live
/// card being dropped from the feed (Protocol Plus off-screen stops, another
/// client stopping it, app restart). Entries are removed only when the user
/// submits or skips (i.e. the `/intake` record is finalized).
final pendingOutcomesProvider = StateNotifierProvider<PendingOutcomesNotifier,
    List<PendingSessionOutcome>>((ref) {
  return PendingOutcomesNotifier(ref);
});

class PendingOutcomesNotifier
    extends StateNotifier<List<PendingSessionOutcome>> {
  final Ref _ref;
  static const _key = 'pending_session_outcomes';

  /// Sessions whose after-screen is on screen RIGHT NOW. Their auto-save is held
  /// back until the screen is left, so the answer the user is about to give
  /// still makes it into the single `/intake` POST.
  final Set<String> _underReview = {};

  PendingOutcomesNotifier(this._ref) : super([]) {
    _load();
  }

  /// Mark/unmark a session as being reviewed on the after-screen.
  void markUnderReview(String sessionId) => _underReview.add(sessionId);
  void clearUnderReview(String sessionId) => _underReview.remove(sessionId);
  bool isUnderReview(String sessionId) => _underReview.contains(sessionId);

  void _load() {
    try {
      final raw = _ref.read(sharedPreferencesProvider).getString(_key) ?? '[]';
      final list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) =>
              PendingSessionOutcome.fromJson(e as Map<String, dynamic>))
          .toList();
      if (state.isNotEmpty) {
        appLogger.i('Loaded ${state.length} pending session outcomes');
      }
    } catch (e) {
      appLogger.e('Failed to load pending outcomes: $e');
    }
  }

  Future<void> _save() async {
    try {
      final raw = jsonEncode(state.map((e) => e.toJson()).toList());
      await _ref.read(sharedPreferencesProvider).setString(_key, raw);
    } catch (e) {
      appLogger.e('Failed to save pending outcomes: $e');
    }
  }

  PendingSessionOutcome? getById(String sessionId) {
    for (final e in state) {
      if (e.sessionId == sessionId) return e;
    }
    return null;
  }

  bool contains(String sessionId) => getById(sessionId) != null;

  /// Entries still awaiting an answer (drives the "Needs review" cards + the
  /// Stop All / Done prompt). Once answered, an entry is hidden here — it only
  /// lingers in [state] as a `syncPending` retry, never re-prompting the user.
  List<PendingSessionOutcome> get needsReview =>
      state.where((e) => e.answers == null).toList();

  /// The unanswered entry for a session, or null if none / already answered.
  PendingSessionOutcome? needsReviewById(String sessionId) {
    final e = getById(sessionId);
    return (e != null && e.answers == null) ? e : null;
  }

  /// Add a snapshot to the queue. No-op if one already exists for the session
  /// (idempotent — terminal transitions can fire more than once).
  Future<void> enqueue(PendingSessionOutcome snapshot) async {
    if (contains(snapshot.sessionId)) return;
    state = [...state, snapshot];
    await _save();
    appLogger.i('Queued session for outcomes review: ${snapshot.sessionId}');
  }

  Future<void> remove(String sessionId) async {
    state = state.where((e) => e.sessionId != sessionId).toList();
    await _save();
  }

  /// Finalize a review: build the intake record from the snapshot + answers,
  /// POST it once, and drop the entry. On POST failure the entry is retained
  /// (marked `syncPending`) so `drainSyncPending` can retry later.
  ///
  /// `outcomes` is null for a plain "Skip" (logs the session with no answers).
  ///
  /// [isRetry] re-posts an entry that is already marked answered — the path
  /// [drainSyncPending] uses. Without it the "already answered" guard below
  /// rejected every retry, so an outcome whose POST failed once was never sent
  /// again and never appeared in history.
  Future<void> finalize(
    String sessionId,
    PostSessionOutcomes? outcomes, {
    bool isRetry = false,
  }) async {
    final entry = getById(sessionId);
    if (entry == null) return; // gone
    if (entry.answers != null && !isRetry) return; // already answered

    // Mark answered IMMEDIATELY (even before the POST resolves) so it can never
    // re-prompt on Stop All or re-appear as a "Needs review" card. It stays in
    // the queue only as a `syncPending` retry until the POST succeeds.
    final answered = entry.copyWith(
      answers: outcomes ?? const PostSessionOutcomes(),
      syncPending: true,
    );
    state = [
      for (final e in state) e.sessionId == sessionId ? answered : e,
    ];
    await _save();

    final userId = _ref.read(authStateProvider).user?.id;
    final record = SessionRecord.fromPending(
      entry,
      outcomes,
      createdBy: userId,
      updatedBy: userId,
    );
    final ok = await _ref.read(sessionRepositoryProvider).finalizeSession(record);
    if (ok) {
      await remove(sessionId); // fully done — drop the retry entry
      // The intake now exists server-side; drop the cached history so the
      // session (and its outcome check) shows up straight away instead of on
      // the next cold start.
      _ref.invalidate(allSessionsProvider);
    } else {
      appLogger.w('Finalize POST failed; kept $sessionId (answered) for retry');
    }
  }

  /// Retry any answered-but-unsynced entries (e.g. after reconnect).
  Future<void> drainSyncPending() async {
    final pending = state.where((e) => e.syncPending).toList();
    for (final entry in pending) {
      await finalize(entry.sessionId, entry.answers, isRetry: true);
    }
  }

  /// Save a finished session to history WITHOUT waiting for the user — the
  /// automatic log that runs the moment a run ends (or when the after-screen is
  /// left without answering). A session that already carries answers, or one
  /// whose after-screen is still open, is left alone.
  ///
  /// [outcomes] carries whatever the user did manage to answer; null logs the
  /// session bare. Either way the record lands in history with no button tap.
  Future<void> autoLog(
    String sessionId, {
    PostSessionOutcomes? outcomes,
    bool force = false,
  }) async {
    final entry = getById(sessionId);
    if (entry == null || entry.answers != null) return;
    if (!force && _underReview.contains(sessionId)) return;
    _underReview.remove(sessionId);
    await finalize(sessionId, outcomes);
  }

  /// Auto-log every queued session nobody is reviewing. Runs on app start /
  /// History open so a run whose after-screen was never reached (app killed,
  /// off-screen end in a previous run) still reaches history on its own.
  Future<void> autoLogUnreviewed() async {
    for (final entry in [...state]) {
      if (entry.answers != null) continue;
      if (_underReview.contains(entry.sessionId)) continue;
      await finalize(entry.sessionId, null);
    }
  }
}
