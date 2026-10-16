import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../hw_tokens.dart';
import 'hw_icon.dart';

/// A card, everywhere: `--r-lg` corners, a 1px copper hairline, `--shadow`,
/// `--s4` padding. Principles §5 — "a card is a card everywhere".
class HwCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Swap the hairline for a full copper border — the spec uses this to mark
  /// the one card on screen that wants an answer.
  final bool accented;

  /// Paint over the card surface (dark hero cards, the Rent & Earn card).
  final Decoration? decoration;

  const HwCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accented = false,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final card = Container(
      padding: padding ?? const EdgeInsets.all(HwSpace.s4),
      decoration: decoration ??
          BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(HwRadius.lg),
            border: Border.all(
              color: accented ? p.copper : p.cardline,
              width: accented ? 1.5 : 1,
            ),
            boxShadow: p.shadow,
          ),
      child: child,
    );
    return onTap == null ? card : HwPress(onTap: onTap!, child: card);
  }
}

/// The tactile press every tappable surface gets: a scale squeeze on the
/// spring curve plus a selection haptic (Principles §7, tier 1).
class HwPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  /// `.tile` presses harder than a row does (`transform:scale(.96)` vs the
  /// nav's `.9`); override per surface where the spec differs.
  final double scale;

  const HwPress({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = HwMotion.press,
  });

  @override
  State<HwPress> createState() => _HwPressState();
}

class _HwPressState extends State<HwPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _down = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: HwMotion.t1,
        curve: HwMotion.spring,
        child: widget.child,
      ),
    );
  }
}

/// Semantic tint for a [HwPill].
enum HwPillTone { copper, good, mid, low, info, ghost }

class HwPill extends StatelessWidget {
  final String label;
  final HwPillTone tone;
  final bool tabular;

  /// How many lines the label may wrap to before ellipsising. One by default —
  /// a pill is a badge, and letting long text wrap freely turns it into a
  /// paragraph with a rounded border. Raise it where the label is real prose of
  /// unbounded length (e.g. a chain subline).
  final int maxLines;

  const HwPill(this.label,
      {super.key,
      this.tone = HwPillTone.ghost,
      this.tabular = false,
      this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    late final Color fg;
    late final Color bg;
    switch (tone) {
      case HwPillTone.copper:
        fg = p.copperInk;
        bg = p.tanSoft;
        break;
      case HwPillTone.good:
        fg = p.good;
        bg = p.goodSoft;
        break;
      case HwPillTone.mid:
        fg = p.mid;
        bg = p.midSoft;
        break;
      case HwPillTone.low:
        fg = p.low;
        bg = p.lowSoft;
        break;
      case HwPillTone.info:
        fg = p.info;
        bg = p.infoSoft;
        break;
      case HwPillTone.ghost:
        fg = p.ink3;
        bg = Colors.transparent;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HwRadius.pill),
        border: tone == HwPillTone.ghost
            ? Border.all(color: p.line)
            : null,
      ),
      // Without a line cap the Text takes its full intrinsic width, so a long
      // server-supplied label (e.g. `ChainInfo.subline`) overflows whatever Row
      // it sits in. Pair this with a `Flexible` at the call site to actually
      // yield the width.
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: HwType.eyebrow,
          fontWeight: FontWeight.w800,
          height: maxLines > 1 ? 1.35 : null,
          color: fg,
          fontFeatures:
              tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
    );
  }
}

/// Small uppercase section label above a card group.
class HwEyebrow extends StatelessWidget {
  final String text;
  const HwEyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: HwSpace.s2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: HwType.eyebrow,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.08 * HwType.eyebrow,
          color: RefPalette.of(context).copperInk,
        ),
      ),
    );
  }
}

/// Card header: a title on the left, an optional trailing widget on the right.
class HwCardHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const HwCardHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: RefPalette.of(context).ink,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Milestone numbers count up rather than snapping into place
/// (Principles §7, tier 3).
class HwCountUp extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String suffix;

  const HwCountUp(this.value,
      {super.key, required this.style, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    // Respect the OS "reduce motion" switch — Principles §10.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Text('$value$suffix', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: HwMotion.ease,
      builder: (_, v, __) => Text('$v$suffix', style: style),
    );
  }
}

