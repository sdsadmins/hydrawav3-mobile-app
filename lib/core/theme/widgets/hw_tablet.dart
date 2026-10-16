import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../constants/theme_constants.dart';

/// Tablet layout, after the v6 prototype's `hydrawav3-v6/97-tablet.js`.
///
/// Two column tiers, after Apple's split between grid content and readable
/// content on iPad:
///   * [wide] — things you scan (Hub widgets, live units): 786px.
///   * [read] — things you read or fill in: 680px.
/// both centred with at least a [gutter] of 24px either side.
///
/// Grids are "auto-fit" with a minimum track ([minTrack]) rather than a fixed
/// column count, so they collapse correctly when the app is resized in iPad
/// Split View / Slide Over / Stage Manager.
class HwTablet {
  HwTablet._();

  static const double wide = 786;
  static const double read = 680;
  static const double gutter = 24;
  static const double minTrack = 340;

  /// True on a tablet-width window (the app's existing 600px breakpoint).
  static bool of(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= ThemeConstants.tabletBreakpoint;

  /// Side padding that centres a [column]-wide content area, never less than
  /// [gutter]. On a phone, returns [phone] unchanged.
  static double sidePadding(BuildContext context,
      {double column = wide, double phone = 18}) {
    if (!of(context)) return phone;
    final w = MediaQuery.sizeOf(context).width;
    return math.max(gutter, (w - column) / 2);
  }
}

/// `display:grid; grid-template-columns: repeat(auto-fit, minmax(min, 1fr));
/// align-items: start` — as many equal columns as fit at [minTrack] each,
/// children top-aligned in rows. [fullWidth] children take a row of their own.
class HwAutoGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTrack;
  final double gap;

  /// Indices of children that span every column (e.g. Quick Start).
  final Set<int> fullWidth;

  const HwAutoGrid({
    super.key,
    required this.children,
    this.minTrack = HwTablet.minTrack,
    this.gap = 16,
    this.fullWidth = const {},
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + gap) / (minTrack + gap)).floor());
      final rows = <Widget>[];
      var row = <Widget>[];

      void flush() {
        if (row.isEmpty) return;
        // Pad a short last row with empty cells so every column keeps the
        // same width, as a CSS grid does.
        while (row.length < cols) {
          row.add(const SizedBox.shrink());
        }
        final cells = <Widget>[];
        for (var i = 0; i < row.length; i++) {
          if (i > 0) cells.add(SizedBox(width: gap));
          cells.add(Expanded(child: row[i]));
        }
        rows.add(
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
        row = [];
      }

      for (var i = 0; i < children.length; i++) {
        if (fullWidth.contains(i) || cols == 1) {
          flush();
          rows.add(children[i]);
          continue;
        }
        row.add(children[i]);
        if (row.length == cols) flush();
      }
      flush();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            rows[i],
          ],
        ],
      );
    });
  }
}
