import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../performance_protocols/presentation/screens/pad_map_screen.dart'
    show kAnatomySetColors;
import '../../domain/kinetic_chain_payload.dart';
import '../../domain/report_summary.dart';
import '../ai_report_style.dart';
import 'report_expander.dart';
import 'sections/at_home_section.dart';
import 'sections/client_summary_sections.dart';
import 'sections/closing_sections.dart';
import 'sections/load_lifestyle_sections.dart';
import 'sections/pad_placement_section.dart';
import 'sections/pattern_sections.dart';
import 'report_widgets.dart' show GenericSection;

/// The report as the UI handoff spec draws it: six numbered sections (I–VI),
/// copper eyebrows, and the spec's own card rhythm — `openReport()`, app.js:2781.
///
/// The spec's report is a MOCK: six short sections, letter grades, four
/// hardcoded exercises. Ours is fed by a real AI response with ~15 detailed
/// sections. So each numbered section shows the spec's summary, and the real
/// clinical depth moves into a `ReportExpander` beneath it. Nothing the backend
/// produced is discarded — including keys we don't know about, which surface
/// under `VII. Additional findings`.
///
/// All content decisions (which key feeds which section, fallbacks, the grade
/// ladder) live in `domain/report_summary.dart` so the PDF renders from the
/// same source.
List<Widget> reportSpecSections(
  BuildContext context,
  Map<String, dynamic> data, {
  VoidCallback? onOpenPadMap,
}) {
  final extras = HydraReport.extraSections(data);
  return [
    _ClientSummary(data),
    _KineticChainMap(data),
    _PadPlacement(data, onOpenPadMap: onOpenPadMap),
    _LoadLifestyle(data),
    _AtHome(data),
    _PractitionerNotes(data),
    if (extras.isNotEmpty) _AdditionalFindings(extras),
  ];
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

/// One `.reportsec card` — an `HwCard` with the spec's numbered copper eyebrow.
class _Section extends StatelessWidget {
  final String eyebrow;
  final List<Widget> children;
  const _Section(this.eyebrow, this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HwEyebrow(eyebrow),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The spec's `.sub` body copy.
Widget _prose(BuildContext context, String text) {
  final p = RefPalette.of(context);
  return Text(
    text,
    style: TextStyle(fontSize: HwType.cap, height: 1.55, color: p.ink2),
  );
}

Widget _chips(List<String> values, {HwPillTone tone = HwPillTone.copper}) {
  if (values.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: HwSpace.s3),
    child: Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [for (final v in values) HwPill(v, tone: tone, maxLines: 2)],
    ),
  );
}

Widget _subLabel(BuildContext context, String text) {
  final p = RefPalette.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: HwSpace.s3, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: HwType.eyebrow,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: p.ink3,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// I · Client summary
// ---------------------------------------------------------------------------

class _ClientSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ClientSummary(this.data);

  @override
  Widget build(BuildContext context) {
    final prose = clientSummaryProse(data);
    return _Section('I. Client summary', [
      if (prose.isNotEmpty)
        _prose(context, prose)
      else
        _prose(context, 'No summary was returned for this assessment.'),
      _chips(clientSummaryChips(data)),
      ReportExpander(
        label: 'Show the full assessment detail',
        children: [
          if (HydraReport.hasContent(data['personal_snapshot']))
            PersonalSnapshotSection(data),
          if (HydraReport.hasContent(data['clinical_insight_snapshot']))
            ClinicalInsightSection(data),
          if (HydraReport.hasContent(data['movement_mobility_summary']))
            MovementMobilitySection(data),
        ],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// II · Structural kinetic chain map
// ---------------------------------------------------------------------------

class _KineticChainMap extends StatelessWidget {
  final Map<String, dynamic> data;
  const _KineticChainMap(this.data);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final rows = patternRows(data);
    if (rows.isEmpty) return const SizedBox.shrink();
    final why = whyPatternMatters(data);

    // Open whichever pattern actually has 3D data; A wins when both do.
    final chainKey = kineticChainPatternHasData(data, 'a')
        ? 'a'
        : kineticChainPatternHasData(data, 'b')
            ? 'b'
            : null;

    return _Section('II. Structural kinetic chain map', [
      for (final row in rows) _GradeRow(row),
      if (why.isNotEmpty) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.tanSoft,
            borderRadius: BorderRadius.circular(HwRadius.sm),
            border: Border.all(color: p.cardline),
          ),
          child: _prose(context, why),
        ),
      ],
      if (chainKey != null) ...[
        const SizedBox(height: HwSpace.s3),
        HwButton(
          label: 'View 3D Kinetic Chain',
          // Same navigation the in-section button already uses
          // (`pattern_sections.dart:93`), so both routes into the 3D viewer
          // build the payload identically.
          onTap: () => context.pushNamed(
            RouteNames.kineticChain3d,
            extra: {
              'patternLabel': 'Kinetic Chain Visualization - '
                  'Pattern ${chainKey.toUpperCase()}',
              'payload': buildKineticChainPayload(data, chainKey),
            },
          ),
        ),
      ],
      ReportExpander(
        label: 'Show the full pattern analysis',
        children: [
          for (final row in rows) PatternFullSection(data, row.key),
        ],
      ),
    ]);
  }
}

/// The spec's `.kchain` row: a 44×44 letter-grade tile, the pattern name, and
/// `{score} / 100 · primary pattern`.
class _GradeRow extends StatelessWidget {
  final PatternRow row;
  const _GradeRow(this.row);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    // Spec colours: Pattern A amber (`--mid`), Pattern B teal (`--info`).
    final fg = row.isPrimary ? p.mid : p.info;
    final bg = row.isPrimary ? p.midSoft : p.infoSoft;
    // No confidence reported → a dashed neutral tile. Never a made-up grade.
    final unknown = row.grade == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line2),
        borderRadius: BorderRadius.circular(HwRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: unknown ? p.chipBg : bg,
              borderRadius: BorderRadius.circular(13),
              border: unknown ? Border.all(color: p.line) : null,
            ),
            child: Text(
              row.grade ?? '—',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: unknown ? p.ink3 : fg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.subline,
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// III · Pad placement
// ---------------------------------------------------------------------------

class _PadPlacement extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onOpenPadMap;
  const _PadPlacement(this.data, {this.onOpenPadMap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final areas = padPlacementAreas(data);
    if (areas.isEmpty) return const SizedBox.shrink();

    return _Section('III. Pad placement', [
      for (var i = 0; i < areas.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  // Same palette the 3D stage and the pad map paint sets in, so
                  // a swatch here means the same set there.
                  color: kAnatomySetColors[i % kAnatomySetColors.length],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  areas[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 4),
      Text(
        '☀ Sun = right · ☾ Moon = left',
        style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
      ),
      if (onOpenPadMap != null) ...[
        const SizedBox(height: HwSpace.s3),
        HwButton(label: 'Open pad map', filled: false, onTap: onOpenPadMap),
      ],
      // The live per-area Sun/Moon placements, fetched from the treatment-plan
      // service — the real detail behind the swatches above.
      ReportExpander(
        label: 'Show the pad placements',
        children: [PadPlacementSection(data)],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// IV · Load & lifestyle
// ---------------------------------------------------------------------------

class _LoadLifestyle extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LoadLifestyle(this.data);

  @override
  Widget build(BuildContext context) {
    final paragraphs = loadLifestyleProse(data);
    final hasDetail = HydraReport.hasContent(data['load_vs_recovery_profile']) ||
        HydraReport.hasContent(data['lifestyle_contributors']);
    if (paragraphs.isEmpty && !hasDetail) return const SizedBox.shrink();

    return _Section('IV. Load & lifestyle', [
      for (var i = 0; i < paragraphs.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _prose(context, paragraphs[i]),
      ],
      _chips(loadLifestyleChips(data), tone: HwPillTone.info),
      ReportExpander(
        children: [
          if (HydraReport.hasContent(data['load_vs_recovery_profile']))
            LoadRecoverySection(data),
          if (HydraReport.hasContent(data['lifestyle_contributors']))
            LifestyleSection(data),
        ],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// V · At-home mobility support
// ---------------------------------------------------------------------------

class _AtHome extends StatefulWidget {
  final Map<String, dynamic> data;
  const _AtHome(this.data);

  @override
  State<_AtHome> createState() => _AtHomeState();
}

class _AtHomeState extends State<_AtHome> {
  /// Done-toggles, by exercise slug.
  ///
  /// Session-scoped for now — persisting them needs a stable report id, which a
  /// freshly generated report doesn't have until the backend row lands. Wiring
  /// that to SharedPreferences is a follow-up; losing a tick on app restart is
  /// better than writing it under a key that changes.
  final _done = <String>{};

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final rows = exerciseRows(widget.data);
    if (rows.isEmpty) return const SizedBox.shrink();

    return _Section('V. At-home mobility support', [
      for (final ex in rows) _ExerciseRow(
        row: ex,
        done: _done.contains(ex.slug),
        onToggle: () => setState(() {
          _done.contains(ex.slug) ? _done.remove(ex.slug) : _done.add(ex.slug);
        }),
      ),
      const SizedBox(height: 4),
      Text(
        '${_done.length}/${rows.length} done',
        style: TextStyle(
          fontSize: HwType.eyebrow,
          fontWeight: FontWeight.w700,
          color: p.ink3,
        ),
      ),
      ReportExpander(
        label: 'Why these exercises',
        children: [AtHomeSupportSection(widget.data)],
      ),
    ]);
  }
}

/// The spec's `.exrow`: gradient video placeholder, name, micro line, done tile.
class _ExerciseRow extends StatefulWidget {
  final ExerciseRow row;
  final bool done;
  final VoidCallback onToggle;
  const _ExerciseRow({
    required this.row,
    required this.done,
    required this.onToggle,
  });

  @override
  State<_ExerciseRow> createState() => _ExerciseRowState();
}

class _ExerciseRowState extends State<_ExerciseRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final ex = widget.row;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: ex.hasDetail ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  // Non-interactive on purpose: there are no exercise videos.
                  // It's the spec's shape without the spec's promise.
                  Container(
                    width: 64,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: p.heroGrad,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Color(0xFFF2E9E2), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                        if (ex.micro.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            ex.micro,
                            style: TextStyle(
                                fontSize: HwType.eyebrow, color: p.ink3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DoneToggle(done: widget.done, onTap: widget.onToggle),
                ],
              ),
            ),
          ),
          if (_open && ex.hasDetail)
            Padding(
              padding: const EdgeInsets.only(left: 76, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < ex.procedure.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.infoSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: p.info,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ex.procedure[i],
                              style: TextStyle(
                                fontSize: HwType.eyebrow,
                                height: 1.5,
                                color: p.ink2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (ex.importantNotes.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: p.midSoft,
                        borderRadius: BorderRadius.circular(HwRadius.xs),
                      ),
                      child: Text(
                        ex.importantNotes,
                        style: TextStyle(
                          fontSize: HwType.eyebrow,
                          height: 1.45,
                          color: p.ink2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The spec's `.done-t` — 26×26, r9, 2px border; green fill with a white check
/// when on.
class _DoneToggle extends StatelessWidget {
  final bool done;
  final VoidCallback onTap;
  const _DoneToggle({required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HwMotion.t2,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: done ? p.good : p.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: done ? p.good : p.line, width: 2),
        ),
        child: Icon(
          Icons.check_rounded,
          size: 15,
          color: done ? Colors.white : Colors.transparent,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VI · Practitioner notes & hand-off
// ---------------------------------------------------------------------------

class _PractitionerNotes extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PractitionerNotes(this.data);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final notes = handoffNotes(data);
    final questions = practitionerQuestions(data);
    final next = nextStepsChips(data);
    final hasDetail =
        HydraReport.hasContent(data['practitioner_notes_template']);

    if (notes.isEmpty &&
        questions.isEmpty &&
        next.focusAreas.isEmpty &&
        next.modalities.isEmpty &&
        !hasDetail) {
      return const SizedBox.shrink();
    }

    return _Section('VI. Practitioner notes & hand-off', [
      if (notes.isNotEmpty) ...[
        Text(
          'Notes:',
          style: TextStyle(
            fontSize: HwType.cap,
            fontWeight: FontWeight.w800,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 4),
        _prose(context, notes),
      ],
      if (questions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Questions for your practitioner:',
          style: TextStyle(
            fontSize: HwType.cap,
            fontWeight: FontWeight.w800,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 6),
        for (final q in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: p.copper,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: _prose(context, q)),
              ],
            ),
          ),
      ],
      // `next_steps` has no home in the spec's six sections — but it's real
      // guidance, so it lands here rather than being dropped.
      if (next.focusAreas.isNotEmpty) ...[
        _subLabel(context, 'Recommended focus areas'),
        _chips(next.focusAreas, tone: HwPillTone.good),
      ],
      if (next.modalities.isNotEmpty) ...[
        _subLabel(context, 'Supportive modalities'),
        _chips(next.modalities),
      ],
      if (hasDetail)
        ReportExpander(
          label: 'Show the full practitioner notes',
          children: [PractitionerNotesSection(data)],
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// VII · Additional findings — anything the backend sent that we don't model
// ---------------------------------------------------------------------------

class _AdditionalFindings extends StatelessWidget {
  final List<MapEntry<String, dynamic>> extras;
  const _AdditionalFindings(this.extras);

  @override
  Widget build(BuildContext context) {
    return _Section('VII. Additional findings', [
      _prose(
        context,
        'This analysis returned fields beyond the standard report.',
      ),
      ReportExpander(
        label: 'Show ${extras.length} additional field'
            '${extras.length == 1 ? '' : 's'}',
        children: [
          for (final e in extras)
            GenericSection(HydraReport.humanize(e.key), e.value),
        ],
      ),
    ]);
  }
}
