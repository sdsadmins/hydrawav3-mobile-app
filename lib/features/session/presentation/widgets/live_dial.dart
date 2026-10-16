import 'dart:math' as math;

import 'package:flutter/material.dart';

// ===========================================================================
// Live session visuals — the v6 prototype's live card (hydrawav3-app
// `hydrawav3-pro-v6.html` → `hydrawav3-reya/30-session.js` dial,
// `hydrawav3-v5/30-session.js` live counter, `hydrawav3-v6/90-dial.js`).
//
// Pure presentation. Every value drawn here is computed by the session screen
// exactly as before; these widgets only decide how it looks.
// ===========================================================================

/// Prototype tones the shared palette doesn't carry.
class LiveTones {
  LiveTones._();

  /// Sun pad (right) while it's working.
  static const Color sun = Color(0xFFE0613F);

  /// Moon pad (left) while it's working.
  static const Color moon = Color(0xFF3B82F6);

  /// Copper used for resting marks and ripples.
  static const Color copper = Color(0xFFC69E83);
  static const Color copperDeep = Color(0xFFA87B5C);

  /// Active stage chip / progress fill.
  static const Color stage = Color(0xFFA9825F);

  /// Break chips, legend and stage name.
  static const Color breakInk = Color(0xFF3D6B94);

  /// Break arcs on the dial.
  static const Color breakArc = Color(0xFF8FBBEF);

  /// Stop.
  static const Color stop = Color(0xFFC0553B);
  static const Color stopDark = Color(0xFFCF6347);

  static const Color copperText = Color(0xFF2B1D12);

  static Color dialTrack(bool dark) =>
      dark ? const Color(0xFF2A2F3A) : const Color(0xFFE7DDCE);

  static Color cardBg(bool dark) =>
      dark ? const Color(0xFF1C1F26) : Colors.white;

  static const Color cardBorder = Color.fromRGBO(192, 157, 132, .4);
}

/// One arc of the dial: a protocol stage or the break between two.
typedef LiveArc = ({double seconds, bool isBreak});

/// How a pad mark is tinted.
enum PadTone { sun, moon, rest, off }

/// The live dial: drifting ripple rings, a soft glow, the segmented ring with
/// its continuous progress arc, and the time with both pad marks in the middle.
class LiveDial extends StatefulWidget {
  /// The ring to draw. When null the dial draws [LiveRingPainter] (a single
  /// continuous arc over a segmented track).
  final CustomPainter? ring;

  /// Whole-run progress, 0–1.
  final double progress;

  /// Stages and breaks for a Protocol Plus run; empty for a single protocol.
  final List<LiveArc> arcs;

  /// Running (not paused / waiting). Drives the ripples and the pad pulse.
  final bool running;

  /// A protocol stage is working both pads right now (not a break, not paused)
  /// — the ripples then carry the pad colours; otherwise they're copper.
  final bool padsWorking;

  /// On a break between stacked protocols.
  final bool onBreak;

  /// Fades the time and the ring (paused or held).
  final bool dimmed;

  final String time;
  final PadTone moon;
  final PadTone sun;

  /// Dial box. 224 on a phone; the tablet grid uses 196 (97-tablet §3).
  final double diameter;

  /// Countdown digits. 46 on a phone, 34 on a tablet.
  final double timeSize;

  const LiveDial({
    super.key,
    this.ring,
    required this.progress,
    required this.arcs,
    required this.running,
    required this.padsWorking,
    required this.onBreak,
    required this.dimmed,
    required this.time,
    required this.moon,
    required this.sun,
    this.diameter = size,
    this.timeSize = 46,
  });

  static const double size = 224;

  @override
  State<LiveDial> createState() => _LiveDialState();
}

class _LiveDialState extends State<LiveDial> with TickerProviderStateMixin {
  // One 12s loop drives three ripples offset by 4s each — `rySesDRip`
  // slowed from 9s on request.
  late final AnimationController _ripple =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  // Pad marks breathe while the pads work (`v5lMod`, 3s).
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  // First paint: the ring settles in and the time counts in (`v5sDialIn`).
  late final AnimationController _enter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static bool _lit(PadTone t) => t == PadTone.sun || t == PadTone.moon;