/// One arc of [HwRings].
class HwRingData {
  final double value;
  final double max;
  final Color color;
  const HwRingData(this.value, this.max, this.color);

  double get fraction =>
      max <= 0 ? 0 : (value / max).clamp(0.0, 1.0).toDouble();
}

/// The concentric activity rings on the Hub's "This week" card
/// (`ring3SVG`, app.js:3963).
class HwRings extends StatelessWidget {
  final List<HwRingData> rings;
  final double size;

  const HwRings(this.rings, {super.key, this.size = 104});

  @override
  Widget build(BuildContext context) {
    final track = RefPalette.of(context).ringTrack;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: HwMotion.ease,
      builder: (_, t, __) => CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(rings, track, t),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<HwRingData> rings;
  final Color track;
  final double progress;

  _RingPainter(this.rings, this.track, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < rings.length; i++) {
      // radius = size/2 - 8 - i*15  →  44, 29, 14 at size 104.
      final radius = size.width / 2 - 8 - i * 15;
      if (radius <= 0) continue;
      final rect = Rect.fromCircle(center: center, radius: radius);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      );

      final sweep = rings[i].fraction * progress * 2 * math.pi;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        -math.pi / 2, // 12 o'clock, matching `transform:rotate(-90deg)`
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = rings[i].color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.rings != rings || old.track != track;
}

/// `.bar` — the shared progress bar (styles.css:293): 9px tall, pill radius,
/// `--bg2` track, `--sun-grad` fill, easing over 800ms.
class HwBar extends StatelessWidget {
  final double fraction;

  /// Override the copper fill. The plan sheet's reports bar uses the spec's
  /// info→good gradient so the two bars in that sheet read as different
  /// quantities rather than one total.
  final Gradient? gradient;

  const HwBar(this.fraction, {super.key, this.gradient});

  /// `linear-gradient(90deg,#4E7A8A,#3F8F6B)` — app.js:2258.
  static const Gradient infoToGood = LinearGradient(
    colors: [Color(0xFF4E7A8A), Color(0xFF3F8F6B)],
  );

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(HwRadius.pill),
      child: Container(
        height: 9,
        color: p.bg2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: HwMotion.ease,
            builder: (_, v, __) => FractionallySizedBox(
              widthFactor: v == 0 ? 0.0001 : v,
              child: Container(
                decoration:
                    BoxDecoration(gradient: gradient ?? p.sunGrad),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screens assemble via a staggered rise rather than appearing all at once
/// (Principles §7, `assemble()`). Only the first few children stagger — past
/// that the delay stops reading as choreography and starts reading as lag.
class HwStagger extends StatelessWidget {
  final int index;
  final Widget child;
  const HwStagger({super.key, required this.index, required this.child});

  static const int _maxStaggered = 9;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

    final delay = HwMotion.stagger * math.min(index, _maxStaggered);
    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween(begin: 0, end: 1),
      duration: HwMotion.t4 + delay,
      curve: Interval(
        delay.inMilliseconds / (HwMotion.t4 + delay).inMilliseconds,
        1,
        curve: HwMotion.ease,
      ),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

/// A chevron-terminated row — the shared shape of every list item in the Hub's
/// compact modules and the whole More screen.
class HwRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  /// Optional content displayed below the subtitle in the row's text column.
  final Widget? belowSubtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Caps the title to this many lines (with ellipsis) instead of the
  /// default unbounded wrap. Null (the default) keeps every existing HwRow
  /// call site's current behavior — only opt in where a long name needs a
  /// fixed line count (e.g. a scrollable list of protocol names).
  final int? titleMaxLines;

  const HwRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.belowSubtitle,
    this.trailing,
    this.onTap,
    this.titleMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          if (leading != null) ...[
            // `.mrow-ic` is a 30px slot holding a 19px glyph (styles.css:200).
            SizedBox(width: 30, child: Center(child: leading)),
            const SizedBox(width: HwSpace.s3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow:
                      titleMaxLines != null ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: HwType.base,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      height: 1.35,
                      color: p.ink2,
                    ),
                  ),
                ],
                if (belowSubtitle != null) ...[
                  const SizedBox(height: HwSpace.s2),
                  belowSubtitle!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: HwSpace.s2),
            trailing!,
          ],
        ],
      ),
    );
    return onTap == null ? row : HwPress(onTap: onTap!, child: row);
  }
}

