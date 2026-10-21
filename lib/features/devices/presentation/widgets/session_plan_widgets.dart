import 'dart:math' as math;

import 'package:flutter/material.dart';

// ===========================================================================
// Session Plan visuals — the v6 prototype's `#scr-setup` (hydrawav3-app
// `hydrawav3-reya/30-session.js` + `hydrawav3-v5/30-session.js`).
//
// Presentation only: every action these widgets expose is passed in by the
// Session tab, exactly the callback it used before.
// ===========================================================================

/// Prototype tones for this screen.
class PlanTones {
  PlanTones._();

  static const Color copper = Color(0xFFC69E83);
  static const Color copperDeep = Color(0xFFA87B5C);
  static const Color copperText = Color(0xFF2B1D12);
  static const Color copperInk = Color(0xFF8A5F42);

  /// Light warm fill used by buttons and tiles (`#FBF5EE`).
  static const Color warmFill = Color(0xFFFBF5EE);
  static const Color warmInk = Color(0xFF5C4E3E);

  /// Card border when idle: rgba(192,157,132,.4).
  static const Color cardBorder = Color.fromRGBO(192, 157, 132, .4);

  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color card(BuildContext c) =>
      dark(c) ? const Color(0xFF1C1F26) : Colors.white;

  static Color fill(BuildContext c) =>
      dark(c) ? const Color(0xFF15171C) : warmFill;

  static Color fillInk(BuildContext c) =>
      dark(c) ? const Color(0xFFE7D3C0) : warmInk;

  static Color hairline(BuildContext c) => dark(c)
      ? const Color.fromRGBO(192, 157, 132, .3)
      : const Color.fromRGBO(26, 26, 26, .06);

  static Color sub(BuildContext c) =>
      dark(c) ? const Color(0xFFAFBCC6) : const Color(0xFF948B82);

  static List<BoxShadow> cardShadow(BuildContext c) => dark(c)
      ? const [
          BoxShadow(
            color: Color.fromRGBO(192, 157, 132, .35),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ]
      : const [
          BoxShadow(
            color: Color.fromRGBO(192, 157, 132, .3),
            blurRadius: 18,
            spreadRadius: -6,
            offset: Offset(0, 4),
          ),
        ];
}

/// `.ry-ses-eye` — the small uppercase section label.
class PlanEyebrow extends StatelessWidget {
  final String text;
  const PlanEyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.47,
        color: PlanTones.sub(context),
      ),
    );
  }
}

/// `.ry-ses-card` — the plan's card surface.
class PlanCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool neutralBorder;

  const PlanCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.neutralBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: PlanTones.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: neutralBorder
              ? (dark
                  ? const Color.fromRGBO(244, 239, 234, .1)
                  : const Color.fromRGBO(26, 26, 26, .09))
              : (dark
                  ? const Color.fromRGBO(192, 157, 132, .3)
                  : PlanTones.cardBorder),
          width: 2,
        ),
        boxShadow: PlanTones.cardShadow(context),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return PlanPress(onTap: onTap!, child: card);
  }
}

/// A gentle press scale for tappable surfaces.
class PlanPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PlanPress({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = .98,
  });

  @override
  State<PlanPress> createState() => _PlanPressState();
}

class _PlanPressState extends State<PlanPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: enabled
          ? () {
              setState(() => _down = false);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 160),
        curve: const Cubic(.34, 1.56, .64, 1),
        child: widget.child,
      ),
    );
  }
}

