import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hub_prefs_provider.dart';

// ===========================================================================
// Hub micro-moments — a port of the prototype's `hydrawav3-v5/15-hubmotion.js`.
//
//   · cards spring up as they scroll into view; the heading mark pops, the
//     title slides in and the copper underline draws
//   · tiles, device rows and stat tiles cascade in; icons pop
//   · Start Now shimmers, the Lease art floats and its arrow nudges
//   · a drifting copper glow sits behind the Hub (light theme)
//
// Entrances play once per visit to the Hub. Everything is off when the
// "Hub animations" switch is off, and the OS reduce-motion setting always wins.
// ===========================================================================

/// True when Hub motion should run.
bool hubMotionOn(BuildContext context, WidgetRef ref) {
  final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return ref.watch(hubMotionProvider) && !reduced;
}

const Curve _cardSpring = Cubic(.34, 1.25, .64, 1);
const Curve _popSpring = Cubic(.34, 1.56, .64, 1);
const Curve _smooth = Cubic(.22, .61, .36, 1);

/// Length of one section's entrance timeline; every inner moment is an
/// interval on it (the prototype's `calc(var(--d) + Nms)` delays).
const int _timelineMs = 1500;

/// Gives a Hub section its entrance and shares the timeline with the widgets
/// inside it ([HubCascade], [HubPop], the heading underline).
class HubReveal extends ConsumerStatefulWidget {
  final Widget child;

  /// Position among the sections that are on screen at first paint — they
  /// stagger 90ms apart; sections further down reveal as they scroll in.
  final int order;

  /// False keeps the child in place and only runs the shared timeline — for
  /// the greeting, whose parts pop and slide in on their own.
  final bool lift;

  const HubReveal({
    super.key,
    required this.child,
    this.order = 0,
    this.lift = true,
  });

  @override
  ConsumerState<HubReveal> createState() => _HubRevealState();
}

class _HubRevealState extends ConsumerState<HubReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _timelineMs),
  );
  ScrollPosition? _position;
  bool _started = false;
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(first: true));
  }

  void _check({bool first = false}) {
    if (_started || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    if (top > screen * .92) return;
    _started = true;
    _position?.removeListener(_check);
    final delay = first ? 180 + widget.order * 90 : 0;
    _start = Timer(Duration(milliseconds: delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _position?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = hubMotionOn(context, ref);
    if (!on) {
      return _HubTimeline(
          animation: kAlwaysCompleteAnimation, child: widget.child);
    }
    if (!widget.lift) return _HubTimeline(animation: _c, child: widget.child);
    final card = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 700 / _timelineMs, curve: _cardSpring),
    );
    return _HubTimeline(
      animation: _c,
      child: AnimatedBuilder(
        animation: card,
        builder: (context, child) {
          final t = card.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 26 * (1 - t)),
              child: Transform.scale(scale: .985 + .015 * t, child: child),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _HubTimeline extends InheritedWidget {
  final Animation<double> animation;
  const _HubTimeline({required this.animation, required super.child});

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HubTimeline>()?.animation;

  @override
  bool updateShouldNotify(_HubTimeline old) => old.animation != animation;
}

Animation<double> _slice(
    BuildContext context, int startMs, int lengthMs, Curve curve) {
  final parent = _HubTimeline.of(context);
  if (parent == null) return kAlwaysCompleteAnimation;
  final a = (startMs / _timelineMs).clamp(0.0, 1.0);
  final b = ((startMs + lengthMs) / _timelineMs).clamp(a, 1.0);
  return CurvedAnimation(parent: parent, curve: Interval(a, b, curve: curve));
}

/// A child that rises 12px into place, [index] steps into a cascade.
class HubCascade extends StatelessWidget {
  final int index;
  final Widget child;
  final int startMs;
  final int stepMs;

  /// Tiles pop from .92 scale as well as rising (`v5mTile`).
  final bool tile;

  const HubCascade({
    super.key,
    required this.index,
    required this.child,
    this.startMs = 320,
    this.stepMs = 70,
    this.tile = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = _slice(context, startMs + index * stepMs, tile ? 550 : 500,
        tile ? const Cubic(.34, 1.4, .64, 1) : _smooth);
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) {
        final t = a.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (tile ? 14 : 12) * (1 - t)),
            child: tile ? Transform.scale(scale: .92 + .08 * t, child: c) : c,
          ),
        );
      },
      child: child,
    );
  }
}

