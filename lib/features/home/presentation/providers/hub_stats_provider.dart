import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/session_history_model.dart';

/// Everything the Hub's numeric surfaces read, derived from real session
/// history. Nothing here is seeded or estimated — a field is null/empty when
/// the data genuinely doesn't exist yet, and the Hub renders the spec's
/// empty-state copy for it.
class HubStats {
  /// Sessions logged today (ring 1).
  final int sessionsToday;

  /// Distinct days with at least one session in the last 7 (ring 3).
  final int activeDays7d;

  /// Share of this week's answered post-session outcome questions that came
  /// back "good" (preset answer rank >= 4 of 5), 0–100. Null when no ranked
  /// question has been answered yet (ring 2 sits at zero and the card shows
  /// its first-run line).
  final int? pulsePct;

  /// How many before/after checks that percentage is drawn from.
  final int pulseTotal;

  /// Guest sessions logged today — drives the roster nudge at >= 3.
  final int guestToday;

  /// Most recent session, or null when there is no history at all.
  final SessionHistoryItem? lastSession;

  const HubStats({
    this.sessionsToday = 0,
    this.activeDays7d = 0,
    this.pulsePct,
    this.pulseTotal = 0,
    this.guestToday = 0,
    this.lastSession,
  });
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Hub numbers, computed from `GET /intake/all`.
final hubStatsProvider = Provider.autoDispose<AsyncValue<HubStats>>((ref) {
  return ref.watch(allSessionsProvider).whenData(_computeStats);
});

HubStats _computeStats(List<SessionHistoryItem> sessions) {
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));

  var sessionsToday = 0;
  var guestToday = 0;
  var improved = 0;
  var checks = 0;
  final activeDays = <String>{};
  SessionHistoryItem? last;

  for (final s in sessions) {
    final at = s.createdAt;
    if (at == null) continue;

    if (last == null || at.isAfter(last.createdAt!)) last = s;

    if (_isSameDay(at, now)) {
      sessionsToday++;
      if (s.isGuest) guestToday++;
    }

    if (at.isAfter(weekAgo)) {
      activeDays.add('${at.year}-${at.month}-${at.day}');

      // The Outcome Pulse: each answered post-session preset question is a
      // "check". Rank 1-5 (higher = better outcome, see QuestionAnswer) — a
      // rank of 4 or 5 counts as "YES". Free-text answers (rank 0) carry no
      // quality signal and aren't counted either way.
      for (final p in s.protocols) {
        for (final qa in p.questionAnswers) {
          if (qa.rank <= 0) continue;
          checks++;
          if (qa.rank >= 4) improved++;
        }
      }
    }
  }

  return HubStats(
    sessionsToday: sessionsToday,
    activeDays7d: activeDays.length,
    pulsePct: checks == 0 ? null : ((improved / checks) * 100).round(),
    pulseTotal: checks,
    guestToday: guestToday,
    lastSession: last,
  );
}

/// The Game Ready board: who on the roster has had a session run on them today.
///
/// The spec's rule (`Hydrawav3_UI_v2_Redesign_Plan.md` §8.1) is deliberately
/// completion-based, not score-based — a finished session is a fact. Guest
/// sessions have no name, so they can't count toward the board.
class GameReadyBoard {
  final List<Client> prepped;
  final List<Client> remaining;

  const GameReadyBoard({this.prepped = const [], this.remaining = const []});

  int get total => prepped.length + remaining.length;
  bool get hasRoster => total > 0;
  double get fraction => total == 0 ? 0 : prepped.length / total;
}

final gameReadyBoardProvider =
    Provider.autoDispose<AsyncValue<GameReadyBoard>>((ref) {
  final clients = ref.watch(clientListProvider);
  final sessions = ref.watch(allSessionsProvider);

  if (clients.isLoading || sessions.isLoading) {
    return const AsyncValue.loading();
  }
  if (clients.hasError) {
    return AsyncValue.error(clients.error!, clients.stackTrace!);
  }
  if (sessions.hasError) {
    return AsyncValue.error(sessions.error!, sessions.stackTrace!);
  }

  final now = DateTime.now();
  final preppedIds = <String>{
    for (final s in sessions.value ?? const <SessionHistoryItem>[])
      if (!s.isGuest &&
          s.clientId != null &&
          s.createdAt != null &&
          _isSameDay(s.createdAt!, now))
        s.clientId!,
  };

  final roster =
      (clients.value ?? const <Client>[]).where((c) => c.isPlayer).toList();

  return AsyncValue.data(GameReadyBoard(
    prepped: roster.where((c) => preppedIds.contains(c.id)).toList(),
    remaining: roster.where((c) => !preppedIds.contains(c.id)).toList(),
  ));
});
