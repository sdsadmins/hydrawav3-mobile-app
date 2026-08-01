import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/pending_session_outcome_model.dart';
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

  @override
  void initState() {
    super.initState();
    for (final entry in ref.read(pendingOutcomesProvider)) {
      _handled.add(entry.sessionId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainStaleOnStart());
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
    // Newest first — if two runs end together the latest one is presented and
    // the other is picked up when this one is dismissed.
    final fresh = next
        .where((e) => e.answers == null && !_handled.contains(e.sessionId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (fresh.isEmpty) return;
    final entry = fresh.first;
    _handled.add(entry.sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _present(entry));
  }

  void _present(PendingSessionOutcome entry) {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final location = router.routerDelegate.currentConfiguration.uri.path;

    // One after-screen at a time — a second would stack on top of the first.
    if (location == RoutePaths.sessionAfter) {
      _handled.remove(entry.sessionId); // retry when this one is dismissed
      return;
    }
    for (final blocked in _blockedPrefixes) {
      if (location.startsWith(blocked)) return;
    }

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
