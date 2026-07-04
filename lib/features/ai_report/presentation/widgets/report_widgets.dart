import 'package:flutter/material.dart';

import '../ai_report_style.dart';

/// Shared building blocks for the bespoke AI-report sections, mirroring the web
/// `analysis-display.tsx` shared components (SectionHeader / SubLabel /
/// ConfidenceBadge / DirectionTag / colored callouts). Section widgets under
/// `widgets/sections/` compose these so every section matches the web layout.
class RW {
  RW._();

  // --- Loosely-typed report accessors ------------------------------------

  static Map<String, dynamic> asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static List<dynamic> asList(dynamic v) => v is List ? v : const [];

  /// Non-empty string list (drops blanks/nulls).
  static List<String> asStrList(dynamic v) => asList(v)
      .where((e) => e != null && e.toString().trim().isNotEmpty)
      .map((e) => e.toString())
      .toList();

  /// List of maps only.
  static List<Map<String, dynamic>> asMapList(dynamic v) => asList(v)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  static String str(Map<String, dynamic> m, String key) =>
      (m[key] ?? '').toString().trim();

  static bool has(dynamic v) => HydraReport.hasContent(v);

  /// Replace underscores with spaces (web `.replace(/_/g, " ")`).
  static String unslug(String s) => s.replaceAll('_', ' ').trim();

  // --- Text styles --------------------------------------------------------

  static const TextStyle body = TextStyle(
      color: HydraReport.darkTeal, fontSize: 13, height: 1.45);

  static TextStyle bodyBold({Color? color, double size = 13}) => TextStyle(
      color: color ?? HydraReport.darkTeal,
      fontSize: size,
      height: 1.4,
      fontWeight: FontWeight.w700);

  // --- Section shell + header --------------------------------------------

  /// Outer section card + `SectionHeader` (tan icon + uppercase gray-500 title).
  static Widget section({
    required IconData icon,
    required String title,
    required Widget child,
    Color? background,
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background ?? HydraReport.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: borderColor ?? HydraReport.tanLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(icon, title),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  static Widget sectionHeader(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 17, color: HydraReport.tanDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: HydraReport.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      );

  /// Small uppercase sub-label above a block (web `SubLabel`).
  static Widget subLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: HydraReport.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      );

  static Widget paragraph(String text,
          {Color color = HydraReport.darkTeal,
          double size = 13,
          FontWeight weight = FontWeight.w500}) =>
      Text(text,
          softWrap: true,
          style: TextStyle(
              color: color, fontSize: size, height: 1.5, fontWeight: weight));

  // --- Badges / tags / chips ---------------------------------------------

  /// Confidence pill with a glowing dot + `{level}%` (tan primary / teal alt).
  static Widget confidenceBadge(num level, {bool alternative = false}) {
    final c = alternative ? HydraReport.darkTeal : HydraReport.tanDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: alternative
                  ? null
                  : [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 7),
          Text('${level.round()}%',
              style: TextStyle(
                  color: c, fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  /// Solid confidence chip "{level}%" (used in compact practitioner headers).
  static Widget percentChip(dynamic level, {bool alternative = false}) {
    final c = alternative ? HydraReport.darkTeal : HydraReport.tanDark;
    final txt = level is num ? '${level.round()}%' : '--%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
      child: Text(txt,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }

  /// Teal direction tag mapping proximal/distal (web `DirectionTag`).
  static Widget directionTag(String? direction) {
    final label = (direction == null || direction.isEmpty)
        ? 'Unknown'
        : direction == 'proximal_to_distal'
            ? 'Proximal to Distal'
            : direction == 'distal_to_proximal'
                ? 'Distal to Proximal'
                : unslug(direction);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HydraReport.darkTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: HydraReport.darkTeal.withValues(alpha: 0.2)),
      ),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              color: HydraReport.darkTeal,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6)),
    );
  }

