import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_names.dart';
import '../../../domain/kinetic_chain_payload.dart';
import '../../ai_report_style.dart';
import '../report_widgets.dart';

/// Outer card matching `RW.section` but with a custom header (so the confidence
/// badge can sit on the right of the title, as on web).
Widget _patternCard({
  required IconData icon,
  required String title,
  Widget? trailing,
  required List<Widget> children,
}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: HydraReport.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: RW.sectionHeader(icon, title)),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

Widget _sub(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [RW.subLabel(label), child],
      ),
    );

/// The reason cards under a kinetic-chain map (muscle + reason).
Widget _reasonCards(List<Map<String, dynamic>> chain, {bool teal = false}) {
  return RW.grid([
    for (final link in chain)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: teal
              ? HydraReport.darkTeal.withValues(alpha: 0.05)
              : HydraReport.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: teal
                  ? HydraReport.darkTeal.withValues(alpha: 0.1)
                  : HydraReport.tanLight.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(RW.str(link, 'muscle'), style: RW.bodyBold()),
            if (RW.str(link, 'reason').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(RW.str(link, 'reason'),
                  style: const TextStyle(
                      color: HydraReport.muted, fontSize: 12, height: 1.4)),
            ],
          ],
        ),
      ),
  ], cols: 2);
}

