import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/active_session_model.dart';
import '../../domain/pending_session_outcome_model.dart';
import '../providers/active_sessions_provider.dart';
import '../providers/pending_outcomes_provider.dart';

/// App-wide presenter for the post-session screen.
///
/// A run goes terminal in exactly one place — [SessionEngine], which queues a
/// snapshot on [pendingOutcomesProvider] whether or not the live card happens to
/// be on screen. This gate watches that queue and opens `#scr-ready-after` from
/// wherever the user is, so every ending looks the same:
///
///   * finished while watching the live card  → the card is replaced by it
///   * finished while on the devices list / hub → it opens on top
///   * finished while the live card was open in remote view → it opens on top
///
/// Before this existed only the first case worked: the live card owned the
/// navigation, so a run the user had walked away from (or was watching in remote
/// view) ended silently and only left a "Needs review" card on History.
///
/// Mounted once, above the router, from `HydrawavApp`.
class SessionOutcomeGate extends ConsumerStatefulWidget {
  final Widget child;

  const SessionOutcomeGate({super.key, required this.child});

  @override
  ConsumerState<SessionOutcomeGate> createState() => _SessionOutcomeGateState();
}

class _SessionOutcomeGateState extends ConsumerState<SessionOutcomeGate> {
  /// Sessions already routed to. Seeded with whatever survived from a previous
  /// app run so a cold start never opens straight onto an old session's
  /// after-screen — those are auto-logged instead (see [_drainStaleOnStart]).
  final Set<String> _handled = {};

  /// Routes where popping an after-screen would be wrong: the auth flow and the
  /// at-home client surface (which runs its own session UI).
  static const _blockedPrefixes = <String>[
    RoutePaths.login,
    RoutePaths.signup,
    RoutePaths.onboarding,
    RoutePaths.forgotPassword,
    RoutePaths.resetPassword,
    RoutePaths.clientHome,
    '/select-organization',
  ];

  /// Safety-net poll — every 2s, independent of and redundant with whatever
  /// the engine's own internal completion detection is doing. Several
  /// different internal paths are each individually responsible for noticing
  /// a session has gone terminal and queuing its outcome (device e-stop,
  /// device rs=stop, the local per-device duration clock, an app-initiated
  /// stop...) — history has shown that's fragile: a gap in ANY of those
  /// paths silently means "never shows the post-session screen" for whatever
  /// case that gap covers. This watchdog doesn't care which internal path
  /// works or is broken: it looks at wall-clock time alone (createdAt +
  /// totalDurationSeconds, both already stored on [ActiveSession], no live
  /// engine needed) and force-queues the outcome once a session is well past
  /// when it should have ended, whether or not anything else already did.
  /// `enqueue()` dedupes by sessionId, so this is a pure no-op whenever the
  /// normal path already did its job — it changes nothing for any session
  /// that completes/stops correctly through the existing mechanisms.
  Timer? _watchdog;

  /// How long past its expected end a session must be before the watchdog
  /// force-queues it — generous enough that it never races the normal path
  /// (which reacts within ~1s), tight enough that a genuinely missed
  /// completion still surfaces quickly instead of being stuck indefinitely.
  static const _watchdogGrace = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    for (final entry in ref.read(pendingOutcomesProvider)) {
      _handled.add(entry.sessionId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainStaleOnStart());
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _runWatchdog());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _runWatchdog() {
    final sessions = ref.read(activeSessionsProvider);
    if (sessions.isEmpty) return;
    final outcomes = ref.read(pendingOutcomesProvider.notifier);
    final now = DateTime.now();
    for (final session in sessions) {
      if (session.totalDurationSeconds <= 0) continue;
      if (outcomes.contains(session.id)) continue; // already queued
      final expectedEnd = session.createdAt.add(
        Duration(seconds: session.totalDurationSeconds) + _watchdogGrace,
      );
      if (now.isBefore(expectedEnd)) continue; // not overdue yet
      appLogger.w(
        '🩺 OUTCOME-DEBUG: watchdog — session ${session.id} '
        '(${session.protocolName}) is ${now.difference(expectedEnd).inSeconds}s '
        'past its expected end and was never queued by the normal path — '
        'force-queuing now',
      );
      unawaited(outcomes.enqueue(_minimalPendingOutcome(session)));
    }
    // Re-attempt presenting anything still queued and unanswered. Safe to
    // call every tick: _onQueueChanged only ever acts on an entry that
    // ISN'T already in [_handled], and an entry only lands there once
    // _present() actually succeeds — a blocked screen (login/onboarding)
    // deliberately leaves it out of _handled so this keeps retrying it,
    // while anything already showing correctly is a no-op here.
    _onQueueChanged(ref.read(pendingOutcomesProvider));
  }

