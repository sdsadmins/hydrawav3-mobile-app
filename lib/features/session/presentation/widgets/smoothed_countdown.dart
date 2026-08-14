import 'dart:async';

import 'package:flutter/material.dart';

/// Ticks a `Duration` down smoothly by exactly 1 second per second, between
/// the coarser updates its caller actually receives (the org-wide live-feed
/// poll runs on an adaptive 1-5s interval, not a true per-second push — its
/// raw `remainingSeconds` displayed directly jumps by an inconsistent number
/// of seconds each rebuild instead of decrementing steadily).
///
/// Two constraints this widget exists to satisfy without repeating past
/// mistakes:
///  1. It owns its OWN `Timer.periodic` and only calls `setState` on itself —
///     never on an ancestor — so ticking this can never force-rebuild
///     unrelated UI on the same screen (that caused a pause/resume flicker
///     the first time this was tried with a screen-wide ticker).
///  2. It does NOT know anything about pause state, Protocol Plus break-hold,
///     or "terminal" sessions — it takes the caller's already-fully-computed
///     [remaining] value and a plain [frozen] flag. When [frozen], it is a
///     pure pass-through of [remaining], never advancing on its own — so
///     every existing freeze mechanism (pause latch, break-hold latch,
///     terminal gating) keeps working exactly as it does today, unmodified,
///     because this widget never second-guesses them.
class SmoothedCountdown extends StatefulWidget {
  /// The caller's fully-computed remaining duration for THIS build — already
  /// reflecting any pause/break-hold freeze the caller applies before handing
  /// it here.
  final Duration remaining;

  /// True whenever [remaining] should NOT be locally extrapolated: the
  /// session is paused, a Protocol Plus device is break-held disconnected,
  /// the device is terminal, or the caller isn't trusting the backend clock
  /// at all (using the local engine's own already-smooth Stopwatch timer
  /// instead). In every one of these cases [remaining] is already the
  /// correct value to show as-is.
  final bool frozen;

  final Widget Function(BuildContext context, Duration remaining) builder;

  const SmoothedCountdown({
    super.key,
    required this.remaining,
    required this.frozen,
    required this.builder,
  });

  @override
  State<SmoothedCountdown> createState() => _SmoothedCountdownState();
}

class _SmoothedCountdownState extends State<SmoothedCountdown> {
  late Duration _anchorRemaining = widget.remaining;
  late DateTime _anchorWallClock = DateTime.now();
  Timer? _ticker;

  Duration get _liveRemaining {
    if (widget.frozen) return widget.remaining;
    final live = _anchorRemaining - DateTime.now().difference(_anchorWallClock);
    return live < Duration.zero ? Duration.zero : live;
  }

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  void _startTicker() {
    // Forces a rebuild of THIS widget once a second so `_liveRemaining`'s
    // elapsed-time math actually repaints — the displayed value is always
    // recomputed fresh from real elapsed time here, never decremented by a
    // stored counter, so this timer's own scheduling jitter can't show up as
    // a visible correction.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.frozen) return;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(SmoothedCountdown old) {
    super.didUpdateWidget(old);
    if (widget.frozen) {
      // Always track the caller's value exactly while frozen, so the instant
      // it un-freezes the anchor resumes from the right place rather than
      // wherever local ticking left off before the freeze began.
      _anchorRemaining = widget.remaining;
      _anchorWallClock = DateTime.now();
      return;
    }
    // Coming OUT of frozen (or the very first live update): always re-anchor.
    if (old.frozen) {
      _anchorRemaining = widget.remaining;
      _anchorWallClock = DateTime.now();
      return;
    }
    if (old.remaining == widget.remaining) return;
    // Only resync to the caller's fresh value when it disagrees with what the
    // wall-clock math already predicts by more than 1s. A poll landing on an
    // ordinary tick boundary is normal ±1s jitter from the poll's own timing
    // relative to this widget's ticker — resyncing on that made the display
    // visibly hop forward a second and back again on every poll. A gap bigger
    // than 1s means something actually changed and DOES need to snap.
    final predicted =
        _anchorRemaining - DateTime.now().difference(_anchorWallClock);
    final diff = (predicted.inSeconds - widget.remaining.inSeconds).abs();
    if (diff > 1) {
      _anchorRemaining = widget.remaining;
      _anchorWallClock = DateTime.now();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _liveRemaining);
}
