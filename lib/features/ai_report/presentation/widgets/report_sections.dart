import 'package:flutter/widgets.dart';

import '../ai_report_style.dart';
import 'report_widgets.dart';
import 'sections/at_home_section.dart';
import 'sections/client_summary_sections.dart';
import 'sections/closing_sections.dart';
import 'sections/load_lifestyle_sections.dart';
import 'sections/pattern_sections.dart';

/// The "Your Report" (client) section widgets in web order, gated on content.
/// Shared by the on-screen report and the image-based PDF so both render the
/// exact same widgets.
List<Widget> clientReportSections(Map<String, dynamic> data) {
  bool has(String key) => HydraReport.hasContent(data[key]);
  return [
    if (has('personal_snapshot')) PersonalSnapshotSection(data),
    if (has('clinical_insight_snapshot')) ClinicalInsightSection(data),
    if (has('movement_mobility_summary')) MovementMobilitySection(data),
    if (has('kinetic_chain_pattern_a')) PatternFullSection(data, 'a'),
    if (has('kinetic_chain_pattern_b')) PatternFullSection(data, 'b'),
    if (has('load_vs_recovery_profile')) LoadRecoverySection(data),
    if (has('lifestyle_contributors')) LifestyleSection(data),
    if (has('at_home_mobility_support')) AtHomeSupportSection(data),
    if (has('why_this_pattern_matters')) WhyMattersSection(data),
    if (has('practitioner_questions')) PractitionerQuestionsSection(data),
    if (has('next_steps')) NextStepsSection(data),
    // Unknown extra keys still render so nothing is dropped.
    for (final e in HydraReport.extraSections(data))
      GenericSection(HydraReport.humanize(e.key), e.value),
    if (has('disclaimer')) DisclaimerSection(data),
  ];
}

/// The practitioner sections AFTER pad placement (which differs live vs. PDF).
/// Prefix with `PadPlacementSection` (live) or `PadPlacementStatic` (PDF).
List<Widget> practitionerTailSections(Map<String, dynamic> data) {
  bool has(String key) => HydraReport.hasContent(data[key]);
  return [
    if (has('practitioner_hand_off')) PractitionerHandoffSection(data),
    if (has('kinetic_chain_pattern_a')) PatternCompactSection(data, 'a'),
    if (has('kinetic_chain_pattern_b')) PatternCompactSection(data, 'b'),
    if (has('practitioner_notes_template')) PractitionerNotesSection(data),
    if (has('disclaimer')) DisclaimerSection(data),
  ];
}