Widget _viewChainButton(BuildContext context, Map<String, dynamic> report,
    String which, bool teal) {
  final accent = teal ? HydraReport.darkTeal : HydraReport.tanDark;
  final label =
      teal ? 'View Kinetic Chain (Pattern B)' : 'View Kinetic Chain';
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SizedBox(
      width: double.infinity,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final payload = buildKineticChainPayload(report, which);
          context.pushNamed(
            RouteNames.kineticChain3d,
            extra: {
              'patternLabel':
                  'Kinetic Chain Visualization - Pattern ${which.toUpperCase()}',
              'payload': payload,
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.threed_rotation_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Full Kinetic-Chain pattern (web `PatternASection` / `PatternBSection`) for
/// the client "Your Report" tab. [which] is 'a' or 'b'.
class PatternFullSection extends StatelessWidget {
  final Map<String, dynamic> report;
  final String which;
  const PatternFullSection(this.report, this.which, {super.key});

  bool get _isB => which == 'b';

  @override
  Widget build(BuildContext context) {
    final p = RW.asMap(report['kinetic_chain_pattern_$which']);
    final confidence = RW.asMap(p['confidence']);
    final level = confidence['level'];
    final chain = RW.asMapList(p['primary_kinetic_chain']);
    final muscles = [
      for (final c in chain)
        if (RW.str(c, 'muscle').isNotEmpty) RW.str(c, 'muscle')
    ];
    final secondary = RW.asMapList(p['secondary_compensatory_regions']);

    final children = <Widget>[];

    // I. Pattern Identification.
    children.add(Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isB
            ? HydraReport.darkTeal.withValues(alpha: 0.05)
            : HydraReport.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _isB
                ? HydraReport.darkTeal.withValues(alpha: 0.1)
                : HydraReport.tanLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (RW.str(p, 'pattern_label').isNotEmpty)
            Text(RW.str(p, 'pattern_label'),
                style: const TextStyle(
                    color: HydraReport.darkTeal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (RW.str(p, 'primary_driver_region').isNotEmpty)
                Text('PRIMARY DRIVER: ${RW.str(p, 'primary_driver_region')}',
                    style: TextStyle(
                        color: _isB
                            ? HydraReport.gray400
                            : HydraReport.tanDark,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              RW.directionTag(RW.str(p, 'direction_of_dysfunction')),
            ],
          ),
          if (RW.str(p, 'direction_rationale').isNotEmpty) ...[
            const SizedBox(height: 10),
            RW.paragraph(RW.str(p, 'direction_rationale')),
          ],
        ],
      ),
    ));

    // II. Chain map.
    if (chain.isNotEmpty) {
      children.add(_sub(
        _isB ? 'II. Chain Map' : 'II. Structural Kinetic Chain Map',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RW.muscleChain(muscles, teal: _isB),
            const SizedBox(height: 12),
            _reasonCards(chain, teal: _isB),
          ],
        ),
      ));
    }

    // Secondary compensatory regions (yellow).
    if (secondary.isNotEmpty) {
      children.add(_sub(
        'Secondary Compensatory Regions',
        Column(
          children: [
            for (final sc in secondary)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HydraReport.yellow50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HydraReport.yellow100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(RW.str(sc, 'region'),
                              style: RW.bodyBold(
                                  color: HydraReport.yellow900)),
                        ),
                        if (!_isB && RW.str(sc, 'type').isNotEmpty) ...[
                          const SizedBox(width: 8),
                          RW.miniBadge(
                            RW.str(sc, 'type'),
                            bg: RW.str(sc, 'type') == 'driver'
                                ? HydraReport.red100
                                : HydraReport.yellow100,
                            fg: RW.str(sc, 'type') == 'driver'
                                ? HydraReport.red600
                                : HydraReport.yellow700,
                          ),
                        ],
                      ],
                    ),
                    if (RW.str(sc, 'mechanism').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                          _isB
                              ? '-- ${RW.str(sc, 'mechanism')}'
                              : RW.str(sc, 'mechanism'),
                          style: const TextStyle(
                              color: HydraReport.yellow700,
                              fontSize: 12,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    // 3D viewer button.
    if (kineticChainPatternHasData(report, which)) {
      children.add(_viewChainButton(context, report, which, _isB));
    }

    // Pattern-specific tail.
    if (_isB) {
      _buildPatternBTail(p, children);
    } else {
      _buildPatternATail(p, children);
    }

    // Confidence justification.
    final justification = RW.str(confidence, 'justification');
    if (justification.isNotEmpty) {
      children.add(RW.callout(
        bg: _isB
            ? HydraReport.darkTeal.withValues(alpha: 0.05)
            : HydraReport.cream,
        border: _isB
            ? HydraReport.darkTeal.withValues(alpha: 0.1)
            : HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Confidence Justification',
        child: RW.paragraph(justification),
      ));
    }

    // Verdict (Pattern B only) sits at the very bottom.
    if (_isB) {
      final verdict = RW.str(p, 'summary_verdict');
      final hierarchy = RW.str(p, 'pattern_hierarchy');
      if (verdict.isNotEmpty || hierarchy.isNotEmpty) {
        children.add(RW.verdictCard([
          if (verdict.isNotEmpty) ('Summary Verdict', verdict),
          if (hierarchy.isNotEmpty) ('Pattern Hierarchy', hierarchy),
        ]));
      }
    }

    return _patternCard(
      icon: _isB ? Icons.balance_rounded : Icons.timeline_rounded,
      title: _isB
          ? 'Kinetic Chain Pattern B (Alternative)'
          : 'Kinetic Chain Pattern A',
      trailing: level is num
          ? RW.confidenceBadge(level, alternative: _isB)
          : null,
      children: children,
    );
  }

  void _buildPatternATail(Map<String, dynamic> p, List<Widget> children) {
    final spinal = RW.asMapList(p['primary_spinal_segments']);
    final dermatomes = RW.asStrList(p['corresponding_dermatomes']);
    final viscero = RW.asStrList(p['viscerosomatic_associations']);
    final myofascial = RW.asMapList(p['myofascial_lines']);
    final biomech = RW.str(p, 'biomechanical_explanation');
    final supporting = RW.asStrList(p['supporting_findings']);
    final retests = RW.asMapList(p['suggested_retests']);

    // III. Neurological & Segmental Context (purple).
    if (spinal.isNotEmpty || dermatomes.isNotEmpty || viscero.isNotEmpty) {
      children.add(RW.callout(
        bg: HydraReport.purple50,
        border: HydraReport.purple100,
        label: 'III. Neurological & Segmental Context',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (spinal.isNotEmpty) ...[
              _miniLabel('Primary Spinal Segments', HydraReport.purple500),
              for (final seg in spinal)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HydraReport.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HydraReport.purple100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          RW.chip(RW.str(seg, 'segment'),
                              bg: HydraReport.purple100,
                              border: HydraReport.purple100,
                              fg: HydraReport.purple800,
                              fontSize: 11),
                          if (RW.str(seg, 'muscles').isNotEmpty)
                            Text(RW.str(seg, 'muscles'),
                                style: const TextStyle(
                                    color: HydraReport.purple700,
                                    fontSize: 12)),
                        ],
                      ),
                      if (RW.str(seg, 'functional_role').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(RW.str(seg, 'functional_role'),
                            style: const TextStyle(
                                color: HydraReport.muted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
            if (dermatomes.isNotEmpty) ...[
              _miniLabel('Corresponding Dermatomes', HydraReport.muted),
              RW.chipWrap(dermatomes,
                  bg: HydraReport.purple50,
                  border: HydraReport.purple100,
                  fg: HydraReport.purple700),
              const SizedBox(height: 10),
            ],
            if (viscero.isNotEmpty) ...[
              _miniLabel('Viscerosomatic Associations', HydraReport.muted),
              for (final v in viscero)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(v, style: RW.body),
                ),
            ],
          ],
        ),
      ));
    }

    // IV. Fascial & Global Integration.
    if (myofascial.isNotEmpty) {
      children.add(_sub(
        'IV. Fascial & Global Integration',
        Column(
          children: [
            for (final ml in myofascial)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HydraReport.darkTeal.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HydraReport.darkTeal.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(RW.str(ml, 'line_name'), style: RW.bodyBold()),
                    if (RW.str(ml, 'relevance').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(RW.str(ml, 'relevance'),
                          style: const TextStyle(
                              color: HydraReport.muted,
                              fontSize: 12,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    // V. Biomechanical Explanation.
    if (biomech.isNotEmpty) {
      children.add(_sub('V. Biomechanical Explanation', RW.paragraph(biomech)));
    }

    // VI. Supporting Findings (green).
    if (supporting.isNotEmpty) {
      children.add(_sub(
        'VI. Supporting Findings',
        Column(children: [
          for (final f in supporting)
            RW.iconCard(Icons.check_circle_rounded, f,
                iconColor: HydraReport.green600,
                bg: HydraReport.green50,
                border: HydraReport.green100),
        ]),
      ));
    }

    // Suggested Retests.
    if (retests.isNotEmpty) {
      children.add(_sub('Suggested Retests', _retestList(retests)));
    }
  }

  void _buildPatternBTail(Map<String, dynamic> p, List<Widget> children) {
    final biomech = RW.str(p, 'biomechanical_rationale');
    final whyPlausible = RW.asStrList(p['why_plausible']);
    final contradicting = RW.asStrList(p['contradicting_evidence']);
    final supporting = RW.asStrList(p['supporting_evidence']);
    final reframed = RW.str(p, 'user_insights_reframed');

    // III. Biomechanical Rationale.
    if (biomech.isNotEmpty) {
      children.add(_sub('III. Biomechanical Rationale', RW.paragraph(biomech)));
    }

    // IV. Competing Pattern Comparison.
    if (whyPlausible.isNotEmpty || contradicting.isNotEmpty) {
      children.add(_sub(
        'IV. Competing Pattern Comparison',
        RW.grid([
          if (whyPlausible.isNotEmpty)
            RW.callout(
              bg: HydraReport.green50,
              border: HydraReport.green100,
              label: 'Why Plausible',
              labelColor: HydraReport.green600,
              child: Column(
                children: [
                  for (final w in whyPlausible)
                    RW.iconCard(Icons.check_circle_rounded, w,
                        iconColor: HydraReport.green500,
                        bg: Colors.transparent,
                        border: Colors.transparent,
                        textColor: HydraReport.green900),
                ],
              ),
            ),
          if (contradicting.isNotEmpty)
            RW.callout(
              bg: HydraReport.red50,
              border: HydraReport.red100,
              label: 'Contradicting Evidence',
              labelColor: HydraReport.red500,
              child: Column(
                children: [
                  for (final c in contradicting)
                    RW.iconCard(Icons.warning_amber_rounded, c,
                        iconColor: HydraReport.red500,
                        bg: Colors.transparent,
                        border: Colors.transparent,
                        textColor: HydraReport.red900),
                ],
              ),
            ),
        ], cols: 2),
      ));
    }

    // Supporting Evidence.
    if (supporting.isNotEmpty) {
      children.add(_sub(
        'Supporting Evidence',
        Column(children: [for (final e in supporting) RW.bulletCard(e)]),
      ));
    }

    // User Insights Reframed.
    if (reframed.isNotEmpty) {
      children.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'User Insights Reframed',
        child: RW.paragraph(reframed),
      ));
    }
  }
}

Widget _miniLabel(String text, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1)),
    );

Widget _retestList(List<Map<String, dynamic>> retests) => Column(
      children: [
        for (final rt in retests)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HydraReport.darkTeal.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: HydraReport.darkTeal.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (RW.str(rt, 'name').isNotEmpty)
                  Text(RW.str(rt, 'name'),
                      style: RW.bodyBold(size: 12.5)),
                if (RW.str(rt, 'procedure').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(RW.str(rt, 'procedure'),
                      style: const TextStyle(
                          color: HydraReport.muted, fontSize: 12, height: 1.4)),
                ],
                if (RW.str(rt, 'observation').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Look for: ${RW.str(rt, 'observation')}',
                      style: const TextStyle(
                          color: HydraReport.tanDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
      ],
    );

/// Compact pattern summary (web `PractitionerReport` Pattern A/B) for the
/// Practitioner tab. [which] is 'a' or 'b'.
class PatternCompactSection extends StatelessWidget {
  final Map<String, dynamic> report;
  final String which;
  const PatternCompactSection(this.report, this.which, {super.key});

  bool get _isB => which == 'b';

  @override
  Widget build(BuildContext context) {
    final p = RW.asMap(report['kinetic_chain_pattern_$which']);
    final confidence = RW.asMap(p['confidence']);
    final chain = RW.asMapList(p['primary_kinetic_chain']);
    final chainText =
        chain.map((c) => RW.str(c, 'muscle')).where((s) => s.isNotEmpty).join(' --> ');

    final children = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Pattern ${which.toUpperCase()}: ${RW.str(p, 'pattern_label')}',
              style: const TextStyle(
                  color: HydraReport.darkTeal,
                  fontSize: 14,
                  fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          RW.percentChip(confidence['level'], alternative: _isB),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (RW.str(p, 'primary_driver_region').isNotEmpty)
            Text('DRIVER: ${RW.str(p, 'primary_driver_region')}',
                style: TextStyle(
                    color: _isB ? HydraReport.gray400 : HydraReport.tanDark,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          RW.directionTag(RW.str(p, 'direction_of_dysfunction')),
        ],
      ),
    ];

    if (chainText.isNotEmpty) {
      children.add(const SizedBox(height: 14));
      children.add(_sub('Kinetic Chain',
          Text(chainText, style: RW.bodyBold(size: 13))));
    }

    if (!_isB) {
      final spinal = RW.asMapList(p['primary_spinal_segments']);
      final myofascial = RW.asMapList(p['myofascial_lines']);
      final retests = RW.asMapList(p['suggested_retests']);
      if (spinal.isNotEmpty) {
        children.add(_sub(
          'Spinal Segments',
          RW.chipWrap([for (final s in spinal) RW.str(s, 'segment')],
              bg: HydraReport.purple100,
              border: HydraReport.purple100,
              fg: HydraReport.purple800),
        ));
      }
      if (myofascial.isNotEmpty) {
        children.add(_sub(
          'Myofascial Lines',
          RW.chipWrap([for (final ml in myofascial) RW.str(ml, 'line_name')],
              bg: HydraReport.darkTeal.withValues(alpha: 0.08),
              border: HydraReport.darkTeal.withValues(alpha: 0.2),
              fg: HydraReport.darkTeal),
        ));
      }
      if (retests.isNotEmpty) {
        children.add(_sub('Suggested Retests', _retestList(retests)));
      }
    } else {
      final whyPlausible = RW.asStrList(p['why_plausible']);
      final contradicting = RW.asStrList(p['contradicting_evidence']);
      if (whyPlausible.isNotEmpty || contradicting.isNotEmpty) {
        children.add(const SizedBox(height: 14));
        children.add(RW.grid([
          if (whyPlausible.isNotEmpty)
            RW.callout(
              bg: HydraReport.green50,
              border: HydraReport.green100,
              label: 'Why Plausible',
              labelColor: HydraReport.green600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in whyPlausible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(w,
                          style: const TextStyle(
                              color: HydraReport.green900, fontSize: 12)),
                    ),
                ],
              ),
            ),
          if (contradicting.isNotEmpty)
            RW.callout(
              bg: HydraReport.red50,
              border: HydraReport.red100,
              label: 'Contradicting Evidence',
              labelColor: HydraReport.red500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in contradicting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(c,
                          style: const TextStyle(
                              color: HydraReport.red900, fontSize: 12)),
                    ),
                ],
              ),
            ),
        ], cols: 2));
      }
      final verdict = RW.str(p, 'summary_verdict');
      if (verdict.isNotEmpty) {
        children.add(RW.verdictCard([('Verdict', verdict)]));
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HydraReport.white,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: HydraReport.tanLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
