import 'package:flutter/material.dart';

import '../../ai_report_style.dart';
import '../report_widgets.dart';

Widget _sub(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [RW.subLabel(label), child],
      ),
    );

/// Two tinted tissue boxes (Shortened=red / Lengthened=blue).
Widget _tissueBoxes(List<String> shortened, List<String> lengthened) {
  return RW.grid([
    if (shortened.isNotEmpty)
      RW.callout(
        bg: HydraReport.red50,
        border: HydraReport.red100,
        label: 'Shortened',
        labelColor: HydraReport.red500,
        child: RW.chipWrap(shortened,
            bg: HydraReport.red100,
            border: HydraReport.red100,
            fg: HydraReport.red800),
      ),
    if (lengthened.isNotEmpty)
      RW.callout(
        bg: HydraReport.blue50,
        border: HydraReport.blue100,
        label: 'Lengthened',
        labelColor: HydraReport.blue500,
        child: RW.chipWrap(lengthened,
            bg: HydraReport.blue100,
            border: HydraReport.blue100,
            fg: HydraReport.blue800),
      ),
  ], cols: 2);
}

/// Load vs Recovery Profile (web `UserReport` section 5).
class LoadRecoverySection extends StatelessWidget {
  final Map<String, dynamic> report;
  const LoadRecoverySection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['load_vs_recovery_profile']);
    final exposure = RW.asMap(m['positioning_exposure']);
    final sleep = RW.asMap(m['sleep_loading']);
    final temporal = RW.asMap(m['temporal_aggravation_patterns']);
    final contextFactors = RW.asStrList(m['user_context_factors']);
    final balance = RW.asMap(m['load_recovery_balance']);
    final functional = RW.str(m, 'functional_summary');

    final blocks = <Widget>[];

    // Positioning Exposure.
    blocks.add(RW.callout(
      bg: HydraReport.cream,
      border: HydraReport.tanLight.withValues(alpha: 0.4),
      label: 'Positioning Exposure',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (RW.str(exposure, 'primary_activity').isNotEmpty)
            RW.kv('Primary Activity', RW.str(exposure, 'primary_activity')),
          if (RW.str(exposure, 'estimated_daily_hours').isNotEmpty)
            RW.kv('Daily Hours',
                '${RW.str(exposure, 'estimated_daily_hours')}h'),
          const SizedBox(height: 6),
          _tissueBoxes(
            RW.asStrList(exposure['tissues_chronically_shortened']),
            RW.asStrList(exposure['tissues_chronically_lengthened']),
          ),
        ],
      ),
    ));

    // Sleep Loading (purple).
    if (RW.str(sleep, 'position').isNotEmpty) {
      final effect = RW.str(sleep, 'effect_on_pattern');
      blocks.add(RW.callout(
        bg: HydraReport.purple50,
        border: HydraReport.purple100,
        label: 'Sleep Loading',
        labelColor: HydraReport.purple700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RW.kv('Position', RW.str(sleep, 'position')),
            if (effect.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Text('Effect: ',
                        style: TextStyle(
                            color: HydraReport.darkTeal,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                    RW.miniBadge(effect,
                        bg: effect == 'reinforces'
                            ? HydraReport.red100
                            : HydraReport.green100,
                        fg: effect == 'reinforces'
                            ? HydraReport.red600
                            : HydraReport.green600),
                  ],
                ),
              ),
            if (RW.str(sleep, 'tissue_impact').isNotEmpty)
              RW.kv('Impact', RW.str(sleep, 'tissue_impact')),
          ],
        ),
      ));
    }

    // Temporal Aggravation Patterns.
    final morning = RW.str(temporal, 'morning');
    final endOfDay = RW.str(temporal, 'end_of_day');
    final exercise = RW.str(temporal, 'during_after_exercise');
    if (morning.isNotEmpty || endOfDay.isNotEmpty || exercise.isNotEmpty) {
      blocks.add(_sub(
        'Temporal Aggravation Patterns',
        RW.grid([
          if (morning.isNotEmpty)
            RW.callout(
                bg: HydraReport.yellow50,
                border: HydraReport.yellow100,
                label: 'Morning',
                labelColor: HydraReport.yellow600,
                child: Text(morning,
                    style: const TextStyle(
                        color: HydraReport.yellow900, fontSize: 12))),
          if (endOfDay.isNotEmpty)
            RW.callout(
                bg: HydraReport.orange50,
                border: HydraReport.orange100,
                label: 'End of Day',
                labelColor: HydraReport.orange600,
                child: Text(endOfDay,
                    style: const TextStyle(
                        color: HydraReport.orange900, fontSize: 12))),
          if (exercise.isNotEmpty)
            RW.callout(
                bg: HydraReport.red50,
                border: HydraReport.red100,
                label: 'During / After Exercise',
                labelColor: HydraReport.red500,
                child: Text(exercise,
                    style: const TextStyle(
                        color: HydraReport.red900, fontSize: 12))),
        ], cols: 3),
      ));
    }

    // User Context Factors.
    if (contextFactors.isNotEmpty) {
      blocks.add(_sub('User Context Factors',
          Column(children: [for (final f in contextFactors) RW.bulletCard(f)])));
    }

    // Load / Recovery Balance.
    if (balance.isNotEmpty && RW.has(balance)) {
      final status = RW.str(balance, 'recovery_status');
      blocks.add(RW.callout(
        bg: HydraReport.darkTeal.withValues(alpha: 0.05),
        border: HydraReport.darkTeal.withValues(alpha: 0.2),
        borderWidth: 1.5,
        label: 'Load / Recovery Balance',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (RW.str(balance, 'daily_load_hours').isNotEmpty)
              RW.kv('Daily Load', '${RW.str(balance, 'daily_load_hours')}h'),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Text('Status: ',
                        style: TextStyle(
                            color: HydraReport.darkTeal,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                    RW.miniBadge(RW.unslug(status),
                        bg: status == 'severely_imbalanced'
                            ? HydraReport.red100
                            : status == 'moderately_imbalanced'
                                ? HydraReport.yellow100
                                : HydraReport.green100,
                        fg: status == 'severely_imbalanced'
                            ? HydraReport.red600
                            : status == 'moderately_imbalanced'
                                ? HydraReport.yellow700
                                : HydraReport.green600),
                  ],
                ),
              ),
            if (RW.str(balance, 'critical_recovery_gap').isNotEmpty)
              RW.kv('Critical Gap', RW.str(balance, 'critical_recovery_gap')),
          ],
        ),
      ));
    }

    // Functional Summary.
    if (functional.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Functional Summary',
        child: RW.paragraph(functional),
      ));
    }

    return RW.section(
      icon: Icons.monitor_heart_rounded,
      title: 'Load vs Recovery Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }
}

