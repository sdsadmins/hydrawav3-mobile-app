import 'package:flutter/material.dart';

import '../../ai_report_style.dart';
import '../report_widgets.dart';

/// Why This Pattern Matters (web `UserReport` section 8). Accepts a string or
/// an object with `.explanation`.
class WhyMattersSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const WhyMattersSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = report['why_this_pattern_matters'];
    final text = v is String
        ? v
        : v is Map
            ? (v['explanation'] ?? '').toString()
            : '';
    return RW.section(
      icon: Icons.warning_amber_rounded,
      title: 'Why This Pattern Matters',
      background: HydraReport.cream,
      child: RW.paragraph(text),
    );
  }
}

/// Questions for Your Practitioner (web `UserReport` section 9) — numbered
/// cream cards.
class PractitionerQuestionsSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const PractitionerQuestionsSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final questions = RW.asStrList(report['practitioner_questions']);
    return RW.section(
      icon: Icons.help_outline_rounded,
      title: 'Questions for Your Practitioner',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < questions.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HydraReport.cream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: HydraReport.tanLight.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: HydraReport.darkTeal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: RW.paragraph(questions[i])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Next Steps (web `UserReport` section 12).
class NextStepsSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const NextStepsSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['next_steps']);
    final focus = RW.asStrList(m['recommended_focus_areas']);
    final modalities = RW.asStrList(m['supportive_modalities']);
    return RW.section(
      icon: Icons.arrow_forward_rounded,
      title: 'Next Steps',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (focus.isNotEmpty) ...[
            RW.subLabel('Recommended Focus Areas'),
            RW.chipWrap(focus,
                bg: HydraReport.green50,
                border: HydraReport.green100,
                fg: HydraReport.green800),
            const SizedBox(height: 16),
          ],
          if (modalities.isNotEmpty) ...[
            RW.subLabel('Supportive Modalities'),
            for (final mod in modalities) RW.bulletCard(mod),
          ],
        ],
      ),
    );
  }
}

/// Practitioner Hand-Off (web `PractitionerReport`) — single paragraph.
class PractitionerHandoffSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const PractitionerHandoffSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    return RW.section(
      icon: Icons.assignment_turned_in_rounded,
      title: 'Practitioner Hand-Off',
      child: RW.paragraph(RW.str(report, 'practitioner_hand_off')),
    );
  }
}

/// Practitioner Notes Template (web `PractitionerReport` section 11).
class PractitionerNotesSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const PractitionerNotesSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = RW.asMap(report['practitioner_notes_template']);
    final manual = RW.asStrList(m['manual_assessment_areas']);
    final quality = RW.asStrList(m['movement_quality_checks']);
    final retests = RW.asStrList(m['retests']);
    final placeholder = RW.str(m, 'session_notes_placeholder');
    final tracking = RW.str(m, 'response_tracking');
    final insights = RW.str(m, 'user_insights_modifications');
    final followUp = RW.str(m, 'follow_up');

    final blocks = <Widget>[];

    if (manual.isNotEmpty) {
      blocks.add(_block(
        'Manual Assessment Areas',
        Column(children: [
          for (final a in manual)
            RW.iconCard(Icons.gps_fixed_rounded, a,
                iconColor: HydraReport.tanDark,
                bg: HydraReport.cream,
                border: HydraReport.tanLight.withValues(alpha: 0.4)),
        ]),
      ));
    }
    if (quality.isNotEmpty) {
      blocks.add(_block(
        'Movement Quality Checks',
        Column(children: [
          for (final c in quality)
            RW.iconCard(Icons.check_circle_rounded, c,
                iconColor: HydraReport.darkTeal,
                bg: HydraReport.darkTeal.withValues(alpha: 0.05),
                border: HydraReport.darkTeal.withValues(alpha: 0.1)),
        ]),
      ));
    }
    if (retests.isNotEmpty) {
      blocks.add(_block(
        'Retests',
        Column(children: [
          for (final rt in retests)
            RW.iconCard(Icons.replay_rounded, rt,
                iconColor: HydraReport.purple500,
                bg: HydraReport.purple50,
                border: HydraReport.purple100),
        ]),
      ));
    }
    if (placeholder.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.gray50,
        border: HydraReport.gray100,
        label: 'Session Notes Placeholder',
        child: Text(placeholder,
            style: const TextStyle(
                color: HydraReport.muted,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4)),
      ));
    }
    if (tracking.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Response Tracking',
        child: RW.paragraph(tracking),
      ));
    }
    if (insights.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.darkTeal.withValues(alpha: 0.05),
        border: HydraReport.darkTeal.withValues(alpha: 0.1),
        label: 'User Insights & Modifications',
        child: RW.paragraph(insights),
      ));
    }
    if (followUp.isNotEmpty) {
      blocks.add(RW.callout(
        bg: HydraReport.cream,
        border: HydraReport.tanLight.withValues(alpha: 0.4),
        label: 'Follow-Up',
        child: RW.paragraph(followUp),
      ));
    }

    return RW.section(
      icon: Icons.description_rounded,
      title: 'Practitioner Notes Template',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
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
}

/// Disclaimer (both tabs) — small gray text.
class DisclaimerSection extends StatelessWidget {
  final Map<String, dynamic> report;
  const DisclaimerSection(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HydraReport.gray50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HydraReport.gray100),
      ),
      child: Text(RW.str(report, 'disclaimer'),
          style: const TextStyle(
              color: HydraReport.gray400, fontSize: 10.5, height: 1.5)),
    );
  }
}
