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

  /// Every ranked post-session check across all history, oldest first — the
  /// raw material for the Usage card's 7D / 30D / ALL score and its graph.
  final List<PulseCheck> checks;

  /// Sessions on record (the Usage card's "N completed sessions").
  final int sessionsTotal;

  /// Device time across all sessions, in hours. Summed from the per-protocol
  /// durations the backend records; zero when none carry a duration.
  final double hoursUsed;

  /// The protocol run most often, with its count. Null with no history.
  final ({String name, int count})? topProtocol;

  const HubStats({
    this.sessionsToday = 0,
    this.activeDays7d = 0,
    this.pulsePct,
    this.pulseTotal = 0,
    this.guestToday = 0,
    this.lastSession,
    this.checks = const [],
    this.sessionsTotal = 0,
    this.hoursUsed = 0,
    this.topProtocol,
  });
}

/// One answered post-session question: when, and whether it came back "good".
class PulseCheck {
  final DateTime at;
  final bool improved;
  const PulseCheck(this.at, this.improved);
}

/// Share of [checks] that improved, as 0–100 (null when there are none),
/// with the raw counts behind it.
({int? pct, int total, int yes}) scoreOf(Iterable<PulseCheck> checks) {
  var yes = 0;
  var total = 0;
  for (final c in checks) {
    total++;
    if (c.improved) yes++;
  }
  return (
    pct: total == 0 ? null : (yes / total * 100).round(),
    total: total,
    yes: yes,
  );
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
  final allChecks = <PulseCheck>[];
  var seconds = 0;
  final protocolCounts = <String, int>{};

  for (final s in sessions) {
    for (final p in s.protocols) {
      seconds += p.duration ?? 0;
      final name = (p.protocol ?? '').trim();
      if (name.isNotEmpty) {
        protocolCounts[name] = (protocolCounts[name] ?? 0) + 1;
      }
    }

    final at = s.createdAt;
    if (at == null) continue;

    for (final p in s.protocols) {
      for (final qa in p.questionAnswers) {
        if (qa.rank <= 0) continue;
        allChecks.add(PulseCheck(at, qa.rank >= 4));
      }
    }

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

  allChecks.sort((a, b) => a.at.compareTo(b.at));
  final top = protocolCounts.entries.isEmpty
      ? null
      : protocolCounts.entries.reduce((a, b) => b.value > a.value ? b : a);

  return HubStats(
    sessionsToday: sessionsToday,
    activeDays7d: activeDays.length,
    pulsePct: checks == 0 ? null : ((improved / checks) * 100).round(),
    pulseTotal: checks,
    guestToday: guestToday,
    lastSession: last,
    checks: allChecks,
    sessionsTotal: sessions.length,
    hoursUsed: seconds / 3600,
    topProtocol: top == null ? null : (name: top.key, count: top.value),
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

// ---------------------------------------------------------------------------
// Game Prep (v5 `20-gameprep.js`)
// ---------------------------------------------------------------------------

/// One player on the Game Prep board.
class GamePrepRow {
  final Client client;

  /// Position in the roster — picks the player's pastel avatar tint.
  final int index;

  /// Today's session, when there is one ("Prepped ✓ · 9:40 AM").
  final SessionHistoryItem? today;

  /// Their most recent session of any day, or null before the first.
  final SessionHistoryItem? last;

  /// Whole days since [last]; null before the first session.
  final int? daysSince;

  const GamePrepRow({
    required this.client,
    required this.index,
    this.today,
    this.last,
    this.daysSince,
  });

  bool get prepped => today != null;
}

class GamePrepData {
  final List<GamePrepRow> prepped;

  /// Still to prep, longest since a session first (never-run players lead).
  final List<GamePrepRow> left;

  /// Distinct sports on the roster, for the team filter chips.
  final List<String> teams;

  const GamePrepData({
    this.prepped = const [],
    this.left = const [],
    this.teams = const [],
  });

  int get total => prepped.length + left.length;
}

/// "Prepped" = a session run on the player today. Completion-based, like the
/// Game Ready board: a finished session is a fact, a score is not.
final gamePrepProvider =
    Provider.autoDispose.family<AsyncValue<GamePrepData>, String?>((ref, team) {
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

  final players =
      (clients.value ?? const <Client>[]).where((c) => c.isPlayer).toList();
  final teams = <String>{
    for (final p in players)
      if ((p.sport ?? '').trim().isNotEmpty) p.sport!.trim(),
  }.toList()
    ..sort();

  final byClient = <String, List<SessionHistoryItem>>{};
  for (final s in sessions.value ?? const <SessionHistoryItem>[]) {
    if (s.isGuest || s.clientId == null || s.createdAt == null) continue;
    byClient.putIfAbsent(s.clientId!, () => []).add(s);
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final rows = <GamePrepRow>[];
  for (var i = 0; i < players.length; i++) {
    final p = players[i];
    if (team != null && (p.sport ?? '').trim() != team) continue;
    final mine = [...?byClient[p.id]]
      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    final last = mine.isEmpty ? null : mine.first;
    final lastDay = last == null
        ? null
        : DateTime(
            last.createdAt!.year, last.createdAt!.month, last.createdAt!.day);
    rows.add(GamePrepRow(
      client: p,
      index: i,
      today: lastDay == today ? last : null,
      last: last,
      daysSince: lastDay == null ? null : today.difference(lastDay).inDays,
    ));
  }

  final left = rows.where((r) => !r.prepped).toList()
    ..sort(
        (a, b) => (b.daysSince ?? 1 << 30).compareTo(a.daysSince ?? 1 << 30));
  return AsyncValue.data(GamePrepData(
    prepped: rows.where((r) => r.prepped).toList(),
    left: left,
    teams: teams,
  ));
});
