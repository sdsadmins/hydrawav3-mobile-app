import 'package:flutter/material.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../ai_report_style.dart';

/// "Show the full analysis" disclosure.
///
/// The UI spec's report has no expanders — its report is a 6-section mock. Ours
/// is fed by a real AI response with far more detail, and the whole point of the
/// six-section structure is that the summary reads quickly while none of the
/// real clinical content is thrown away. This is where the rest lives.
///
/// The expanded body renders on a `HydraReport.cream` sheet: those detail
/// widgets are a static light-mode palette (see `ai_report_style.dart`), so the
/// sheet makes the light surface read as a printed document rather than a
/// theming mistake.
class ReportExpander extends StatefulWidget {
  final String label;
  final List<Widget> children;

  const ReportExpander({
    super.key,
    this.label = 'Show the full analysis',
    required this.children,
  });

  @override
  State<ReportExpander> createState() => _ReportExpanderState();
}

class _ReportExpanderState extends State<ReportExpander> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final p = RefPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HwPress(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            margin: const EdgeInsets.only(top: HwSpace.s3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: p.card2,
              borderRadius: BorderRadius.circular(HwRadius.sm),
              border: Border.all(color: p.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _open ? 'Hide the full analysis' : widget.label,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: HwMotion.t2,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: p.copperInk),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: HwMotion.t2,
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: HwSpace.s2),
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 2),
            decoration: BoxDecoration(
              color: HydraReport.cream,
              borderRadius: BorderRadius.circular(HwRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}