/// A child that pops in from .6 scale on the spring curve.
class HubPop extends StatelessWidget {
  final int startMs;
  final Widget child;
  const HubPop({super.key, required this.startMs, required this.child});

  @override
  Widget build(BuildContext context) {
    final a = _slice(context, startMs, 550, _popSpring);
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: .6 + .4 * a.value, child: c),
      ),
      child: child,
    );
  }
}

/// A child that slides in 12px from the left.
class HubSlideIn extends StatelessWidget {
  final int startMs;
  final Widget child;
  const HubSlideIn({super.key, required this.startMs, required this.child});

  @override
  Widget build(BuildContext context) {
    final a = _slice(context, startMs, 500, _smooth);
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(-12 * (1 - a.value), 0), child: c),
      ),
      child: child,
    );
  }
}

/// Draws a child in from the left edge (the heading underline).
class HubDraw extends StatelessWidget {
  final int startMs;
  final Widget child;
  const HubDraw({super.key, required this.startMs, required this.child});

  @override
  Widget build(BuildContext context) {
    final a = _slice(context, startMs, 800, _smooth);
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) => Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.diagonal3Values(a.value.clamp(0.0, 1.0), 1, 1),
        child: c,
      ),
      child: child,
    );
  }
}

/// A looping animation that only runs while Hub motion is on.
abstract class _LoopState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> with SingleTickerProviderStateMixin {
  Duration get period;
  Duration get startDelay => Duration.zero;

  late final AnimationController loop =
      AnimationController(vsync: this, duration: period);
  bool _running = false;
  Timer? _start;

  void _sync(bool on) {
    if (on && !_running) {
      _running = true;
      if (startDelay == Duration.zero) {
        loop.repeat();
      } else {
        _start = Timer(startDelay, () {
          if (mounted && _running) loop.repeat();
        });
      }
    } else if (!on && _running) {
      _running = false;
      _start?.cancel();
      loop.stop();
      loop.value = 0;
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    loop.dispose();
    super.dispose();
  }

  Widget buildLoop(BuildContext context, bool on);

  @override
  Widget build(BuildContext context) {
    final on = hubMotionOn(context, ref);
    _sync(on);
    return buildLoop(context, on);
  }
}

/// A light sweep across a primary button every 4.2s (`v5mShimmer`).
class HubShimmer extends ConsumerStatefulWidget {
  final Widget child;
  final BorderRadius radius;
  const HubShimmer({super.key, required this.child, required this.radius});

  @override
  ConsumerState<HubShimmer> createState() => _HubShimmerState();
}

class _HubShimmerState extends _LoopState<HubShimmer> {
  @override
  Duration get period => const Duration(milliseconds: 4200);
  @override
  Duration get startDelay => const Duration(milliseconds: 1500);