/// A hairline-separated stack of [HwRow]s in one card.
///
/// Separators use `--divider` (copper-tinted) at full width — styles.css:275
/// puts the border on the row itself, so it is not inset.
class HwRowGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const HwRowGroup({super.key, required this.children, this.padding});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwCard(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.backbar` — styles.css:110.
///
/// The spec pulls this bar full-bleed with `margin:0 -18px` so its opaque
/// background spans edge to edge. Flutter rejects negative margins, and it
/// would buy nothing here: the bar's background is `--bg`, the same as the
/// screen's, so the bleed is invisible. It simply sits inside the gutters.
///
/// The back button is optional: History and Reports render a bare title.
class HwBackBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  const HwBackBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Row(
        children: [
          if (onBack != null) ...[
            HwIconButton(asset: HwIcons.back, onTap: onBack!),
            const SizedBox(width: HwSpace.s3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // Every backbar in the spec overrides `.h-page` to 20px.
                    fontSize: HwType.xl,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: p.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style:
                        TextStyle(fontSize: HwType.cap, color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: HwSpace.s2),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// `.iconbtn` — styles.css:105. 40×40, r13, hairline, card fill.
class HwIconButton extends StatelessWidget {
  final String asset;
  final VoidCallback onTap;
  final Color? color;
  final double size;

  const HwIconButton({
    super.key,
    required this.asset,
    required this.onTap,
    this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: p.line),
        ),
        child: Center(
          child: HwIcon(asset, size: 19, color: color ?? p.ink2),
        ),
      ),
    );
  }
}

/// `.goalchips` + `.chip` — styles.css:186, 393. A horizontally scrolling
/// filter row; the selected chip takes the copper `.hot` treatment.
class HwChipRow extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const HwChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: HwSpace.s2),
        itemBuilder: (_, i) => HwChip(
          label: labels[i],
          selected: i == selectedIndex,
          onTap: () => onSelected(i),
        ),
      ),
    );
  }
}

class HwChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const HwChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      scale: 0.92,
      onTap: onTap,
      child: AnimatedContainer(
        duration: HwMotion.t2,
        curve: HwMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.tanSoft : p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.md),
          border: Border.all(
            color: selected ? p.copper : p.line,
            width: 1.5,
          ),
          boxShadow: selected ? null : p.shadow,
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: HwType.sm,
            fontWeight: FontWeight.w600,
            color: selected ? p.copperInk : p.ink,
          ),
        ),
      ),
    );
  }
}

/// `.seg` — styles.css:236. The selected segment takes the navy hero fill,
/// never a grey (Principles §5).
class HwSegmented extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const HwSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardline, width: 1.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: HwPress(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: HwMotion.t2,
                  curve: HwMotion.ease,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: i == selectedIndex ? p.heroGrad : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == selectedIndex ? p.shadow : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w700,
                      color: i == selectedIndex
                          ? const Color(0xFFF2E9E2)
                          : p.ink3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `#sheet` — styles.css:313. One scaffold for every bottom sheet: 28px top
/// radius, grab handle, 82% max height, safe-area bottom padding.
///
/// Always presented on the root navigator — the tabs live inside a ShellRoute
/// whose Navigator only covers the Scaffold body, so a sheet without this
/// renders behind the bottom nav.
Future<T?> showHwSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    barrierColor: const Color.fromRGBO(15, 20, 24, .45),
    builder: (sheetContext) => HwSheet(child: builder(sheetContext)),
  );
}

class HwSheet extends StatelessWidget {
  final Widget child;
  const HwSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final media = MediaQuery.of(context);
    // Height of the on-screen keyboard, 0 when it is closed.
    final keyboard = media.viewInsets.bottom;
    final open = keyboard > 0;

