import 'package:flutter/material.dart';

import '../../ai_report_style.dart';
import '../report_widgets.dart';

/// At-Home Mobility Support (web `UserReport` section 7).
class AtHomeSupportSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const AtHomeSupportSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['at_home_mobility_support']);
    final rationale = RW.str(m, 'selection_rationale');
    final exercises = RW.asMapList(m['exercises']);
    final relief = RW.asStrList(m['relief_based_mapping']);
    final daily = RW.str(m, 'daily_integration_guidance');
    final goal = RW.str(m, 'functional_goal');

    final blocks = <Widget>[];

    if (rationale.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Selection Rationale',
        child: RW.paragraph(rationale),
      ));
    }

    if (exercises.isNotEmpty) {
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RW.subLabel('Exercises'),
      ));
      for (var i = 0; i < exercises.length; i++) {
        blocks.add(_exerciseCard(exercises[i], i));
      }
    }

    if (relief.isNotEmpty) {
      blocks.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RW.subLabel('Relief-Based Mapping'),
            RW.chipWrap(relief,
                bg: HydraReport.green50,
                border: HydraReport.green100,
                fg: HydraReport.green800),
          ],
        ),
      ));
    }

    if (daily.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.darkTeal.withValues(alpha: 0.05),
        border: HydraReport.darkTeal.withValues(alpha: 0.1),
        label: 'Daily Integration Guidance',
        child: RW.paragraph(daily),
      ));
    }

    if (goal.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Functional Goal',
        child: RW.paragraph(goal, weight: FontWeight.w700),
      ));
    }

    return RW.section(
      icon: Icons.lightbulb_rounded,
      title: 'At-Home Mobility Support',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }

  Widget _exerciseCard(Map<String, dynamic> ex, int index) {
    final procedure = RW.asStrList(ex['procedure']);
    final notes = RW.str(ex, 'important_notes');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HydraReport.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: HydraReport.tanLight.withValues(alpha: 0.5), width: 1.4),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _numBadge(index + 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(RW.str(ex, 'name'),
                        style: const TextStyle(
                            color: HydraReport.darkTeal,
                            fontSize: 14,
                            fontWeight: FontWeight.w900)),
                    if (RW.str(ex, 'addresses').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Addresses: ${RW.str(ex, 'addresses')}',
                          style: const TextStyle(
                              color: HydraReport.tanDark,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              if (RW.str(ex, 'frequency').isNotEmpty ||
                  RW.str(ex, 'duration_reps').isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (RW.str(ex, 'frequency').isNotEmpty)
                        Text(RW.str(ex, 'frequency').toUpperCase(),
                            textAlign: TextAlign.right,
                            softWrap: true,
                            style: const TextStyle(
                                color: HydraReport.muted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      if (RW.str(ex, 'duration_reps').isNotEmpty)
                        Text(RW.str(ex, 'duration_reps').toUpperCase(),
                            textAlign: TextAlign.right,
                            softWrap: true,
                            style: const TextStyle(
                                color: HydraReport.tanDark,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (procedure.isNotEmpty) ...[
            const SizedBox(height: 12),
            RW.subLabel('Procedure'),
            for (var si = 0; si < procedure.length; si++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: HydraReport.darkTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${si + 1}',
                          style: const TextStyle(
                              color: HydraReport.darkTeal,
                              fontSize: 9,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(procedure[si],
                          style: const TextStyle(
                              color: HydraReport.darkTeal,
                              fontSize: 12,
                              height: 1.45)),
                    ),
                  ],
                ),
              ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            RW.iconCard(Icons.warning_amber_rounded, notes,
                iconColor: HydraReport.yellow600,
                bg: HydraReport.yellow50,
                border: HydraReport.yellow100,
                textColor: HydraReport.yellow900),
          ],
        ],
      ),
    );
  }

  Widget _numBadge(int n) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HydraReport.tanDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$n',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900)),
      );
}