  @override
  Widget buildLoop(BuildContext context, bool on) {
    if (!on) return widget.child;
    return ClipRRect(
      borderRadius: widget.radius,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: loop,
                builder: (context, _) {
                  // Crosses in the first 55% of the cycle, then rests.
                  final k = (loop.value / .55).clamp(0.0, 1.0);
                  return LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth * .4;
                    final x = -1.2 * w + (c.maxWidth + 2.4 * w) * k;
                    return Stack(children: [
                      Positioned(
                        left: x,
                        top: 0,
                        bottom: 0,
                        width: w,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1, -.3),
                              end: Alignment(1, .3),
                              colors: [
                                Color.fromRGBO(255, 255, 255, 0),
                                Color.fromRGBO(255, 255, 255, .4),
                                Color.fromRGBO(255, 255, 255, 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]);
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slow float for decorative art (`v5mFloat`, 6s).
class HubFloat extends ConsumerStatefulWidget {
  final Widget child;
  const HubFloat({super.key, required this.child});

  @override
  ConsumerState<HubFloat> createState() => _HubFloatState();
}

class _HubFloatState extends _LoopState<HubFloat> {
  @override
  Duration get period => const Duration(seconds: 6);

  @override
  Widget buildLoop(BuildContext context, bool on) {
    if (!on) return widget.child;
    return AnimatedBuilder(
      animation: loop,
      builder: (context, c) {
        final s = (1 - math.cos(loop.value * 2 * math.pi)) / 2; // 0→1→0
        return Transform.translate(
          offset: Offset(0, -8 * s),
          child: Transform.rotate(angle: -2 * math.pi / 180 * s, child: c),
        );
      },
      child: widget.child,
    );
  }
}

/// A small sideways nudge every 2.6s — the Lease arrow (`v5mNudge`).
class HubNudge extends ConsumerStatefulWidget {
  final Widget child;
  const HubNudge({super.key, required this.child});

  @override
  ConsumerState<HubNudge> createState() => _HubNudgeState();
}

class _HubNudgeState extends _LoopState<HubNudge> {
  @override
  Duration get period => const Duration(milliseconds: 2600);
  @override
  Duration get startDelay => const Duration(seconds: 2);

  @override
  Widget buildLoop(BuildContext context, bool on) {
    if (!on) return widget.child;
    return AnimatedBuilder(
      animation: loop,
      builder: (context, c) {
        final v = loop.value;
        final dx = v < .7
            ? 0.0
            : v < .8
                ? 4 * (v - .7) / .1
                : v < .9
                    ? 4 * (1 - (v - .8) / .1)
                    : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: c);
      },
      child: widget.child,
    );
  }
}

/// A soft pulsing ring, for "up next" and live markers (`v5gNudge`, 1.8s).
class HubPulse extends ConsumerStatefulWidget {
  final Widget child;
  final BorderRadius radius;
  final Color color;
  const HubPulse({
    super.key,
    required this.child,
    required this.radius,
    this.color = const Color(0xFFC69E83),
  });

  @override
  ConsumerState<HubPulse> createState() => _HubPulseState();
}

class _HubPulseState extends _LoopState<HubPulse> {
  @override
  Duration get period => const Duration(milliseconds: 1800);

  @override
  Widget buildLoop(BuildContext context, bool on) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, c) {
        final s = on ? (1 - math.cos(loop.value * 2 * math.pi)) / 2 : .5;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: widget.radius + BorderRadius.circular(4),
            border: Border.all(
              color: widget.color.withValues(alpha: .25 + .55 * s),
              width: 2,
            ),
          ),
          child: c,
        );
      },
      child: widget.child,
    );
  }
}

/// The drifting copper glow behind the Hub (light theme only), fixed to the
/// viewport the way the prototype's sticky `.v5m-amb` layer is.
class HubAmbientGlow extends ConsumerStatefulWidget {
  const HubAmbientGlow({super.key});

  @override
  ConsumerState<HubAmbientGlow> createState() => _HubAmbientGlowState();
}

class _HubAmbientGlowState extends _LoopState<HubAmbientGlow> {
  // One 1287s loop is the least common multiple of 9s, 11s and 13s, so each
  // blob keeps its own period with no jump when the loop wraps.
  @override
  Duration get period => const Duration(seconds: 1287);

  @override
  Widget buildLoop(BuildContext context, bool on) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!on || dark) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final secs = loop.value * 1287;
          double wave(double period) =>
              (1 - math.cos(secs / period * 2 * math.pi)) / 2;
          final a = wave(9), b = wave(11), c = wave(13);
          return Stack(
            children: [
              _blob(
                  top: 230,
                  right: -90,
                  size: 260,
                  scale: 1 + .15 * a,
                  dx: -14 * a,
                  dy: 10 * a,
                  opacity: .6 + .4 * a,
                  color: const Color.fromRGBO(221, 202, 191, .75)),
              _blob(
                  top: 470,
                  left: -80,
                  size: 240,
                  scale: 1.1 - .1 * b,
                  dx: 16 * b,
                  dy: -12 * b,
                  opacity: .5 + .4 * b,
                  color: const Color.fromRGBO(198, 158, 131, .32)),
              _blob(
                  top: 640,
                  right: -50,
                  size: 230,
                  scale: 1 + .2 * c,
                  dx: -10 * c,
                  dy: -16 * c,
                  opacity: .45 + .4 * c,
                  color: const Color.fromRGBO(221, 202, 191, .6)),
            ],
          );
        },
      ),
    );
  }

  Widget _blob({
    required double top,
    double? left,
    double? right,
    required double size,
    required double scale,
    required double dx,
    required double dy,
    required double opacity,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color, color.withValues(alpha: 0)],
                  stops: const [0, .7],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
