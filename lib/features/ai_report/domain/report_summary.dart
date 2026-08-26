/// Every content decision for the six-section report, in one place.
///
/// WHY THIS FILE EXISTS. The report is rendered twice — once as widgets
/// (`report_spec_sections.dart`) and once as a PDF (`ai_report_pdf.dart`, which
/// hand-builds `pw.Widget`s and cannot share a widget tree). Without a shared
/// layer, "which key feeds section IV", "what grade is 63" and "what do we show
/// when `functional_summary` is empty" would be answered twice and drift.
///
/// A shared *render* abstraction over `Widget` and `pw.Widget` was considered
/// and rejected: `pw`'s `MultiPage` layout model is genuinely different, and at
/// this size the indirection costs more than it saves. So rendering stays split
/// and only the CONTENT decisions are shared — those are the ones that drift
/// invisibly.
///
/// Deliberately pure Dart: no Flutter import, so it is trivially unit-testable
/// and safe to call from the data layer where the PDF is built.
library;

// ---------------------------------------------------------------------------
// Loose accessors
//
// The report is an untyped `Map<String, dynamic>` end to end — the backend's
// shape varies by model and prompt version, so every read is defensive. A
// missing or wrong-typed key yields empty, never an exception: a partial report
// must still render.
// ---------------------------------------------------------------------------

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

String _str(Object? v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  // Some fields arrive as `{explanation: "..."}` rather than a bare string.
  if (v is Map) {
    for (final k in const ['explanation', 'text', 'summary', 'value']) {
      final s = v[k];
      if (s is String && s.trim().isNotEmpty) return s.trim();
    }
    return '';
  }
  return v.toString().trim();
}

List<String> _strList(Object? v) {
  if (v is! List) return const [];
  return v.map(_str).where((e) => e.isNotEmpty).toList();
}