    // KEYBOARD HANDLING. Two things are needed and both were missing, which is
    // why every sheet with a text field was covered:
    //
    //  1. The sheet has to be pushed UP by the keyboard height. A modal bottom
    //     sheet is laid out against the full screen, so without this the
    //     keyboard simply draws on top of the fields and the primary button.
    //  2. The max height has to be measured against the space that is actually
    //     left. `size.height * 0.82` is 82% of the WHOLE screen — with a
    //     keyboard taking ~40%, that alone still overflows.
    //
    // With the keyboard open the sheet is allowed 94% of what remains rather
    // than 82%: the spec's 82% exists to leave a comfortable strip of page
    // visible above the sheet, and once the keyboard is up that strip is gone
    // anyway — the useful thing is to keep as many fields on screen as possible.
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: (media.size.height - keyboard) * (open ? 0.94 : 0.82),
          ),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: p.shadowLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4.5,
                margin: const EdgeInsets.fromLTRB(0, 6, 0, 14),
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(HwRadius.pill),
                ),
              ),
              Flexible(
                child: Padding(
                  // The 24px bottom breathing room is only wanted when the sheet
                  // is sitting on the screen edge. With the keyboard up it is
                  // dead space between the button and the keys.
                  padding: EdgeInsets.fromLTRB(20, 0, 20, open ? 8 : 24),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.field` — styles.css:358. Label over a bordered input that takes a copper
/// border on focus.
class HwField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool readOnly;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;

  const HwField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.readOnly = false,
    this.keyboardType,
    this.validator,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: p.line, width: 1.5),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: HwType.cap,
              fontWeight: FontWeight.w700,
              color: p.ink2,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            readOnly: readOnly,
            keyboardType: keyboardType,
            validator: validator,
            onTap: onTap,
            style: TextStyle(fontSize: HwType.base, color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: p.card2,
              hintText: hint,
              hintStyle: TextStyle(fontSize: HwType.base, color: p.ink3),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: p.copper, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: p.low, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: p.low, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The copper primary button (`--sun-grad`) and its ghost variant.
class HwButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;
  final Color? tint;

  const HwButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.busy = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final enabled = onTap != null && !busy;
    final accent = tint ?? p.copper;

    return Opacity(
      opacity: enabled ? 1 : .5,
      child: HwPress(
        onTap: enabled ? onTap! : () {},
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: filled ? p.sunGrad : null,
            borderRadius: BorderRadius.circular(HwRadius.sm),
            border:
                filled ? null : Border.all(color: accent, width: 1.5),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.sm,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : p.copperInk,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// `.skiplink` — styles.css:338. A quiet, full-width text action.
class HwSkipLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const HwSkipLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HwPress(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w600,
              color: RefPalette.of(context).ink3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Report generation state — `.statusbanner`, styles.css:408.
enum HwStatus { generating, ready, failed }

class HwStatusBanner extends StatelessWidget {
  final HwStatus status;
  const HwStatusBanner(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    late final Color fg;
    late final Color bg;
    late final String label;
    switch (status) {
      case HwStatus.generating:
        fg = p.mid;
        bg = p.midSoft;
        label = 'Generating';
        break;
      case HwStatus.ready:
        fg = p.good;
        bg = p.goodSoft;
        label = 'Ready';
        break;
      case HwStatus.failed:
        fg = p.low;
        bg = p.lowSoft;
        label = 'Failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HwRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == HwStatus.generating) ...[
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: HwType.eyebrow,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small notice for feature-gated surfaces that should not be tapped yet.
class HwComingSoonBanner extends StatelessWidget {
  final String label;
  final bool compact;

  const HwComingSoonBanner({
    super.key,
    this.label = 'Coming soon',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: p.midSoft,
        borderRadius: BorderRadius.circular(HwRadius.pill),
        border: Border.all(color: p.mid.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: compact ? 12 : 14,
            color: p.mid,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? HwType.eyebrow : HwType.cap,
              fontWeight: FontWeight.w800,
              color: p.mid,
            ),
          ),
        ],
      ),
    );
  }
}