  void _sync() {
    final ripple = widget.running && !_still;
    if (ripple && !_ripple.isAnimating) _ripple.repeat();
    if (!ripple && _ripple.isAnimating) _ripple.stop();
    // Breathe only while at least one mark is actually lit (red or blue).
    final pulse = widget.padsWorking &&
        widget.running &&
        !_still &&
        (_lit(widget.sun) || _lit(widget.moon));
    if (pulse && !_pulse.isAnimating) _pulse.repeat();
    if (!pulse && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    _pulse.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.diameter;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Ripples — drawn outside the dial's own box, clipped by the card.
          if (widget.running && !_still)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ripple,
                  builder: (context, _) => CustomPaint(
                    // Each side copies the mark on that side, live: the left
                    // (Moon) mark's colour on the left half, the right (Sun)
                    // mark's on the right — so when the device switches the
                    // pad colours, the rings switch with them. A mark that
                    // isn't lit, a break or a pause → copper.
                    painter: _RipplePainter(
                      t: _ripple.value,
                      left: widget.padsWorking ? widget.moon : PadTone.rest,
                      right: widget.padsWorking ? widget.sun : PadTone.rest,
                    ),
                  ),
                ),
              ),
            ),
          // Soft glow inside the ring.
          Positioned.fill(
            left: 8,
            top: 8,
            right: 8,
            bottom: 8,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Copper base — also on a break (no blue tint), matching the
                // copper rings there.
                gradient: const RadialGradient(
                  colors: [
                    Color.fromRGBO(201, 167, 136, .22),
                    Color.fromRGBO(201, 167, 136, 0),
                  ],
                  stops: [0, .7],
                ),
              ),
              // A pad's warm/cool halo shows only while that pad is lit,
              // same rule as the rings.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.padsWorking) ...[
                    _SideHalo(tone: widget.sun, x: .44),
                    _SideHalo(tone: widget.moon, x: -.44),
                  ],
                ],
              ),
            ),
          ),
          // The ring.
          AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final t = _still
                  ? 1.0
                  : const Cubic(.34, 1.56, .64, 1).transform(_enter.value);
              return Opacity(
                opacity: (.25 + .75 * t).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: -8 * math.pi / 180 * (1 - t),
                  child: Transform.scale(scale: .9 + .1 * t, child: child),
                ),
              );
            },
            child: CustomPaint(
              size: Size.square(s),
              painter: widget.ring ??
                  LiveRingPainter(
                    progress: widget.progress,
                    arcs: widget.arcs,
                    track: LiveTones.dialTrack(dark),
                    dimmed: widget.dimmed,
                  ),
            ),
          ),
          // Time + pad marks.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: widget.dimmed ? .5 : 1,
                child: Text(
                  widget.time,
                  style: TextStyle(
                    fontSize: widget.timeSize,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -.92,
                    color: dark
                        ? const Color(0xFFF5EFE6)
                        : const Color(0xFF22242A),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  // Moon leads, Sun follows half a beat later.
                  double beat(double shift) {
                    final v = (_pulse.value + shift) % 1;
                    return 1 + .14 * (1 - math.cos(v * 2 * math.pi)) / 2;
                  }

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A mark that isn't lit stays still.
                      Transform.scale(
                        scale: _pulse.isAnimating && _lit(widget.moon)
                            ? beat(0)
                            : 1,
                        child: PadMark(tone: widget.moon, isSun: false),
                      ),
                      const SizedBox(width: 10),
                      Transform.scale(
                        scale: _pulse.isAnimating && _lit(widget.sun)
                            ? beat(.5)
                            : 1,
                        child: PadMark(tone: widget.sun, isSun: true),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One pad's mark in the middle of the dial (`.v5l-mods i`).
class PadMark extends StatelessWidget {
  final PadTone tone;
  final bool isSun;
  const PadMark({super.key, required this.tone, required this.isSun});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color c;
    final double ring;
    switch (tone) {
      case PadTone.sun:
        c = LiveTones.sun;
        ring = .35;
      case PadTone.moon:
        c = LiveTones.moon;
        ring = .32;
      case PadTone.rest:
        c = dark ? const Color(0xFFDEB393) : const Color(0xFFB27D5C);
        ring = .32;
      case PadTone.off:
        c = const Color(0xFF9CA3AF);
        ring = .28;
    }
    final working = tone == PadTone.sun || tone == PadTone.moon;
    final base = LiveTones.cardBg(dark);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0, -.1),
          colors: [
            Color.alphaBlend(c.withValues(alpha: dark ? .3 : .22), base),
            Color.alphaBlend(c.withValues(alpha: dark ? .1 : .08), base),
          ],
        ),
        border: Border.all(color: c.withValues(alpha: ring), width: 1.5),
        boxShadow: [
          if (working)
            BoxShadow(
              color: c.withValues(alpha: .75),
              blurRadius: 14,
              spreadRadius: -6,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: CustomPaint(painter: _PadGlyph(color: c, sun: isSun)),
    );
  }
}

/// The prototype's moon (a filled crescent) and sun (a disc with eight rays),
/// drawn from its own 24×24 SVG paths.
class _PadGlyph extends CustomPainter {
  final Color color;
  final bool sun;
  const _PadGlyph({required this.color, required this.sun});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    if (sun) {
      canvas.drawCircle(const Offset(12, 12), 4.2, fill);
      final ray = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      const rays = [
        [12.0, 2.0, 12.0, 4.2],
        [12.0, 19.8, 12.0, 22.0],
        [4.9, 4.9, 6.4, 6.4],
        [17.6, 17.6, 19.1, 19.1],
        [2.0, 12.0, 4.2, 12.0],
        [19.8, 12.0, 22.0, 12.0],
        [4.9, 19.1, 6.4, 17.6],
        [17.6, 6.4, 19.1, 4.9],
      ];
      for (final r in rays) {
        canvas.drawLine(Offset(r[0], r[1]), Offset(r[2], r[3]), ray);
      }
    } else {
      // M20.5 14.2 A8.5 8.5 0 1 1 9.8 3.5 a6.8 6.8 0 0 0 10.7 10.7 Z
      final path = Path()
        ..moveTo(20.5, 14.2)
        ..arcToPoint(const Offset(9.8, 3.5),
            radius: const Radius.circular(8.5), largeArc: true)
        ..arcToPoint(const Offset(20.5, 14.2),
            radius: const Radius.circular(6.8), clockwise: false)
        ..close();
      canvas.drawPath(path, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadGlyph old) => old.color != color || old.sun != sun;
}

class _RipplePainter extends CustomPainter {
  final double t;

  /// The colour each half takes: the tone of the mark on that side.
  final PadTone left;
  final PadTone right;
  _RipplePainter({required this.t, required this.left, required this.right});

  static const _copper = Color.fromRGBO(198, 158, 131, .95);
  static const _red = Color.fromRGBO(224, 97, 63, .97);
  static const _blue = Color.fromRGBO(59, 130, 246, .95);

  static Color _of(PadTone tone) => switch (tone) {
        PadTone.sun => _red,
        PadTone.moon => _blue,
        _ => _copper,
      };

  bool get dual => _of(left) != _copper || _of(right) != _copper;

  // Right half, then left half, meeting through copper top and bottom.
  List<Color> get _dualColors => [
        _copper,
        _of(right),
        _of(right),
        _copper,
        _of(left),
        _of(left),
        _copper,
      ];
  static const _dualStops = [
    0.0,
    62 / 360,
    118 / 360,
    .5,
    242 / 360,
    298 / 360,
    1.0
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    for (final shift in const [0.0, 1 / 3, 2 / 3]) {
      final k = (t + shift) % 1; // 0 → 1 over 12s
      final scale = 1 + .52 * k;
      final opacity = .9 * (1 - k);
      if (opacity <= 0.01) continue;
      final r = base * scale - 2.5 * scale;
      final width = 5 * scale;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      if (dual) {
        // CSS conic-gradient starts at 12 o'clock; Flutter's sweep at 3.
        paint.shader = SweepGradient(
          colors: [
            for (final col in _dualColors)
              col.withValues(alpha: col.a * opacity),
          ],
          stops: _dualStops,
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: c, radius: r));
      } else {
        paint.color = Color.fromRGBO(201, 167, 136, .95 * opacity);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width + 10
            ..color = Color.fromRGBO(201, 167, 136, .22 * opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.t != t || old.left != left || old.right != right;
}

/// The dial ring (`.ry-ses-dialsvg`): a beige track, each break as a pale blue
/// arc, and one continuous copper-gradient arc for the whole run's progress.
class LiveRingPainter extends CustomPainter {
  final double progress;
  final List<LiveArc> arcs;
  final Color track;
  final bool dimmed;

  LiveRingPainter({
    required this.progress,
    required this.arcs,
    required this.track,
    required this.dimmed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 0 0 200 200, r = 85, stroke 13 — scaled to the box.
    final k = size.shortestSide / 200;
    final c = size.center(Offset.zero);
    final r = 85 * k;
    final w = 13 * k;
    final rect = Rect.fromCircle(center: c, radius: r);
    final fade = dimmed ? .55 : 1.0;

    Paint stroke(Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = col.withValues(alpha: col.a * fade);

    canvas.drawCircle(c, r, stroke(track)..strokeCap = StrokeCap.butt);

    // Breaks, where the run pauses between stacked protocols.
    final total = arcs.fold<double>(0, (a, s) => a + s.seconds);
    if (total > 0) {
      var at = 0.0;
      for (final a in arcs) {
        final span = a.seconds / total;
        if (a.isBreak && span > 0) {
          canvas.drawArc(
            rect,
            -math.pi / 2 + at * 2 * math.pi,
            span * 2 * math.pi,
            false,
            stroke(LiveTones.breakArc.withValues(alpha: .28)),
          );
        }
        at += span;
      }
    }

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final sweep = math.max(p * 2 * math.pi, .02);
    final paint = stroke(Colors.white)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFE7C9A9).withValues(alpha: fade),
          const Color(0xFFB27D5C).withValues(alpha: fade),
        ],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(LiveRingPainter old) =>
      old.progress != progress ||
      old.dimmed != dimmed ||
      old.track != track ||
      old.arcs.length != arcs.length;
}

/// The round control (`.v5s-rb`): outlined copper for Pause, filled copper
/// for Resume, solid red for Stop — with an optional caption underneath.
enum RoundKind { pause, resume, stop }

class LiveRoundButton extends StatefulWidget {
  final RoundKind kind;
  final VoidCallback? onTap;
  final double size;
  final String? caption;
  final String semanticLabel;

  const LiveRoundButton({
    super.key,
    required this.kind,
    required this.onTap,
    required this.semanticLabel,
    this.size = 58,
    this.caption,
  });

  @override
  State<LiveRoundButton> createState() => _LiveRoundButtonState();
}

class _LiveRoundButtonState extends State<LiveRoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onTap != null;
    final s = widget.size;
    final big = s >= 56;

    final BoxDecoration deco;
    final Color fg;
    final IconData icon;
    switch (widget.kind) {
      case RoundKind.pause:
        fg = dark ? const Color(0xFFE2C0A2) : LiveTones.copperDeep;
        icon = Icons.pause_rounded;
        deco = BoxDecoration(
          shape: BoxShape.circle,
          color: dark
              ? Color.alphaBlend(const Color.fromRGBO(198, 158, 131, .06),
                  LiveTones.cardBg(true))
              : Colors.white,
          border: Border.all(color: LiveTones.copper, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(198, 158, 131, dark ? .1 : .12),
              spreadRadius: 5,
            ),
          ],
        );
      case RoundKind.resume:
        fg = LiveTones.copperText;
        icon = Icons.play_arrow_rounded;
        deco = const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE2C0A2), Color(0xFFC69E83), Color(0xFFA87B5C)],
            stops: [0, .45, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(168, 123, 92, .8),
              blurRadius: 20,
              spreadRadius: -8,
              offset: Offset(0, 8),
            ),
          ],
        );
      case RoundKind.stop:
        fg = Colors.white;
        icon = Icons.stop_rounded;
        deco = BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? LiveTones.stopDark : LiveTones.stop,
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(192, 85, 59, .75),
              blurRadius: 20,
              spreadRadius: -8,
              offset: Offset(0, 8),
            ),
          ],
        );
    }

    final button = AnimatedScale(
      scale: _down ? .9 : 1,
      duration: const Duration(milliseconds: 160),
      curve: const Cubic(.34, 1.56, .64, 1),
      child: Container(
        width: s,
        height: s,
        decoration: deco,
        child: Icon(icon,
            size: widget.kind == RoundKind.stop
                ? (big ? 26 : 22)
                : (big ? 28 : 24),
            color: fg),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTap: enabled
              ? () {
                  setState(() => _down = false);
                  widget.onTap!();
                }
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              button,
              if (widget.caption != null) ...[
                const SizedBox(height: 5),
                Text(
                  widget.caption!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .44,
                    color: dark
                        ? const Color(0xFF9A9188)
                        : const Color(0xFF9A918A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The 38px round header button (`.ry-ses-round`).
class LiveHeaderButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool on;

  const LiveHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.on = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark ? const Color(0xFF1C252B) : Colors.white,
                  border: Border.all(
                    color: on
                        ? const Color.fromRGBO(63, 142, 110, .5)
                        : (dark
                            ? const Color.fromRGBO(244, 239, 234, .07)
                            : const Color.fromRGBO(26, 26, 26, .06)),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(31, 43, 51, .04),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                    BoxShadow(
                      color: Color.fromRGBO(31, 43, 51, .06),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: 18,
                      color: on
                          ? const Color(0xFF3F8F6B)
                          : (dark
                              ? const Color(0xFFF4EFEA)
                              : const Color(0xFF1A1A1A)),
                    ),
                    child: icon,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The faint halo inside the dial on one side, in the colour of that side's
/// mark (none when the mark isn't lit).
class _SideHalo extends StatelessWidget {
  final PadTone tone;
  final double x;
  const _SideHalo({required this.tone, required this.x});

  @override
  Widget build(BuildContext context) {
    final Color? c = switch (tone) {
      PadTone.sun => const Color.fromRGBO(224, 97, 63, .16),
      PadTone.moon => const Color.fromRGBO(59, 130, 246, .15),
      _ => null,
    };
    if (c == null) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(x, 0),
          radius: .62,
          colors: [c, c.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
