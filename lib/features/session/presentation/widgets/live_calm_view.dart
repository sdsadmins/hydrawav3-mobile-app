import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/widgets/hw_tablet.dart';

/// What the calm view shows for one unit.
class LiveCalmUnit {
  final String unit;
  final Duration remaining;

  /// 0–1 of the whole run.
  final double progress;

  /// "Paused", "Resting between protocols", or the running stage's name.
  final String stage;

  /// The treatment: the Protocol Plus name, or the protocol.
  final String treatment;
  final bool paused;
  const LiveCalmUnit({
    required this.unit,
    required this.remaining,
    required this.progress,
    required this.stage,
    required this.treatment,
    this.paused = false,
  });
}

/// The live screen's **Simple** view (v6 `30-calm`): a calm full-screen lens
/// for the client — a plain copper ring per unit with the time left, the
/// stage and the treatment, a slow breath glow, and "Hold to return" (0.9s)
/// so a resting hand can't leave it. The live screen and its controls keep
/// running underneath, untouched.
class LiveCalmView extends StatefulWidget {
  /// Read fresh every second.
  final List<LiveCalmUnit> Function() read;
  final VoidCallback onExit;

  /// Who the session is for — "Guest", or the person and whether they're a
  /// client or a player. Hidden when unknown here (e.g. a run started on
  /// another device).
  final String? who;
  const LiveCalmView({
    super.key,
    required this.read,
    required this.onExit,
    this.who,
  });

  @override
  State<LiveCalmView> createState() => _LiveCalmViewState();
}

class _LiveCalmViewState extends State<LiveCalmView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // nothing left running: back to the normal view
      if (widget.read().isEmpty) {
        widget.onExit();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tablet = HwTablet.of(context);
    final units = widget.read();
    final n = units.length;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF18222A), Color(0xFF0D1318)]
                : const [
                    Color(0xFFFBF7F2),
                    Color(0xFFF1E6DC),
                    Color(0xFFEADDD1)
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 18),
              const Text(
                'HYDRAWAV3',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.9,
                  color: Color(0xFFB27D5C),
                ),
              ),
              if (widget.who != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.who!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: dark
                          ? const Color(0xFFF1EDE7)
                          : const Color(0xFF2A2320),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                n <= 1 ? 'Session in progress' : '$n sessions in progress',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      dark ? const Color(0xFF9AA4AD) : const Color(0xFF9A918A),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 18,
                      runSpacing: 26,
                      children: [
                        for (final u in units)
                          _CalmCell(
                            unit: u,
                            // every ring says which unit it is
                            showName: true,
                            size: n == 1
                                ? (tablet ? 300.0 : 236.0)
                                : (tablet ? 220.0 : 150.0),
                            dark: dark,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 22, top: 8),
                child: _HoldToReturn(onDone: widget.onExit, dark: dark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalmCell extends StatelessWidget {
  final LiveCalmUnit unit;
  final bool showName;
  final double size;
  final bool dark;
  const _CalmCell({
    required this.unit,
    required this.showName,
    required this.size,
    required this.dark,
  });

  static String _mmss(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFF1EDE7) : const Color(0xFF2A2320);
    final sub = dark ? const Color(0xFF9AA4AD) : const Color(0xFF9A918A);
    final timeSize = (size * .26).clamp(40.0, 72.0);
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showName) ...[
            Text(
              unit.unit.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: sub,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _Breath(still: unit.paused, size: size),
                CustomPaint(
                  size: Size.square(size),
                  painter: _CalmRing(progress: unit.progress, dark: dark),
                ),
                Padding(
                  padding: EdgeInsets.all(size * .14),
                  // shrinks to fit the smaller rings of a multi-unit view
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size * .72),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _mmss(unit.remaining),
                            style: TextStyle(
                              fontSize: timeSize,
                              fontWeight: FontWeight.w300,
                              height: 1,
                              color: ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            unit.stage,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: sub),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            unit.treatment,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: showName ? 15 : 20,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// The plain thin copper ring, filling with the run's progress.
class _CalmRing extends CustomPainter {
  final double progress;
  final bool dark;
  _CalmRing({required this.progress, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(4.0, size.width * .022);
    final rect = (Offset.zero & size).deflate(stroke / 2 + size.width * .04);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color.fromRGBO(178, 125, 92, .16),
    );
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFC69E83),
      );
    }
  }

  @override
  bool shouldRepaint(_CalmRing old) =>
      old.progress != progress || old.dark != dark;
}

/// A slow 7s "breath" glow behind the ring; still when paused or when the
/// system asks for less motion.
class _Breath extends StatefulWidget {
  final bool still;
  final double size;
  const _Breath({required this.still, required this.size});

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 7000));

  void _sync() {
    final calm =
        widget.still || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (calm) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Breath old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          return Container(
            width: widget.size * (.78 + .1 * t),
            height: widget.size * (.78 + .1 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFFDEB393).withValues(alpha: .20 + .14 * t),
                const Color(0xFFDEB393).withValues(alpha: 0),
              ]),
            ),
          );
        },
      );
}

/// "Hold to return": press and hold 0.9s while a copper fill sweeps across;
/// letting go early cancels. A tap does nothing.
class _HoldToReturn extends StatefulWidget {
  final VoidCallback onDone;
  final bool dark;
  const _HoldToReturn({required this.onDone, required this.dark});

  @override
  State<_HoldToReturn> createState() => _HoldToReturnState();
}

class _HoldToReturnState extends State<_HoldToReturn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return Semantics(
      button: true,
      label: 'Hold to return to the full view',
      onTap: widget.onDone,
      // raw pointer events: the fill starts the instant a finger lands
      child: Listener(
        onPointerDown: (_) => _c.forward(from: 0),
        onPointerUp: (_) {
          if (_c.status != AnimationStatus.completed) _c.reverse();
        },
        onPointerCancel: (_) {
          if (_c.status != AnimationStatus.completed) _c.reverse();
        },
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 196,
              height: 46,
              decoration: BoxDecoration(
                color: dark
                    ? const Color.fromRGBO(255, 255, 255, .06)
                    : const Color.fromRGBO(255, 255, 255, .7),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: const Color.fromRGBO(178, 125, 92, .3)),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: _c.value,
                    heightFactor: 1,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Hold to return',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _c.value > .5
                            ? const Color(0xFF2B1D12)
                            : (dark
                                ? const Color(0xFFDDCABF)
                                : const Color(0xFF8A5F42)),
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
