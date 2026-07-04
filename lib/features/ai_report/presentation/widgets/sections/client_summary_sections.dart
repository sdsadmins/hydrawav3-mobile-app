import 'package:flutter/material.dart';

import '../../ai_report_style.dart';
import '../report_widgets.dart';

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Personal Snapshot (web `UserReport` section 0).
class PersonalSnapshotSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const PersonalSnapshotSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['personal_snapshot']);
    final age = RW.str(m, 'age');
    final gender = RW.str(m, 'gender');
    final primary = RW.str(m, 'primary_concern');
    final secondary = RW.asStrList(m['secondary_concerns']);
    final duration = RW.str(m, 'pain_duration_category');

    return RW.section(
      icon: Icons.person_rounded,
      title: 'Personal Snapshot',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RW.grid([
            if (age.isNotEmpty) RW.statCard('Age', age, valueSize: 20),
            if (gender.isNotEmpty)
              RW.statCard('Gender', _cap(gender), valueSize: 20),
          ], cols: 2),
          if (primary.isNotEmpty) ...[
            const SizedBox(height: 10),
            RW.callout(
              bg: HydraReport.cream,
              border: HydraReport.tanLight.withValues(alpha: 0.4),
              label: 'Primary Concern',
              child: RW.paragraph(primary),
            ),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 2),
            RW.callout(
              bg: HydraReport.cream,
              border: HydraReport.tanLight.withValues(alpha: 0.4),
              label: 'Secondary Concerns',
              child: RW.chipWrap(secondary),
            ),
          ],
          if (duration.isNotEmpty) ...[
            const SizedBox(height: 2),
            RW.statCard('Pain Duration', _cap(RW.unslug(duration)),
                valueColor: HydraReport.tanDark, valueSize: 16),
          ],
        ],
      ),
    );
  }
}

/// Clinical Insight Summary (web `UserReport` section 1).
class ClinicalInsightSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const ClinicalInsightSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['clinical_insight_snapshot']);
    final summary = RW.str(m, 'summary_statement');
    final bias = RW.str(m, 'primary_movement_bias');
    final chain = RW.str(m, 'dominant_kinetic_chain');
    final region = RW.str(m, 'primary_symptom_region');

    return RW.section(
      icon: Icons.insights_rounded,
      title: 'Clinical Insight Summary',
      background: HydraReport.cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary.isNotEmpty) ...[
            RW.paragraph(summary),
            const SizedBox(height: 14),
          ],
          RW.grid([
            if (bias.isNotEmpty)
              RW.statCard('Movement Bias', bias,
                  valueSize: 13, bg: HydraReport.white),
            if (chain.isNotEmpty)
              RW.statCard('Dominant Chain', chain,
                  valueSize: 13, bg: HydraReport.white),
            if (region.isNotEmpty)
              RW.statCard('Symptom Region', region,
                  valueSize: 13, bg: HydraReport.white),
          ], cols: 3),
        ],
      ),
    );
  }
}

/// Movement & Mobility Summary (web `UserReport` section 2, sub-blocks A–F).
class MovementMobilitySection extends StatelessWidget {
  final Map<String, dynamic> report;
  const MovementMobilitySection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['movement_mobility_summary']);
    final findings = RW.asStrList(m['primary_movement_findings']);
    final critical = RW.asMap(m['critical_indicator']);
    final sensations = RW.asMapList(m['post_movement_sensations']);
    final secondaryDir = RW.asMap(m['secondary_pattern_direction']);
    final biasClass = RW.str(m, 'movement_bias_classification');
    final userInsight = RW.str(m, 'user_insight_integration');

    final blocks = <Widget>[];

    if (findings.isNotEmpty) {
      blocks.add(_block('A. Primary Movement Findings',
          Column(children: [for (final f in findings) RW.bulletCard(f)])));
    }

    if (RW.str(critical, 'exact_response').isNotEmpty) {
      blocks.add(_block(
        'B. Critical Indicator',
        RW.callout(
          bg: HydraReport.red50,
          border: HydraReport.red500.withValues(alpha: 0.35),
          borderWidth: 1.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _redField('Exact Response', RW.str(critical, 'exact_response')),
              if (RW.str(critical, 'muscle_group_implicated').isNotEmpty)
                _redField('Muscle Group Implicated',
                    RW.str(critical, 'muscle_group_implicated')),
              if (RW.str(critical, 'mechanical_significance').isNotEmpty)
                _redField('Mechanical Significance',
                    RW.str(critical, 'mechanical_significance')),
            ],
          ),
        ),
      ));
    }

    if (sensations.isNotEmpty) {
      blocks.add(_block(
        'C. Post-Movement Sensations',
        RW.grid([
          for (final s in sensations)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HydraReport.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: HydraReport.tanLight.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                          text: RW.str(s, 'location'),
                          style: RW.bodyBold()),
                      if (RW.str(s, 'side').isNotEmpty)
                        TextSpan(
                            text: '  (${RW.str(s, 'side')})',
                            style: const TextStyle(
                                color: HydraReport.gray400, fontSize: 11)),
                    ]),
                  ),
                  if (RW.str(s, 'quality').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(RW.str(s, 'quality'),
                        style: const TextStyle(
                            color: HydraReport.muted, fontSize: 12)),
                  ],
                ],
              ),
            ),
        ], cols: 2),
      ));
    }

    if (RW.str(secondaryDir, 'chain_map').isNotEmpty) {
      blocks.add(_block(
        'D. Secondary Pattern Direction',
        RW.callout(
          bg: HydraReport.darkTeal.withValues(alpha: 0.05),
          border: HydraReport.darkTeal.withValues(alpha: 0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (RW.str(secondaryDir, 'classification').isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: RW.chip(
                    RW.unslug(RW.str(secondaryDir, 'classification'))
                        .toUpperCase(),
                    bg: HydraReport.darkTeal.withValues(alpha: 0.1),
                    border: HydraReport.darkTeal.withValues(alpha: 0.2),
                    fg: HydraReport.darkTeal,
                    fontSize: 9.5,
                    weight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              RW.paragraph(RW.str(secondaryDir, 'chain_map')),
            ],
          ),
        ),
      ));
    }

    if (biasClass.isNotEmpty) {
      blocks.add(_block(
        'E. Movement Bias Classification',
        Align(
          alignment: Alignment.centerLeft,
          child: RW.chip(
            RW.unslug(biasClass).toUpperCase(),
            bg: HydraReport.tanDark.withValues(alpha: 0.1),
            border: HydraReport.tanDark.withValues(alpha: 0.2),
            fg: HydraReport.tanDark,
            fontSize: 11,
            weight: FontWeight.w900,
          ),
        ),
      ));
    }

    if (userInsight.isNotEmpty) {
      blocks.add(_block(
        'F. User Insight Integration',
        RW.callout(
          bg: HydraReport.cream,
          border: HydraReport.tanLight.withValues(alpha: 0.4),
          child: RW.paragraph(userInsight),
        ),
      ));
    }

    return RW.section(
      icon: Icons.directions_run_rounded,
      title: 'Movement & Mobility Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            blocks[i],
          ],
        ],
      ),
    );
  }

  Widget _block(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [RW.subLabel(label), child],
      );

  Widget _redField(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    color: HydraReport.red500,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
            const SizedBox(height: 3),
            Text(value,
                softWrap: true,
                style: const TextStyle(
                    color: HydraReport.red900, fontSize: 13, height: 1.4)),
          ],
        ),
      );
}