/// `.ry-ses-spill` — the uppercase pill in a section header. [on] gives the
/// copper-tint "armed" look. [icon]-only pills are square-ish (`.v5s-mute`).
class PlanPill extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool on;
  final bool caret;
  final VoidCallback? onTap;
  final String? tooltip;

  const PlanPill({
    super.key,
    this.label,
    this.icon,
    this.on = false,
    this.caret = false,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final fg = on
        ? (dark ? const Color(0xFFE2C0A2) : PlanTones.copperInk)
        : (dark ? const Color(0xFFC0B7AE) : const Color(0xFF5C5650));
    final iconOnly = label == null;
    Widget pill = Container(
      height: 34,
      constraints: BoxConstraints(minWidth: iconOnly ? 34 : 0),
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10),
      decoration: BoxDecoration(
        color: on
            ? Color.fromRGBO(198, 158, 131, dark ? .14 : .16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on
              ? Color.fromRGBO(198, 158, 131, dark ? .5 : .7)
              : Color.fromRGBO(198, 158, 131, dark ? .32 : .55),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) Icon(icon, size: iconOnly ? 16 : 13, color: fg),
          if (icon != null && !iconOnly) const SizedBox(width: 5),
          if (!iconOnly)
            Text(
              label!.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .55,
                color: fg,
              ),
            ),
          if (caret) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: fg),
          ],
        ],
      ),
    );
    pill = PlanPress(onTap: onTap, scale: .94, child: pill);
    if (tooltip != null) pill = Tooltip(message: tooltip!, child: pill);
    // 44px tap height around a 34px pill.
    return SizedBox(height: 44, child: Center(widthFactor: 1, child: pill));
  }
}

