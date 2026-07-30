import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';

/// Shared chrome for the 5-step Guided Assessment, ported from the UI handoff
/// (`renderWizard()`, app.js:2861 and `styles.css:386-407`).

// ---------------------------------------------------------------------------
// .stepdots
// ---------------------------------------------------------------------------

/// The spec's step indicator: 7px dots that stretch into a 22px copper pill for
/// the current and completed steps.
class WizardStepDots extends StatelessWidget {
  final int count;
  final int step; // 1-based
  const WizardStepDots({super.key, required this.count, required this.step});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: HwMotion.t3,
              curve: HwMotion.ease,
              width: i <= step ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i <= step ? p.copper : p.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// .optcard
// ---------------------------------------------------------------------------

/// The spec's option row: a bordered card that takes a copper border and a tan
/// fill when selected, with a ✓ / ○ marker.
class WizardOptCard extends StatelessWidget {
  final String label;
  final bool selected;

  /// Multi-select rows show a check; single-select rows show a filled radio.
  final bool multi;
  final VoidCallback onTap;

  const WizardOptCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.multi = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: HwPress(
        scale: 0.97,
        onTap: onTap,
        child: AnimatedContainer(
          duration: HwMotion.t2,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? p.tanSoft : p.card,
            borderRadius: BorderRadius.circular(HwRadius.md),
            border: Border.all(
              color: selected ? p.copper : p.line,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined)
                    : (selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded),
                size: 19,
                color: selected ? p.copperInk : p.ink3,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w600,
                    color: selected ? p.copperInk : p.ink,
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

// ---------------------------------------------------------------------------
// .romstage — the animated protractor
// ---------------------------------------------------------------------------

/// The spec's step-2 protractor: a copper pivot, a dashed tan arc, and an arm
/// sweeping 40° → 0° → 40° on a 3.2s loop (`app.js:2892`).
///
/// Honours `MediaQuery.disableAnimations` by holding the arm at 20° — the same
/// courtesy `HwCountUp` and `HwRings` already extend, and a looping animation is
/// exactly what that setting exists to stop.
class RomProtractor extends StatefulWidget {
  const RomProtractor({super.key});

  @override
  State<RomProtractor> createState() => _RomProtractorState();
}

class _RomProtractorState extends State<RomProtractor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) _c.stop();

    return SizedBox(
      width: 150,
      height: 120,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // 0 → 1 → 0 over the loop, then mapped onto 40° → 0°.
          final t = still ? 0.5 : (1 - (_c.value * 2 - 1).abs());
          return CustomPaint(
            painter: _ProtractorPainter(
              sweep: 40 * (1 - t),
              pivot: p.copper,
              arc: p.tan,
              arm: p.copperDeep,
            ),
          );
        },
      ),
    );
  }
}

class _ProtractorPainter extends CustomPainter {
  final double sweep; // degrees from vertical
  final Color pivot;
  final Color arc;
  final Color arm;

  _ProtractorPainter({
    required this.sweep,
    required this.pivot,
    required this.arc,
    required this.arm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height - 16);
    const radius = 76.0;

    // Dashed reference arc, ±40° around vertical.
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const start = -math.pi / 2 - 0.7;
    const total = 1.4;
    const dashes = 13;
    for (var i = 0; i < dashes; i++) {
      final a0 = start + total * (i / dashes);
      final a1 = a0 + total / dashes * 0.55;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        a0,
        a1 - a0,
        false,
        arcPaint,
      );
    }

    // The sweeping arm.
    final rad = -math.pi / 2 + sweep * math.pi / 180;
    canvas.drawLine(
      origin,
      origin + Offset(math.cos(rad), math.sin(rad)) * radius,
      Paint()
        ..color = arm
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // Pivot.
    canvas.drawCircle(origin, 7, Paint()..color = pivot);
    canvas.drawCircle(
      origin,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ProtractorPainter old) => old.sweep != sweep;
}

// ---------------------------------------------------------------------------
// A labelled slider with a live copper value pill
// ---------------------------------------------------------------------------

class WizardSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const WizardSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: HwType.eyebrow,
                  fontWeight: FontWeight.w700,
                  color: p.ink2,
                ),
              ),
            ),
            HwPill(valueLabel, tone: HwPillTone.copper, tabular: true),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: p.copperDeep,
            inactiveTrackColor: p.line,
            thumbColor: p.copperDeep,
            overlayColor: p.copper.withValues(alpha: 0.18),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
