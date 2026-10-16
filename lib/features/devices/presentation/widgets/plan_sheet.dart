import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/widgets/hw_tablet.dart';
import 'session_plan_widgets.dart';

/// The v6 sheet (`#sheet` + `.ry-sheethead`): a bottom drawer on a phone,
/// and on a tablet (`97-tablet` §6) a centred form sheet, 560px wide and at
/// most 76% of the screen tall. [builder] returns the body under the title;
/// a body that can outgrow the sheet should scroll itself (a
/// `SingleChildScrollView`, or a `Column` with a `Flexible` list).
Future<T?> showPlanSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? headerAction,
  required WidgetBuilder builder,
}) {
  final tablet = HwTablet.of(context);
  Widget frame(BuildContext ctx) => _PlanSheetFrame(
        title: title,
        subtitle: subtitle,
        headerAction: headerAction,
        grab: !tablet,
        body: Builder(builder: builder),
      );

  if (tablet) {
    return showDialog<T>(
      context: context,
      barrierColor: const Color.fromRGBO(20, 16, 12, .45),
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: PlanTones.card(ctx),
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(560, size.width * .86),
              maxHeight: size.height * .76,
            ),
            child: frame(ctx),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PlanTones.card(context),
    barrierColor: const Color.fromRGBO(20, 16, 12, .45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: frame(ctx),
    ),
  );
}

class _PlanSheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? headerAction;
  final bool grab;
  final Widget body;
  const _PlanSheetFrame({
    required this.title,
    required this.subtitle,
    required this.headerAction,
    required this.grab,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    // Keep the title, close button and body as separate screen-reader
    // stops — inside a Dialog (tablet) they would otherwise merge into one.
    return Semantics(
      explicitChildNodes: true,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, grab ? 10 : 22, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (grab)
                Center(
                  child: Container(
                    width: 40,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color.fromRGBO(255, 255, 255, .12)
                          : const Color.fromRGBO(26, 26, 26, .08),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              // `.ry-sheethead`
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: dark
                                  ? const Color(0xFFF1E4D6)
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: PlanTones.sub(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (headerAction != null) ...[
                    const SizedBox(width: 8),
                    headerAction!,
                  ],
                  const SizedBox(width: 8),
                  // `.ry-x`
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: PlanPress(
                      onTap: () => Navigator.of(context).maybePop(),
                      scale: .92,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: PlanTones.card(context),
                              border: Border.all(
                                color: dark
                                    ? const Color.fromRGBO(255, 255, 255, .12)
                                    : const Color.fromRGBO(26, 26, 26, .08),
                              ),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: dark
                                  ? const Color(0xFFCDB9A5)
                                  : const Color(0xFF5E5852),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-search.sheet` — the search pill at the top of a picker.
class PlanSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const PlanSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF15171C) : const Color(0xFFF7F3F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark
              ? const Color.fromRGBO(255, 255, 255, .08)
              : const Color.fromRGBO(26, 26, 26, .06),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: PlanTones.sub(context)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              autofocus: false,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 14,
                color: dark ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: PlanTones.sub(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.ry-ses-ava` — initials on warm pink, or the dashed "GU" guest ring.
class PlanAvatar extends StatelessWidget {
  final String? initials;
  final double size;
  const PlanAvatar({super.key, required this.initials, this.size = 32});

  @override
  Widget build(BuildContext context) {
    if (initials != null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFF1D4C4),
        ),
        child: Text(
          initials!,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF7A5142),
          ),
        ),
      );
    }
    final c = PlanTones.dark(context)
        ? const Color(0xFFAFBCC6)
        : const Color(0xFF5E5852);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DashRing(c),
        child: Center(
          child: Text(
            'GU',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashRing extends CustomPainter {
  final Color color;
  const _DashRing(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 1;
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const dashes = 14;
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step,
          step * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashRing old) => old.color != color;
}

/// `.ry-ses-ck` — the copper dot marking the chosen row.
class PlanPickedDot extends StatelessWidget {
  const PlanPickedDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(168, 123, 92, .7),
              blurRadius: 6,
              spreadRadius: -2,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      );
}

// ─────────────────────────────── Intake form (`.v5i`) ─────────────────────────

/// `.v5i-f > span` — a field label, with an optional muted tag
/// ("optional", "tap all that apply").
class PlanFieldLabel extends StatelessWidget {
  final String text;
  final String? tag;
  const PlanFieldLabel(this.text, {super.key, this.tag});

  @override
  Widget build(BuildContext context) {
    final sub = PlanTones.sub(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (tag != null)
            TextSpan(
              text: '  $tag',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: sub.withValues(alpha: .75),
              ),
            ),
        ]),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: sub,
        ),
      ),
    );
  }
}

InputBorder _fieldBorder(Color c, [double w = 1.5]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );

Color _fieldLine(BuildContext context) => PlanTones.dark(context)
    ? const Color.fromRGBO(255, 255, 255, .1)
    : const Color.fromRGBO(26, 26, 26, .08);

/// `.v5i-f input` — a 16px-round field on the card colour; copper on focus.
/// [unit] sits inside the right edge (`.v5i-unit i`), always visible.
class PlanTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final String? unit;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  const PlanTextField({
    super.key,
    required this.controller,
    this.hint,
    this.unit,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final sub = PlanTones.sub(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(
        fontSize: 15,
        color: dark ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sub),
        suffixIcon: unit == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 14, left: 6),
                child: Text(
                  unit!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sub,
                  ),
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: dark ? const Color(0xFF15171C) : PlanTones.card(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _fieldBorder(_fieldLine(context)),
        enabledBorder: _fieldBorder(_fieldLine(context)),
        focusedBorder: _fieldBorder(PlanTones.copper),
      ),
    );
  }
}

/// `.v5i-f select` — a closed dropdown box matching [PlanTextField].
class PlanSelectBox extends StatelessWidget {
  final Widget child;
  const PlanSelectBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF15171C) : PlanTones.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _fieldLine(context), width: 1.5),
      ),
      child: child,
    );
  }
}

/// `.v5i-chip` — a pickable pill (positions).
class PlanChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const PlanChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Semantics(
      button: true,
      selected: selected,
      child: PlanPress(
        onTap: onTap,
        scale: .95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? const Color(0xFF2A221C) : const Color(0xFFF7EDE4))
                : (dark ? const Color(0xFF15171C) : PlanTones.card(context)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? PlanTones.copper : _fieldLine(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? (dark ? const Color(0xFFE7C9A9) : PlanTones.copperInk)
                  : (dark ? const Color(0xFFE7D3C0) : const Color(0xFF1A1A1A)),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.btn.primary` (`.v5i-go`) — the copper action at the foot of a sheet.
class PlanPrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const PlanPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PlanPress(
        onTap: busy ? null : onTap,
        scale: .98,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFDEB393), Color(0xFFC69E83), Color(0xFFB27D5C)],
              stops: [0, .45, 1],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(168, 123, 92, .85),
                blurRadius: 20,
                spreadRadius: -10,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(PlanTones.copperText),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PlanTones.copperText,
                  ),
                ),
        ),
      ),
    );
  }
}