/// `.v5s-vsw` — the tall USE switch at the left of a unit card.
class PlanUseSwitch extends StatelessWidget {
  final bool on;
  final VoidCallback? onTap;
  const PlanUseSwitch({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final enabled = onTap != null;
    return Semantics(
      toggled: on,
      button: true,
      label: 'Use this unit',
      child: Opacity(
        opacity: enabled ? 1 : .7,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: 24,
                  height: 44,
                  decoration: BoxDecoration(
                    color: on
                        ? PlanTones.copper
                        : (dark
                            ? const Color(0xFF4A3320)
                            : const Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: on
                        ? const [
                            BoxShadow(
                              color: Color.fromRGBO(198, 158, 131, .6),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 450),
                    curve: const Cubic(.34, 1.56, .64, 1),
                    alignment:
                        on ? Alignment.topCenter : Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, .28),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'USE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.54,
                    height: 1,
                    color: on
                        ? (dark ? const Color(0xFFE7C9A9) : PlanTones.copper)
                        : PlanTones.sub(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-puck` — the top-down Hydrawav3 unit: a soft body with a gloss and
/// its button, inside halo rings; copper and rippling while armed.
class PlanPuck extends StatefulWidget {
  final bool on;
  const PlanPuck({super.key, required this.on});

  @override
  State<PlanPuck> createState() => _PlanPuckState();
}

class _PlanPuckState extends State<PlanPuck>
    with SingleTickerProviderStateMixin {
  // Three ripples, 1.6s apart, on a 4.8s loop (`rySesRip`).
  late final AnimationController _rip = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800));

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void dispose() {
    _rip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final ripple = widget.on && !_still;
    if (ripple && !_rip.isAnimating) _rip.repeat();
    if (!ripple && _rip.isAnimating) _rip.stop();

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Glow behind an armed unit.
          if (widget.on)
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  PlanTones.copper.withValues(alpha: dark ? .45 : .26),
                  PlanTones.copper.withValues(alpha: 0),
                ]),
              ),
            ),
          // Halo rings (`.v5s-halo`).
          Positioned.fill(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark
                      ? const Color.fromRGBO(231, 201, 169, .2)
                      : const Color.fromRGBO(192, 157, 132, .24),
                ),
                gradient: const RadialGradient(
                  colors: [
                    Color.fromRGBO(192, 157, 132, .12),
                    Color.fromRGBO(192, 157, 132, .05),
                    Color.fromRGBO(192, 157, 132, 0),
                  ],
                  stops: [0, .55, .72],
                ),
              ),
            ),
          ),
          Positioned.fill(
            left: 11,
            top: 11,
            right: 11,
            bottom: 11,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark
                      ? const Color.fromRGBO(231, 201, 169, .14)
                      : const Color.fromRGBO(192, 157, 132, .16),
                ),
              ),
            ),
          ),
          if (ripple)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _rip,
                  builder: (context, _) => CustomPaint(
                    painter: _RipplePainter(_rip.value),
                  ),
                ),
              ),
            ),
          // The unit itself.
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 36,
            height: 48,
            decoration: BoxDecoration(
              color: widget.on
                  ? PlanTones.copper
                  : (dark ? const Color(0xFF332C22) : const Color(0xFFE7DBC9)),
              borderRadius: BorderRadius.circular(14),
              boxShadow: widget.on
                  ? const [
                      BoxShadow(
                        color: Color.fromRGBO(198, 158, 131, .56),
                        blurRadius: 14,
                        spreadRadius: -3,
                        offset: Offset(0, 5),
                      ),
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, .2),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, .1),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(255, 255, 255, .4),
                          Color.fromRGBO(255, 255, 255, 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 6,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-.3, -.4),
                      colors: [Color(0xFF6B4E36), Color(0xFF2B1B10)],
                      stops: [0, .7],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, .45),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  _RipplePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    for (final shift in const [0.0, 1 / 3, 2 / 3]) {
      final k = (t + shift) % 1;
      // scale .55 → 1.85, fading in to 35% then out.
      final scale = .55 + 1.3 * k;
      final o = k < .35 ? .5 * (k / .35) : .5 * (1 - (k - .35) / .65);
      if (o <= .01) continue;
      canvas.drawCircle(
        c,
        base * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = PlanTones.copper.withValues(alpha: o),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}

/// `.v5s-loc` — the LOCATE pill under the puck.
class PlanLocatePill extends StatelessWidget {
  final VoidCallback onTap;
  const PlanLocatePill({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final fg = dark ? const Color(0xFFE7C9A9) : PlanTones.copperInk;
    return PlanPress(
      onTap: onTap,
      scale: .95,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            width: 120,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: dark ? PlanTones.fill(context) : const Color(0xFFFBF5EE),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: dark
                    ? const Color.fromRGBO(192, 157, 132, .3)
                    : const Color.fromRGBO(192, 157, 132, .45),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ◎ — a ring with a dot
                Container(
                  width: 12,
                  height: 12,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: fg, width: 1.6),
                  ),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: fg),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LOCATE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    height: 1,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-ubtn` — the round-ended control under a unit card.
class PlanUnitButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool on;
  final int flex;

  /// Quarter turns for the icon (1 stands a sideways icon upright).
  final int iconTurns;

  const PlanUnitButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.on = false,
    this.flex = 1,
    this.iconTurns = 0,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      flex: flex,
      child: Tooltip(
        message: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: PlanPress(
            onTap: onTap,
            scale: .95,
            child: SizedBox(
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 40,
                  decoration: BoxDecoration(
                    color: PlanTones.fill(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          on ? PlanTones.copper : PlanTones.hairline(context),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: iconTurns,
                      child: Icon(icon,
                          size: 18, color: PlanTones.fillInk(context)),
                    ),
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

/// `.v5s-fab` — the big round Start button.
class PlanStartFab extends StatefulWidget {
  final bool ready;
  final bool starting;
  final VoidCallback onTap;
  const PlanStartFab({
    super.key,
    required this.ready,
    required this.starting,
    required this.onTap,
  });

  @override
  State<PlanStartFab> createState() => _PlanStartFabState();
}

class _PlanStartFabState extends State<PlanStartFab>
    with TickerProviderStateMixin {
  bool _down = false;

  /// `.ry-shimmer`: a light band sweeps across while ready. Slowed from the
  /// prototype's 3.8s loop: a 4s sweep, then a 2.5s rest (6.5s loop).
  late final AnimationController _shimmer = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 6500));

  /// `.v5s-fab.fire`: the press pop when a start goes ahead.
  late final AnimationController _fire = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

  /// `.v5s-fab.nudge`: a little shake when tapped before anything's ready
  /// (slowed to 0.8s from the prototype's 0.42s).
  late final AnimationController _nudge = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  bool get _ready => widget.ready && !widget.starting;

  void _syncShimmer() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_ready && !still) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else if (_shimmer.isAnimating) {
      _shimmer.stop();
      _shimmer.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncShimmer();
  }

  @override
  void didUpdateWidget(PlanStartFab old) {
    super.didUpdateWidget(old);
    _syncShimmer();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _fire.dispose();
    _nudge.dispose();
    super.dispose();
  }

  // v5sFire: 0% .88 → 45% 1.1 → 100% 1
  double get _fireScale {
    if (!_fire.isAnimating) return 1;
    final t = const Cubic(.22, .61, .36, 1).transform(_fire.value);
    return t < .45
        ? .88 + (1.1 - .88) * (t / .45)
        : 1.1 + (1 - 1.1) * ((t - .45) / .55);
  }

  // v5sNudge: 25% −5px, 50% +4px, 75% −2px
  double get _nudgeDx {
    if (!_nudge.isAnimating) return 0;
    final t = Curves.ease.transform(_nudge.value);
    const keys = [0.0, -5.0, 4.0, -2.0, 0.0];
    final pos = t * 4, i = pos.floor().clamp(0, 3);
    return keys[i] + (keys[i + 1] - keys[i]) * (pos - i);
  }

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final ready = _ready;
    final decoration = ready
        ? const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE2C0A2), Color(0xFFC69E83), Color(0xFFA87B5C)],
              stops: [0, .45, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(168, 123, 92, .85),
                blurRadius: 30,
                spreadRadius: -8,
                offset: Offset(0, 14),
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, .2),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            shape: BoxShape.circle,
            color: dark ? const Color(0xFF2E323B) : const Color(0xFFDCD2C6),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(58, 46, 36, .35),
                blurRadius: 16,
                spreadRadius: -8,
                offset: Offset(0, 6),
              ),
            ],
          );
    return Semantics(
      button: true,
      enabled: ready,
      label: widget.starting ? 'Starting session' : 'Start session',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          setState(() => _down = false);
          if (ready) {
            _fire.forward(from: 0);
          } else if (!widget.starting) {
            _nudge.forward(from: 0);
          }
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_fire, _nudge]),
          builder: (context, child) => Transform.translate(
            offset: Offset(_nudgeDx, 0),
            child: Transform.scale(scale: _fireScale, child: child),
          ),
          child: AnimatedScale(
            scale: _down && ready ? .9 : 1,
            duration: const Duration(milliseconds: 160),
            curve: const Cubic(.34, 1.56, .64, 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 72,
              height: 72,
              decoration: decoration,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // the light band, clipped to the circle
                  if (ready)
                    Positioned.fill(
                      child: ClipOval(
                        child: AnimatedBuilder(
                          animation: _shimmer,
                          builder: (context, _) {
                            // first 4s: −120% → 220%, then rest
                            final t =
                                (_shimmer.value * 6500 / 4000).clamp(0.0, 1.0);
                            final x =
                                -1.2 + 3.4 * Curves.easeInOut.transform(t);
                            return FractionalTranslation(
                              translation: Offset(x, 0),
                              child: const FractionallySizedBox(
                                widthFactor: .4,
                                alignment: Alignment.centerLeft,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-1, -.18),
                                      end: Alignment(1, .18),
                                      colors: [
                                        Color(0x00FFFFFF),
                                        Color(0x73FFFFFF),
                                        Color(0x00FFFFFF),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  Center(
                    child: widget.starting
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation(PlanTones.copperText),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 40,
                              color: ready
                                  ? PlanTones.copperText
                                  : (dark
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFFFBF7F2)),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.v5s-mfab` — the small round music button above Start.
class PlanMusicFab extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const PlanMusicFab({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Tooltip(
      message: 'Session music',
      child: PlanPress(
        onTap: onTap,
        scale: .9,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? null : PlanTones.card(context),
            gradient: on
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFDEB393),
                      Color(0xFFC69E83),
                      Color(0xFFB27D5C)
                    ],
                  )
                : null,
            border: on
                ? null
                : Border.all(
                    color: Color.fromRGBO(198, 158, 131, dark ? .4 : .55),
                    width: 1.5,
                  ),
            boxShadow: [
              BoxShadow(
                color: dark
                    ? const Color.fromRGBO(0, 0, 0, .6)
                    : const Color.fromRGBO(58, 46, 36, .45),
                blurRadius: 20,
                spreadRadius: -8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            on ? Icons.music_note_rounded : Icons.music_note_outlined,
            size: 21,
            color: on
                ? PlanTones.copperText
                : (dark ? const Color(0xFFE2C0A2) : PlanTones.copperDeep),
          ),
        ),
      ),
    );
  }
}

/// `#v6sum` — the pre-start summary strip: who, how many units, how long,
/// what runs, and a note when the session is a Guest one.
class PlanSummaryStrip extends StatelessWidget {
  final String who;
  final int units;
  final Duration longest;
  final List<String> protocols;
  final bool guest;

  const PlanSummaryStrip({
    super.key,
    required this.who,
    required this.units,
    required this.longest,
    required this.protocols,
    required this.guest,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final ink = dark ? const Color(0xFFF4EFEA) : const Color(0xFF1A1A1A);
    final ink2 = dark ? const Color(0xFFC0B7AE) : const Color(0xFF5E5852);
    final ink3 = dark ? const Color(0xFF9A9188) : const Color(0xFF9A918A);
    final mins = (longest.inSeconds / 60).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B242B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: dark
                ? const Color.fromRGBO(0, 0, 0, .7)
                : const Color.fromRGBO(58, 46, 36, .45),
            blurRadius: 30,
            spreadRadius: -12,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: dark
                ? const Color.fromRGBO(222, 179, 147, .18)
                : const Color.fromRGBO(26, 26, 26, .08),
            spreadRadius: 1,
          ),
        ],
      ),
      child: units == 0
          ? Row(
              children: [
                Icon(Icons.bluetooth_searching_rounded, size: 17, color: ink3),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Connect a unit to plan a session',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ink3,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$units unit${units == 1 ? '' : 's'}'
                            '${mins > 0 ? ' · $mins min' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ink3,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (protocols.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          protocols.join(' \u2192 '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: ink2,
                          ),
                        ),
                      ],
                      if (guest) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded,
                                size: 13, color: ink3),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                "Guest — this session won't be saved to a client",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ink3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 20, color: ink3),
              ],
            ),
    );
  }
}

/// Sun + Moon mark for the Find Pad Placements tile (`.v6sm`).
class PlanSunMoonMark extends StatelessWidget {
  const PlanSunMoonMark({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 22,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 2,
            child: Icon(Icons.wb_sunny_rounded,
                size: 18, color: Color(0xFFE0613F)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: -math.pi / 12,
              child: const Icon(Icons.dark_mode_rounded,
                  size: 16, color: Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.v5s-dly` — the Start Delay stepper on a unit card: − value + with the
/// DELAY caption. Tinted copper while a delay is set. Holding − / + repeats.
class PlanDelayStepper extends StatelessWidget {
  final int seconds;
  final int max;

  /// Null disables the stepper (no protocol yet, or the unit is busy).
  final ValueChanged<int>? onChanged;

  const PlanDelayStepper({
    super.key,
    required this.seconds,
    required this.onChanged,
    this.max = 60,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final on = seconds > 0;
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: SizedBox(
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: on
                  ? (dark ? const Color(0xFF1F1B18) : null)
                  : PlanTones.fill(context),
              gradient: on && !dark
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFBF5EE), Color(0xFFF6E9DC)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: on
                    ? Color.fromRGBO(198, 158, 131, dark ? .6 : .75)
                    : PlanTones.hairline(context),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                _StepButton(
                  label: '−',
                  semantic: 'Less start delay',
                  onStep: enabled && seconds > 0
                      ? () => onChanged!((seconds - 1).clamp(0, max))
                      : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: '$seconds',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: dark
                                  ? const Color(0xFFF1E4D6)
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          TextSpan(
                            text: 's',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: PlanTones.sub(context),
                            ),
                          ),
                        ]),
                        style: const TextStyle(
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'DELAY',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                          height: 1,
                          color: on
                              ? (dark
                                  ? const Color(0xFFE7C9A9)
                                  : PlanTones.copperDeep)
                              : PlanTones.sub(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _StepButton(
                  label: '+',
                  semantic: 'More start delay',
                  onStep: enabled && seconds < max
                      ? () => onChanged!((seconds + 1).clamp(0, max))
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatefulWidget {
  final String label;
  final String semantic;
  final VoidCallback? onStep;
  const _StepButton({
    required this.label,
    required this.semantic,
    required this.onStep,
  });

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _down = false;
  bool _holding = false;

  Future<void> _repeat() async {
    _holding = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    while (_holding && mounted && widget.onStep != null) {
      widget.onStep!();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final enabled = widget.onStep != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semantic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onStep!();
              }
            : null,
        onTapCancel: () => setState(() => _down = false),
        onLongPressStart: enabled ? (_) => _repeat() : null,
        onLongPressEnd: (_) {
          _holding = false;
          setState(() => _down = false);
        },
        child: SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _down
                    ? PlanTones.copper
                    : (dark ? const Color(0xFF262A33) : Colors.white),
                boxShadow: dark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color.fromRGBO(58, 46, 36, .18),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: _down
                      ? PlanTones.copperText
                      : (enabled
                          ? (dark
                              ? const Color(0xFFE7C9A9)
                              : PlanTones.copperInk)
                          : PlanTones.sub(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Advanced panel (`.ry-ses-adv`) ───────────────────

/// Uppercase label used across the advanced panel (`.ry-ses-lbl`).
class PlanAdvLabel extends StatelessWidget {
  final String text;
  const PlanAdvLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .55,
          color: PlanTones.dark(context)
              ? const Color(0xFFCDB9A5)
              : PlanTones.sub(context),
        ),
      );
}

/// `.ry-ses-seg` — the OFF / SWEEP / SINGLE row of filled pills.
class PlanModeSeg extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  /// Options shown but not selectable (faded, taps ignored).
  final Set<String> disabled;
  const PlanModeSeg({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.disabled = const {},
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              enabled: !disabled.contains(options[i]),
              selected: options[i] == selected,
              child: Opacity(
                opacity: disabled.contains(options[i]) ? .4 : 1,
                child: PlanPress(
                  onTap: disabled.contains(options[i])
                      ? null
                      : () => onSelect(options[i]),
                  scale: .96,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: options[i] == selected
                          ? PlanTones.copper
                          : PlanTones.fill(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      options[i].toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .55,
                        color: options[i] == selected
                            ? Colors.white
                            : (dark
                                ? const Color(0xFFB7A999)
                                : PlanTones.warmInk),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// v6 `70-intensity` — a pad intensity nudge of −limit..+limit % around the
/// protocol's own setting. The track fills outward from the centre in the
/// pad's tint, the caption reads "−10% · protocol · +10%", and tapping the
/// value puts it back to 0.
class PlanAdjustSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color tint;
  final double limit;
  final ValueChanged<double> onChanged;
  const PlanAdjustSlider({
    super.key,
    required this.label,
    required this.value,
    required this.tint,
    required this.onChanged,
    this.limit = 10,
  });

  static String _fmt(double v) {
    final n = v.round();
    final sign = n > 0 ? '+' : (n < 0 ? '−' : '');
    return '$sign${n.abs()}%';
  }

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(-limit, limit).toDouble();
    final zero = v.round() == 0;
    final ink3 = PlanTones.sub(context);
    final capStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: ink3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: PlanAdvLabel(label)),
            Semantics(
              button: !zero,
              label: zero ? null : 'Back to the protocol setting',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: zero ? null : () => onChanged(0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 46),
                  child: Text(
                    _fmt(v),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: zero ? ink3 : tint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            trackShape: _CentreFillTrack(
              min: -limit,
              max: limit,
              fill: tint,
              base: PlanTones.dark(context)
                  ? const Color(0xFF3A3E47)
                  : const Color(0xFFEDE8E3),
            ),
            thumbShape: const _PlanThumb(),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            overlayColor: tint.withValues(alpha: .12),
            tickMarkShape: SliderTickMarkShape.noTickMark,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: SizedBox(
            height: 34,
            child: Slider(
              value: v,
              min: -limit,
              max: limit,
              divisions: (limit * 2).round(),
              onChanged: onChanged,
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('−${limit.round()}%', style: capStyle),
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 1.5,
                    height: 7,
                    decoration: BoxDecoration(
                      color: PlanTones.dark(context)
                          ? const Color.fromRGBO(192, 157, 132, .4)
                          : const Color.fromRGBO(26, 26, 26, .15),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  Text('protocol', style: capStyle),
                ],
              ),
            ),
            Text('+${limit.round()}%', style: capStyle),
          ],
        ),
      ],
    );
  }
}

/// A plain level slider (`.ry-ses-sl`) — label and value over a copper track.
class PlanLevelSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;
  const PlanLevelSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: PlanAdvLabel(label)),
            Text(
              '${v.toStringAsFixed(0)}$unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: PlanTones.dark(context)
                    ? const Color(0xFFCDB9A5)
                    : PlanTones.sub(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: PlanTones.copper,
            inactiveTrackColor: PlanTones.dark(context)
                ? const Color(0xFF3A3E47)
                : const Color(0xFFEDE8E3),
            thumbShape: const _PlanThumb(),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            overlayColor: PlanTones.copper.withValues(alpha: .14),
            tickMarkShape: SliderTickMarkShape.noTickMark,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: SizedBox(
            height: 34,
            child: Slider(
              value: v,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
          ),
        ),
      ],
    );
  }
}

/// The white 22px thumb with a soft drop (`input[type=range]::thumb`).
class _PlanThumb extends SliderComponentShape {
  const _PlanThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final c = context.canvas;
    c.drawCircle(
      center.translate(0, 2),
      11,
      Paint()
        ..color = const Color.fromRGBO(58, 46, 36, .3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    c.drawCircle(center, 11, Paint()..color = Colors.white);
    c.drawCircle(
      center,
      10.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color.fromRGBO(26, 26, 26, .12),
    );
  }
}

/// Track that fills from the zero point to the thumb, either way.
class _CentreFillTrack extends RoundedRectSliderTrackShape {
  final double min;
  final double max;
  final Color fill;
  final Color base;
  const _CentreFillTrack({
    required this.min,
    required this.max,
    required this.fill,
    required this.base,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final r = Radius.circular(rect.height / 2);
    final c = context.canvas;
    c.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..color = base);
    final zeroX = rect.left + rect.width * ((0 - min) / (max - min));
    final a = math.min(zeroX, thumbCenter.dx);
    final b = math.max(zeroX, thumbCenter.dx);
    if (b - a > .5) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(a, rect.top, b, rect.bottom), r),
        Paint()..color = fill,
      );
    }
  }
}

/// `.ry-ses-tog` in its v6 one-per-row form — the name and a small switch.
class PlanToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const PlanToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Semantics(
      toggled: value,
      label: label,
      child: PlanPress(
        onTap: () => onChanged(!value),
        scale: .98,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF15171C) : PlanTones.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark
                  ? const Color.fromRGBO(192, 157, 132, .2)
                  : const Color.fromRGBO(192, 157, 132, .25),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: dark
                        ? const Color(0xFFE7D3C0)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                width: 30,
                height: 17,
                padding: const EdgeInsets.all(2),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value
                      ? PlanTones.copper
                      : (dark
                          ? const Color(0xFF3A3E47)
                          : const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-morebtn` + `.ry-ses-more` — "More settings" behind a dashed rule,
/// closed until tapped.
class PlanMoreSettings extends StatefulWidget {
  final List<Widget> children;
  const PlanMoreSettings({super.key, required this.children});

  @override
  State<PlanMoreSettings> createState() => _PlanMoreSettingsState();
}

class _PlanMoreSettingsState extends State<PlanMoreSettings> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final ink = dark ? const Color(0xFFE7D3C0) : const Color(0xFF3A2E24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          painter: _DashedRule(
            color: dark
                ? const Color.fromRGBO(192, 157, 132, .3)
                : const Color.fromRGBO(192, 157, 132, .35),
          ),
          child: Semantics(
            button: true,
            expanded: _open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        'More settings',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child:
                          Icon(Icons.expand_more_rounded, size: 18, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: const Cubic(.22, .61, .36, 1),
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DashedRule extends CustomPainter {
  final Color color;
  const _DashedRule({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(
          Offset(x, .5), Offset(math.min(x + 3, size.width), .5), p);
    }
  }

  @override
  bool shouldRepaint(_DashedRule old) => old.color != color;
}