  /// A valid-but-thin [PendingSessionOutcome] built purely from
  /// [ActiveSession] fields — no live engine involved. It has no per-protocol
  /// questions (the engine snapshot normally carries those), so the
  /// after-screen falls back to its plain "session logged" card instead of
  /// asking questions — still a real, functioning post-session screen, and
  /// the session still gets a proper history entry either way.
  PendingSessionOutcome _minimalPendingOutcome(ActiveSession session) {
    return PendingSessionOutcome(
      sessionId: session.id,
      protocolId: session.protocolId,
      protocolName: session.protocolName,
      deviceIds: session.deviceIds,
      totalDurationSeconds: session.totalDurationSeconds,
      elapsedSeconds: session.elapsedSeconds,
      createdAt: session.createdAt,
    );
  }

  /// Anything left queued from a previous run never got its after-screen, so it
  /// is logged to history on its own rather than waiting for a tap that may
  /// never come.
  void _drainStaleOnStart() {
    final notifier = ref.read(pendingOutcomesProvider.notifier);
    notifier.autoLogUnreviewed();
    notifier.drainSyncPending();
  }

  void _onQueueChanged(List<PendingSessionOutcome> next) {
    appLogger.i(
      '🩺 OUTCOME-DEBUG: gate._onQueueChanged — queue has ${next.length} '
      'entries: ${next.map((e) => '${e.sessionId}(answers=${e.answers != null})').toList()}, '
      '_handled=$_handled',
    );
    // Newest first — if two runs end together the latest one is presented and
    // the other is picked up when this one is dismissed.
    final fresh = next
        .where((e) => e.answers == null && !_handled.contains(e.sessionId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (fresh.isEmpty) {
      appLogger.i('🩺 OUTCOME-DEBUG: gate._onQueueChanged — fresh list empty, nothing to present');
      return;
    }
    final entry = fresh.first;
    appLogger.i('🩺 OUTCOME-DEBUG: gate._onQueueChanged — presenting ${entry.sessionId}');
    _handled.add(entry.sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _present(entry));
  }

  void _present(PendingSessionOutcome entry) {
    if (!mounted) {
      appLogger.i('🩺 OUTCOME-DEBUG: gate._present — gate not mounted, aborting');
      return;
    }
    final router = ref.read(routerProvider);
    final location = router.routerDelegate.currentConfiguration.uri.path;
    appLogger.i('🩺 OUTCOME-DEBUG: gate._present — current location=$location');

    // One after-screen at a time — a second would stack on top of the first.
    if (location == RoutePaths.sessionAfter) {
      appLogger.i('🩺 OUTCOME-DEBUG: gate._present — already on after-screen, deferring');
      _handled.remove(entry.sessionId); // retry when this one is dismissed
      return;
    }
    for (final blocked in _blockedPrefixes) {
      if (location.startsWith(blocked)) {
        appLogger.i(
          '🩺 OUTCOME-DEBUG: gate._present — location blocked by prefix '
          '"$blocked", deferring (will retry once off that screen)',
        );
        // Don't mark it handled — a blocked screen (login/onboarding) is
        // never where a live session runs, so this is rare and transient.
        // Leaving it un-handled lets the NEXT queue change, or the
        // watchdog's periodic retry, present it once the app is somewhere
        // safe — rather than silently losing it forever the way this used
        // to.
        _handled.remove(entry.sessionId);
        return;
      }
    }
    appLogger.i('🩺 OUTCOME-DEBUG: gate._present — pushing sessionAfter for ${entry.sessionId}');

    final extra = <String, dynamic>{'sessionId': entry.sessionId};
    // Coming off the live card, the after-screen REPLACES it — the run is over,
    // so there is nothing to go back to. From anywhere else it opens on top and
    // back returns the user where they were.
    if (location == RoutePaths.session) {
      router.pushReplacement(RoutePaths.sessionAfter, extra: extra);
    } else {
      router.push(RoutePaths.sessionAfter, extra: extra);
    }
    appLogger.i(
      'Post-session screen opened for ${entry.sessionId} (from $location)',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<PendingSessionOutcome>>(
      pendingOutcomesProvider,
      (_, next) => _onQueueChanged(next),
    );
    return widget.child;
  }
}