List<Map<String, dynamic>> _mapList(Object? v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// First non-empty of [candidates] — the fallback chains below are all shaped
/// like this, and writing them as a list keeps the priority order readable.
String _firstNonEmpty(List<String> candidates) {
  for (final c in candidates) {
    if (c.isNotEmpty) return c;
  }
  return '';
}

// ---------------------------------------------------------------------------
// II · Kinetic chain scores and grades
// ---------------------------------------------------------------------------

/// A pattern row in section II.
///
/// [score] and [grade] are null together when the model reported no confidence.
/// That is rendered as `—`; a grade is never invented from nothing.
class PatternRow {
  /// 'a' or 'b'.
  final String key;
  final String label;
  final int? score;
  final String? grade;

  /// Pattern A is the primary hypothesis; B is the alternative to watch.
  bool get isPrimary => key == 'a';

  const PatternRow({
    required this.key,
    required this.label,
    this.score,
    this.grade,
  });

  /// `72 / 100 · primary pattern` — the spec's sub-line, or an honest
  /// substitute when confidence is missing.
  String get subline {
    final tail = isPrimary ? 'primary pattern' : 'watch pattern';
    if (score == null) return 'Confidence not reported · $tail';
    return '$score / 100 · $tail';
  }

  /// `Pattern A · Hip drive chain`, with `(alternative)` on B per the spec.
  String get title {
    final name = label.isEmpty ? 'Kinetic chain' : label;
    return isPrimary
        ? 'Pattern A · $name'
        : 'Pattern B · $name (alternative)';
  }
}

/// Confidence as a 0–100 integer, or null when absent.
///
/// Models emit confidence both as a fraction (`0.72`) and as a percentage
/// (`72`), so anything at or below 1 is treated as a fraction. That makes a
/// genuine 1% confidence unreachable — an acceptable trade, since 1% and 100%
/// are not meaningfully different inputs here and the fraction form is common.
int? reportScore(Map<String, dynamic> report, String patternKey) {
  final pattern = _map(report['kinetic_chain_pattern_$patternKey']);
  final raw = _map(pattern['confidence'])['level'];
  final num? level = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  if (level == null) return null;
  final pct = level <= 1 ? level * 100 : level;
  return pct.round().clamp(0, 100);
}

/// Letter grade for a 0–100 score.
///
/// The ladder is anchored on the UI spec's own seeded report — `{score: 72,
/// grade: 'B'}` and `{score: 61, grade: 'B−'}` (app.js:2758). That seed is the
/// only ground truth available; the spec's `wizGenerate` heuristic contradicts
/// it, so the seed wins. Both anchors land exactly on the bands below.
///
/// Note the minus is U+2212 (−), matching the spec, not an ASCII hyphen.
String? reportGrade(int? score) {
  if (score == null) return null;
  if (score >= 90) return 'A';
  if (score >= 85) return 'A−';
  if (score >= 80) return 'B+';
  if (score >= 70) return 'B';
  if (score >= 60) return 'B−';
  if (score >= 50) return 'C+';
  if (score >= 40) return 'C';
  return 'D';
}

/// The rows for section II. Returns only the patterns that carry data, so a
/// report with no Pattern B renders one row rather than an empty placeholder.
List<PatternRow> patternRows(Map<String, dynamic> report) {
  final rows = <PatternRow>[];
  for (final key in const ['a', 'b']) {
    final pattern = _map(report['kinetic_chain_pattern_$key']);
    if (pattern.isEmpty) continue;
    final score = reportScore(report, key);
    rows.add(PatternRow(
      key: key,
      label: _str(pattern['pattern_label']),
      score: score,
      grade: reportGrade(score),
    ));
  }
  return rows;
}

/// The `why_this_pattern_matters` callout under the two rows. The spec has no
/// home for this field, but it is the one that explains the section.
String whyPatternMatters(Map<String, dynamic> report) =>
    _str(report['why_this_pattern_matters']);

// ---------------------------------------------------------------------------
// I · Client summary
// ---------------------------------------------------------------------------

/// The opening paragraph. Falls back through progressively weaker sources so
/// the section is never empty on a partial report.
String clientSummaryProse(Map<String, dynamic> report) {
  final clinical = _map(report['clinical_insight_snapshot']);
  final personal = _map(report['personal_snapshot']);
  final movement = _map(report['movement_mobility_summary']);

  final composed = () {
    final primary = _str(personal['primary_concern']);
    if (primary.isEmpty) return '';
    final secondary = _strList(personal['secondary_concerns']);
    if (secondary.isEmpty) return primary;
    return '$primary Also reported: ${secondary.join(', ')}.';
  }();

  return _firstNonEmpty([
    _str(clinical['summary_statement']),
    composed,
    _str(movement['user_insight_integration']),
  ]);
}

/// The three chips under the summary. These are the rest of
/// `clinical_insight_snapshot` — dropping them would lose real analysis, and
/// they read well as chips.
List<String> clientSummaryChips(Map<String, dynamic> report) {
  final clinical = _map(report['clinical_insight_snapshot']);
  return [
    _str(clinical['primary_movement_bias']),
    _str(clinical['dominant_kinetic_chain']),
    _str(clinical['primary_symptom_region']),
  ].where((e) => e.isNotEmpty).toList();
}

// ---------------------------------------------------------------------------
// IV · Load & lifestyle
// ---------------------------------------------------------------------------

/// One or two paragraphs. The spec's section IV is a single static paragraph;
/// the real data has two natural ones (how load accumulates, and the loop that
/// reinforces it), so both are returned and the caller spaces them.
List<String> loadLifestyleProse(Map<String, dynamic> report) {
  final load = _map(report['load_vs_recovery_profile']);
  final lifestyle = _map(report['lifestyle_contributors']);

  final paragraphs = <String>[
    _str(load['functional_summary']),
    _str(lifestyle['reinforcement_loop_summary']),
  ].where((e) => e.isNotEmpty).toList();

  if (paragraphs.isNotEmpty) return paragraphs;

  // Nothing summarised — compose from the temporal pattern, which is the most
  // concrete thing left.
  final temporal = _map(load['temporal_aggravation_patterns']);
  final parts = <String>[
    if (_str(temporal['morning']).isNotEmpty)
      'Mornings: ${_str(temporal['morning'])}',
    if (_str(temporal['end_of_day']).isNotEmpty)
      'End of day: ${_str(temporal['end_of_day'])}',
    if (_str(temporal['during_after_exercise']).isNotEmpty)
      'Around exercise: ${_str(temporal['during_after_exercise'])}',
  ];
  return parts.isEmpty ? const [] : [parts.join(' · ')];
}

/// Context chips for section IV.
List<String> loadLifestyleChips(Map<String, dynamic> report) =>
    _strList(_map(report['load_vs_recovery_profile'])['user_context_factors']);

// ---------------------------------------------------------------------------
// V · At-home mobility support
// ---------------------------------------------------------------------------

/// One exercise row.
class ExerciseRow {
  final String name;
  final String addresses;
  final String frequency;
  final String durationReps;
  final List<String> procedure;
  final String importantNotes;

  const ExerciseRow({
    required this.name,
    this.addresses = '',
    this.frequency = '',
    this.durationReps = '',
    this.procedure = const [],
    this.importantNotes = '',
  });

  /// The micro line under the exercise name.
  ///
  /// DELIBERATE SPEC DEVIATION: the spec shows `{duration} · video`. There are
  /// no exercise videos in this app and none are planned, so printing "video"
  /// would promise something that does not exist. We show the real prescription
  /// instead, which is more useful anyway.
  String get micro {
    final parts = [durationReps, frequency].where((e) => e.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' · ');
    return addresses;
  }

  /// Stable identity for the done-toggle store.
  ///
  /// Slugified NAME, not list index: a re-fetched report keeps exercise names
  /// but the model may reorder them, and an index key would silently mark the
  /// wrong exercise done.
  String get slug => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  bool get hasDetail => procedure.isNotEmpty || importantNotes.isNotEmpty;
}

List<ExerciseRow> exerciseRows(Map<String, dynamic> report) {
  final section = _map(report['at_home_mobility_support']);
  return _mapList(section['exercises'])
      .map((e) => ExerciseRow(
            name: _str(e['name']),
            addresses: _str(e['addresses']),
            frequency: _str(e['frequency']),
            durationReps: _str(e['duration_reps']),
            procedure: _strList(e['procedure']),
            importantNotes: _str(e['important_notes']),
          ))
      .where((e) => e.name.isNotEmpty)
      .toList();
}

/// The "Why these exercises" content, shown in section V's own expander.
Map<String, dynamic> atHomeContext(Map<String, dynamic> report) {
  final section = _map(report['at_home_mobility_support']);
  return {
    'selection_rationale': _str(section['selection_rationale']),
    'relief_based_mapping': _strList(section['relief_based_mapping']),
    'daily_integration_guidance': _str(section['daily_integration_guidance']),
    'functional_goal': _str(section['functional_goal']),
  };
}

// ---------------------------------------------------------------------------
// VI · Practitioner notes & hand-off
// ---------------------------------------------------------------------------

/// The `Notes:` paragraph. Falls back to flattening the notes template when the
/// model returned no prose hand-off.
String handoffNotes(Map<String, dynamic> report) {
  final direct = _str(report['practitioner_hand_off']);
  if (direct.isNotEmpty) return direct;

  final template = _map(report['practitioner_notes_template']);
  return _firstNonEmpty([
    _str(template['follow_up']),
    _str(template['response_tracking']),
    _str(template['user_insights_modifications']),
  ]);
}

/// The `Questions for your practitioner:` list.
///
/// The spec renders these as prose; a list is strictly easier to read and to
/// act on, and still fits inside the card.
List<String> practitionerQuestions(Map<String, dynamic> report) =>
    _strList(report['practitioner_questions']);

/// `next_steps` has no home in the spec's six sections. Rather than drop real
/// recommendations, they become two chip groups at the foot of VI.
({List<String> focusAreas, List<String> modalities}) nextStepsChips(
  Map<String, dynamic> report,
) {
  final next = _map(report['next_steps']);
  return (
    focusAreas: _strList(next['recommended_focus_areas']),
    modalities: _strList(next['supportive_modalities']),
  );
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

/// The spec's exact disclaimer, used when the backend sent none.
const String kDefaultDisclaimer =
    'Wellness guidance only: supports recovery and mobility; not medical advice.';

String disclaimerText(Map<String, dynamic> report) {
  final fromReport = _str(report['disclaimer']);
  return fromReport.isEmpty ? kDefaultDisclaimer : fromReport;
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// `{Client} · {yyyy-MM-dd}` for the back bar, from whatever the report carries.
/// Returns an empty string when neither is known, so the caller can omit the
/// subtitle rather than render a stray separator.
String reportSubtitle(Map<String, dynamic> raw, {String? clientName}) {
  final name = (clientName ?? _str(raw['clientName'])).trim();
  final created = _str(raw['createdAt'] ?? raw['created_at']);
  final day = created.length >= 10 ? created.substring(0, 10) : '';
  return [name, day].where((e) => e.isNotEmpty).join(' · ');
}

/// Identity for per-report local state (the exercise done-toggles).
///
/// Reads the RAW map, before `HydraReport.normalize()` strips metadata. Returns
/// empty when the report has no server id yet — a freshly generated, not-yet
/// persisted report — and the caller keeps its toggles in memory for the
/// session rather than writing them under a key that will change.
String reportIdOf(Map<String, dynamic> raw) =>
    _firstNonEmpty([_str(raw['_id']), _str(raw['id'])]);