  /// Rounded chip. Defaults to a white pill with a tan border.
  static Widget chip(String text,
      {Color bg = HydraReport.white,
      Color? border,
      Color fg = HydraReport.darkTeal,
      double fontSize = 12,
      FontWeight weight = FontWeight.w700}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border ?? HydraReport.tanLight),
      ),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: fontSize, fontWeight: weight)),
    );
  }

  /// A small uppercase pill label (e.g. driver / type badges).
  static Widget miniBadge(String text, {required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: fg,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6)),
      );

  static Widget chipWrap(List<String> items,
          {Color bg = HydraReport.white,
          Color? border,
          Color fg = HydraReport.darkTeal}) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in items) chip(t, bg: bg, border: border, fg: fg),
        ],
      );

  // --- Bullets / icon rows -----------------------------------------------

  /// Tan-dot bullet row on a tinted card (web primary_movement_findings style).
  static Widget bulletCard(String text,
      {Color bg = HydraReport.cream,
      Color? border,
      Color dot = HydraReport.tanDark,
      Color textColor = HydraReport.darkTeal}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: border ?? HydraReport.tanLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(text,
                softWrap: true,
                style: TextStyle(
                    color: textColor, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// Icon + text row on a tinted card (check / alert style).
  static Widget iconCard(IconData icon, String text,
      {required Color iconColor,
      required Color bg,
      required Color border,
      Color textColor = HydraReport.darkTeal}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          Expanded(
            child: Text(text,
                softWrap: true,
                style: TextStyle(
                    color: textColor, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// Inline "Label: value" (RichText) that wraps.
  static Widget kv(String label, String value,
      {Color color = HydraReport.darkTeal, double size = 12.5}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: color, fontSize: size, height: 1.4),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  // --- Colored callout containers ----------------------------------------

  /// A tinted box with an optional uppercase label heading.
  static Widget callout({
    required Widget child,
    required Color bg,
    required Color border,
    String? label,
    Color? labelColor,
    double borderWidth = 1,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: labelColor ?? HydraReport.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }

  /// Solid dark-teal verdict card with white label + body (web summary_verdict).
  static Widget verdictCard(List<(String, String)> entries) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HydraReport.darkTeal,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(entries[i].$1.toUpperCase(),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Text(entries[i].$2,
                softWrap: true,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }

  // --- Muscle chain flow --------------------------------------------------

  /// Muscle chips joined by arrows (web "Structural Kinetic Chain Map" flow).
  /// [teal] = Pattern B outline style; otherwise Pattern A solid dark-teal.
  static Widget muscleChain(List<String> muscles, {bool teal = false}) {
    final children = <Widget>[];
    for (var i = 0; i < muscles.length; i++) {
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: teal
                ? HydraReport.darkTeal.withValues(alpha: 0.08)
                : HydraReport.darkTeal,
            borderRadius: BorderRadius.circular(12),
            border: teal
                ? Border.all(
                    color: HydraReport.darkTeal.withValues(alpha: 0.2))
                : null,
          ),
          child: Text(muscles[i],
              style: TextStyle(
                  color: teal ? HydraReport.darkTeal : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ),
      );
      if (i < muscles.length - 1) {
        children.add(Icon(Icons.arrow_forward_rounded,
            size: 16,
            color: teal ? HydraReport.gray400 : HydraReport.tanDark));
      }
    }
    return Wrap(
        spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }

  // --- Responsive grid ----------------------------------------------------

  /// 1 column on narrow phones, [cols] columns when wide enough (web
  /// `grid-cols-1 sm:grid-cols-N`).
  static Widget grid(List<Widget> children, {int cols = 2, double gap = 10}) {
    final items = children.where((_) => true).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (ctx, c) {
      final maxW = c.maxWidth;
      final effective = maxW < 420 ? 1 : cols;
      if (effective <= 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              items[i],
            ],
          ],
        );
      }
      final itemW = (maxW - gap * (effective - 1)) / effective;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final ch in items) SizedBox(width: itemW, child: ch),
        ],
      );
    });
  }

  /// A small stat card (label on top, big value below) — web personal-snapshot
  /// / clinical-insight tiles.
  static Widget statCard(String label, String value,
      {Color valueColor = HydraReport.darkTeal,
      double valueSize = 15,
      Color bg = HydraReport.cream}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: HydraReport.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value,
              softWrap: true,
              style: TextStyle(
                  color: valueColor,
                  fontSize: valueSize,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// Fallback renderer for unknown report keys so nothing is silently dropped
/// (keeps the pre-rewrite generic behavior for extra API fields).
class GenericSection extends StatelessWidget {
  final String title;
  final dynamic value;
  const GenericSection(this.title, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return RW.section(
      icon: Icons.article_outlined,
      title: title,
      child: _node(value),
    );
  }

  Widget _node(dynamic value) {
    if (value is String || value is num || value is bool) {
      return Text(value.toString(), style: RW.body);
    }
    if (value is List) {
      final items = value.where(RW.has).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      if (items.every((e) => e is String || e is num || e is bool)) {
        return RW.chipWrap(items.map((e) => e.toString()).toList());
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _node(item)),
        ],
      );
    }
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in value.entries.where((e) => RW.has(e.value)))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RW.subLabel(HydraReport.humanize(e.key.toString())),
                  _node(e.value),
                ],
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