/// A positioning card (web shared `PositioningCard`).
Widget _positioningCard(String title, Map<String, dynamic> data,
    {required bool primary}) {
  return RW.callout(
    bg: primary ? HydraReport.cream : HydraReport.gray50,
    border: primary
        ? HydraReport.tanLight.withValues(alpha: 0.4)
        : HydraReport.gray100,
    label: title,
    labelColor: primary ? HydraReport.tanDark : HydraReport.muted,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (RW.str(data, 'activity').isNotEmpty)
          RW.kv('Activity', RW.str(data, 'activity')),
        if (RW.str(data, 'position_held').isNotEmpty)
          RW.kv('Position', RW.str(data, 'position_held')),
        if (RW.str(data, 'estimated_duration').isNotEmpty)
          RW.kv('Duration', RW.str(data, 'estimated_duration')),
        const SizedBox(height: 6),
        _tissueBoxes(
          RW.asStrList(data['tissues_shortened']),
          RW.asStrList(data['tissues_lengthened']),
        ),
        if (RW.str(data, 'mechanical_consequence').isNotEmpty) ...[
          const SizedBox(height: 6),
          RW.paragraph(RW.str(data, 'mechanical_consequence'), size: 12.5),
        ],
      ],
    ),
  );
}

/// Lifestyle Contributors (web `UserReport` section 6).
class LifestyleSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const LifestyleSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['lifestyle_contributors']);
    final primary = RW.asMap(m['primary_positioning']);
    final secondary = RW.asMap(m['secondary_positioning']);
    final sleep = RW.asMap(m['sleep_position_influence']);
    final asym = RW.asMap(m['asymmetric_loading_factors']);
    final loop = RW.str(m, 'reinforcement_loop_summary');

    final blocks = <Widget>[];

    if (RW.str(primary, 'activity').isNotEmpty) {
      blocks.add(_positioningCard('Primary Positioning', primary,
          primary: true));
    }
    if (RW.str(secondary, 'activity').isNotEmpty) {
      blocks.add(_positioningCard('Secondary Positioning', secondary,
          primary: false));
    }

    if (RW.str(sleep, 'position').isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.purple50,
        border: HydraReport.purple100,
        label: 'Sleep Position Influence',
        labelColor: HydraReport.purple700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RW.kv('Position', RW.str(sleep, 'position')),
            if (RW.str(sleep, 'effect').isNotEmpty)
              RW.kv('Effect', RW.str(sleep, 'effect')),
            if (RW.str(sleep, 'asymmetry_contribution').isNotEmpty)
              RW.kv('Asymmetry Contribution',
                  RW.str(sleep, 'asymmetry_contribution')),
          ],
        ),
      ));
    }

    final contributors = RW.asStrList(asym['user_insight_contributors']);
    if (RW.str(asym, 'clinical_laterality').isNotEmpty ||
        contributors.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.darkTeal.withValues(alpha: 0.05),
        border: HydraReport.darkTeal.withValues(alpha: 0.1),
        label: 'Asymmetric Loading Factors',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (RW.str(asym, 'clinical_laterality').isNotEmpty)
              RW.kv('Clinical Laterality',
                  RW.str(asym, 'clinical_laterality')),
            if (RW.str(asym, 'sleep_preference').isNotEmpty)
              RW.kv('Sleep Preference', RW.str(asym, 'sleep_preference')),
            if (contributors.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('USER INSIGHT CONTRIBUTORS',
                  style: TextStyle(
                      color: HydraReport.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              for (final c in contributors)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                            color: HydraReport.darkTeal,
                            shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(c,
                            style: const TextStyle(
                                color: HydraReport.darkTeal, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ));
    }

    if (loop.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Reinforcement Loop Summary',
        child: RW.paragraph(loop),
      ));
    }

    return RW.section(
      icon: Icons.favorite_rounded,
      title: 'Lifestyle Contributors',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }
}
