import 'package:flutter/material.dart';

/// Hydra brand palette + report section metadata, shared by the on-screen
/// report (`ai_report_screen.dart`) and the downloadable PDF (`ai_report_pdf.dart`)
/// so both look the same (web parity with `analysis-display.tsx`).
class HydraReport {
  HydraReport._();

  // Brand colors (from web globals.css).
  static const darkTeal = Color(0xFF132A35);
  static const teal = Color(0xFF233D47);
  static const tanDark = Color(0xFFC59D84);
  static const tanLight = Color(0xFFDDBEA8);
  static const cream = Color(0xFFF9F5F1);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280); // gray-500

  // Callout tones.
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red800 = Color(0xFF991B1B);
  static const red900 = Color(0xFF7F1D1D);
  static const green50 = Color(0xFFF0FDF4);
  static const green100 = Color(0xFFDCFCE7);
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF16A34A);
  static const green800 = Color(0xFF166534);
  static const green900 = Color(0xFF14532D);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue500 = Color(0xFF3B82F6);
  static const blue800 = Color(0xFF1E40AF);
  static const blue900 = Color(0xFF1E3A8A);
  static const yellow50 = Color(0xFFFEFCE8);
  static const yellow100 = Color(0xFFFEF9C3);
  static const yellow600 = Color(0xFFCA8A04);
  static const yellow700 = Color(0xFFA16207);
  static const yellow900 = Color(0xFF713F12);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange600 = Color(0xFFEA580C);
  static const orange900 = Color(0xFF7C2D12);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple500 = Color(0xFFA855F7);
  static const purple700 = Color(0xFF7E22CE);
  static const purple800 = Color(0xFF6B21A8);
  // Grays (web gray-50/100/400/700).
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray700 = Color(0xFF374151);

  /// Sections in render order: key, title, icon, and whether it's
  /// practitioner-only (hidden on the "Your Report" tab).
  static const List<ReportSection> sections = [
    ReportSection('personal_snapshot', 'Personal Snapshot', Icons.person_rounded),
    ReportSection('clinical_insight_snapshot', 'Clinical Insight',
        Icons.insights_rounded,
        tone: SectionTone.cream),
    ReportSection('movement_mobility_summary', 'Movement & Mobility',
        Icons.directions_run_rounded),
    ReportSection('kinetic_chain_pattern_a', 'Kinetic Chain — Pattern A',
        Icons.timeline_rounded),
    ReportSection('kinetic_chain_pattern_b', 'Kinetic Chain — Pattern B',
        Icons.balance_rounded),
    ReportSection('load_vs_recovery_profile', 'Load vs Recovery',
        Icons.monitor_heart_rounded),
    ReportSection('lifestyle_contributors', 'Lifestyle Contributors',
        Icons.favorite_rounded),
    ReportSection('at_home_mobility_support', 'At-Home Mobility Support',
        Icons.lightbulb_rounded),
    ReportSection('why_this_pattern_matters', 'Why This Pattern Matters',
        Icons.warning_amber_rounded,
        tone: SectionTone.cream),
    ReportSection('practitioner_questions', 'Questions for Your Practitioner',
        Icons.help_outline_rounded),
    ReportSection('practitioner_hand_off', 'Practitioner Hand-off',
        Icons.assignment_turned_in_rounded,
        practitionerOnly: true),
    ReportSection('practitioner_notes_template', 'Practitioner Notes',
        Icons.description_rounded,
        practitionerOnly: true),
    ReportSection('next_steps', 'Next Steps', Icons.arrow_forward_rounded),
    ReportSection('disclaimer', 'Disclaimer', Icons.info_outline_rounded,
        tone: SectionTone.gray),
  ];

  /// Metadata keys that are NOT report content (hidden from the rendered report).
  static const Set<String> metaKeys = {
    '_id', 'id', '__v', 'userId', 'user_id', 'clientId', 'client_id',
    'organizationId', 'organization_id', 'createdBy', 'updatedBy', 'createdAt',
    'updatedAt', 'created_at', 'updated_at', 'intakeId', 'intake_id',
    'intakeData', 'intake_data', 'aiProvider', 'ai_provider', 'aiModel',
    'ai_model', 'schema_version', 'report_type', 'guestMode', 'guest_mode',
    'sessionId', 'session_id', 'requestId', 'request_id', 'status', 'provider',
    'model', 'prompt', 'promptVersion', 'prompt_version', 'clientName',
    'practitionerId', 'name', 'role', 'error', 'message',
  };

  /// Some API responses wrap the report under `report`/`result`/`data`/etc.
  /// Unwrap until we reach the object that actually holds the section keys.
  static Map<String, dynamic> normalize(Map input) {
    var m = Map<String, dynamic>.from(input);
    const wrappers = [
      'report', 'result', 'data', 'analysis', 'output', 'aiReport',
      'ai_report', 'analysisResult', 'analysis_result',
    ];
    for (var i = 0; i < 5; i++) {
      final hasSection = sections.any((s) => m.containsKey(s.key));
      if (hasSection) break;
      Map? next;
      for (final w in wrappers) {
        if (m[w] is Map) {
          next = m[w] as Map;
          break;
        }
      }
      if (next == null) break;
      m = Map<String, dynamic>.from(next);
    }
    return m;
  }

  /// Content keys present in [m] that aren't known sections or metadata — so any
  /// extra fields the API returns still render instead of being dropped.
  static List<MapEntry<String, dynamic>> extraSections(Map<String, dynamic> m) {
    final known = sections.map((s) => s.key).toSet();
    return m.entries
        .where((e) =>
            !known.contains(e.key) &&
            !metaKeys.contains(e.key) &&
            hasContent(e.value))
        .toList();
  }

  static String humanize(String key) {
    final s = key.replaceAll('_', ' ').trim();
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static bool hasContent(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  /// A colored callout tone for known field keys (critical → red, supporting →
  /// green, etc.), else the default cream tone.
  static CalloutTone toneForKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('critical') ||
        k.contains('contradicting') ||
        k.contains('shortened') ||
        k.contains('worsen')) {
      return const CalloutTone(red50, red100, red900, red500);
    }
    if (k.contains('supporting') ||
        k.contains('plausible') ||
        k.contains('improv') ||
        k.contains('relief') ||
        k.contains('recommended')) {
      return const CalloutTone(green50, green100, green900, green600);
    }
    if (k.contains('important') || k.contains('aggravat') || k.contains('warn')) {
      return const CalloutTone(yellow50, yellow100, ink, yellow700);
    }
    if (k.contains('lengthened') || k.contains('dermatome')) {
      return const CalloutTone(blue50, blue100, blue800, blue800);
    }
    if (k.contains('segment') || k.contains('spinal') || k.contains('sleep')) {
      return const CalloutTone(purple50, purple100, purple700, purple700);
    }
    return const CalloutTone(cream, tanLight, darkTeal, tanDark);
  }
}

enum SectionTone { white, cream, gray }

class ReportSection {
  final String key;
  final String title;
  final IconData icon;
  final SectionTone tone;
  final bool practitionerOnly;
  const ReportSection(this.key, this.title, this.icon,
      {this.tone = SectionTone.white, this.practitionerOnly = false});
}

/// bg, border, text, accent (label) colors for a callout.
class CalloutTone {
  final Color bg;
  final Color border;
  final Color text;
  final Color accent;
  const CalloutTone(this.bg, this.border, this.text, this.accent);
}
