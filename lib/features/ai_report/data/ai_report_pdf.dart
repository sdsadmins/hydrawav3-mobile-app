import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../presentation/ai_report_style.dart';

/// Build a multi-page A4 PDF of the AI report, styled to match the on-screen
/// report (`ai_report_screen.dart` + `widgets/sections/*`) — same Hydra
/// palette, section headings, colored callouts and chips (web parity with
/// `analysis-display.tsx`). Like the web PDF export, it contains ONLY the
/// audience currently being viewed: pass [practitioner] `true` for the
/// Practitioner report, `false` (default) for the client "Your Report".
///
/// Every entry pushed to [widgets] is a SMALL widget so MultiPage can paginate
/// freely (avoids `TooManyPagesException` from tall, unbreakable cards).
Future<Uint8List> buildAiReportPdf(
  Map<String, dynamic> rawReport, {
  String? title,
  bool practitioner = false,
}) async {
  final report = HydraReport.normalize(rawReport);
  final doc = pw.Document();
  final widgets = <pw.Widget>[];

  if (practitioner) {
    _emitPractitioner(report, widgets);
  } else {
    _emitClient(report, widgets);
  }

  if (widgets.isEmpty) {
    widgets.add(pw.Text('No report content available.',
        style: pw.TextStyle(color: _pc(HydraReport.muted))));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      header: (ctx) => ctx.pageNumber == 1
          ? _titleHeader(title, practitioner: practitioner)
          : pw.SizedBox(),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: _pc(HydraReport.muted))),
      ),
      build: (ctx) => widgets,
    ),
  );

  return doc.save();
}

// --- Color + data helpers --------------------------------------------------

PdfColor _pc(Color c) => PdfColor(c.r, c.g, c.b);

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};
List<String> _strList(dynamic v) => (v is List ? v : const [])
    .where((e) => e != null && e.toString().trim().isNotEmpty)
    .map((e) => _clean(e.toString()))
    .toList();
List<Map<String, dynamic>> _mapList(dynamic v) => (v is List ? v : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();
String _s(Map<String, dynamic> m, String key) =>
    _clean((m[key] ?? '').toString().trim());
String _unslug(String s) => s.replaceAll('_', ' ').trim();
bool _has(dynamic v) => HydraReport.hasContent(v);

/// The PDF's built-in Helvetica font only covers WinAnsi/Latin-1, so Unicode
/// the AI emits — arrows, em/en dashes, smart quotes, ellipses — renders as
/// tofu boxes. Map those to ASCII so the PDF reads cleanly.
String _clean(String s) {
  if (s.isEmpty) return s;
  return s
      .replaceAll('→', ' -> ') // →
      .replaceAll('←', ' <- ') // ←
      .replaceAll('↔', ' <-> ') // ↔
      .replaceAll('⇒', ' => ') // ⇒
      .replaceAll('➔', ' -> ') // ➔
      .replaceAll('➙', ' -> ') // ➙
      .replaceAll('➜', ' -> ') // ➜
      .replaceAll('➡', ' -> ') // ➡
      .replaceAll('–', '-') // – en dash
      .replaceAll('—', '-') // — em dash
      .replaceAll('―', '-') // ― horizontal bar
      .replaceAll('‘', "'") // ‘
      .replaceAll('’', "'") // ’
      .replaceAll('“', '"') // “
      .replaceAll('”', '"') // ”
      .replaceAll('…', '...') // …
      .replaceAll('•', '-') // •
      .replaceAll('‑', '-') // non-breaking hyphen
      .replaceAll(' ', ' ') // non-breaking space
      // Collapse any double spaces the arrow padding may introduce.
      .replaceAll(RegExp(r' {2,}'), ' ');
}

// --- Shared PDF building blocks -------------------------------------------

pw.Widget _titleHeader(String? title, {bool practitioner = false}) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _pc(HydraReport.darkTeal),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 30,
            height: 30,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _pc(HydraReport.tanDark),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text('AI',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title ?? 'AI Kinetic Chain Report',
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text(
                  practitioner
                      ? 'PRACTITIONER REPORT'
                      : 'YOUR REPORT',
                  style: pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: _pc(HydraReport.tanLight))),
            ],
          ),
        ],
      ),
    );

pw.Widget _heading(String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 6, bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _pc(HydraReport.tanDark), width: 0.8)),
      ),
      child: pw.Text(title.toUpperCase(),
          style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _pc(HydraReport.tanDark))),
    );

pw.Widget _sub(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
      child: pw.Text(text.toUpperCase(),
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _pc(HydraReport.muted))),
    );

pw.Widget _para(String text,
        {Color color = HydraReport.darkTeal, double size = 11}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: size, color: _pc(color), lineSpacing: 2)),
    );

pw.Widget _kv(String label, String value,
        {Color color = HydraReport.darkTeal}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: 10.5, color: _pc(color)),
          children: [
            pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: value),
          ],
        ),
      ),
    );

pw.Widget _chips(List<String> items,
        {Color bg = HydraReport.white,
        Color fg = HydraReport.darkTeal,
        Color? border}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in items)
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: _pc(bg),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _pc(border ?? HydraReport.tanLight)),
              ),
              child: pw.Text(t,
                  style: pw.TextStyle(
                      fontSize: 10,
                      color: _pc(fg),
                      fontWeight: pw.FontWeight.bold)),
            ),
        ],
      ),
    );

pw.Widget _bullet(String text, {Color color = HydraReport.darkTeal}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            margin: const pw.EdgeInsets.only(top: 4, right: 6),
            decoration: pw.BoxDecoration(
                color: _pc(HydraReport.tanDark), shape: pw.BoxShape.circle),
          ),
          pw.Expanded(
              child: pw.Text(text,
                  style: pw.TextStyle(fontSize: 10.5, color: _pc(color)))),
        ],
      ),
    );

pw.Widget _callout({
  String? label,
  required Color bg,
  required Color border,
  Color? labelColor,
  required List<pw.Widget> children,
}) =>
    pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _pc(bg),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pc(border)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            pw.Text(label.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _pc(labelColor ?? HydraReport.muted))),
            pw.SizedBox(height: 4),
          ],
          ...children,
        ],
      ),
    );

pw.Widget _percentPill(dynamic level, {bool alternative = false}) {
  final c = alternative ? HydraReport.darkTeal : HydraReport.tanDark;
  final txt = level is num ? '${level.round()}%' : '--%';
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
        color: _pc(c), borderRadius: pw.BorderRadius.circular(999)),
    child: pw.Text(txt,
        style: pw.TextStyle(
            fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
  );
}

// --- Client (Your Report) sections ----------------------------------------

void _emitClient(Map<String, dynamic> r, List<pw.Widget> out) {
  if (_has(r['personal_snapshot'])) _personalSnapshot(r, out);
  if (_has(r['clinical_insight_snapshot'])) _clinicalInsight(r, out);
  if (_has(r['movement_mobility_summary'])) _movement(r, out);
  if (_has(r['kinetic_chain_pattern_a'])) _patternFull(r, 'a', out);
  if (_has(r['kinetic_chain_pattern_b'])) _patternFull(r, 'b', out);
  if (_has(r['load_vs_recovery_profile'])) _loadRecovery(r, out);
  if (_has(r['lifestyle_contributors'])) _lifestyle(r, out);
  if (_has(r['at_home_mobility_support'])) _atHome(r, out);
  if (_has(r['why_this_pattern_matters'])) _whyMatters(r, out);
  if (_has(r['practitioner_questions'])) _questions(r, out);
  if (_has(r['next_steps'])) _nextSteps(r, out);
  if (_has(r['disclaimer'])) _disclaimer(r, out);
}

void _personalSnapshot(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['personal_snapshot']);
  out.add(_heading('Personal Snapshot'));
  if (_s(m, 'age').isNotEmpty) out.add(_kv('Age', _s(m, 'age')));
  if (_s(m, 'gender').isNotEmpty) out.add(_kv('Gender', _s(m, 'gender')));
  if (_s(m, 'primary_concern').isNotEmpty) {
    out.add(_callout(label: 'Primary Concern', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'primary_concern'))]));
  }
  final secondary = _strList(m['secondary_concerns']);
  if (secondary.isNotEmpty) {
    out.add(_sub('Secondary Concerns'));
    out.add(_chips(secondary));
  }
  if (_s(m, 'pain_duration_category').isNotEmpty) {
    out.add(_kv('Pain Duration', _unslug(_s(m, 'pain_duration_category')),
        color: HydraReport.tanDark));
  }
}

void _clinicalInsight(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['clinical_insight_snapshot']);
  out.add(_heading('Clinical Insight Summary'));
  if (_s(m, 'summary_statement').isNotEmpty) out.add(_para(_s(m, 'summary_statement')));
  if (_s(m, 'primary_movement_bias').isNotEmpty) out.add(_kv('Movement Bias', _s(m, 'primary_movement_bias')));
  if (_s(m, 'dominant_kinetic_chain').isNotEmpty) out.add(_kv('Dominant Chain', _s(m, 'dominant_kinetic_chain')));
  if (_s(m, 'primary_symptom_region').isNotEmpty) out.add(_kv('Symptom Region', _s(m, 'primary_symptom_region')));
}

void _movement(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['movement_mobility_summary']);
  out.add(_heading('Movement & Mobility Summary'));

  final findings = _strList(m['primary_movement_findings']);
  if (findings.isNotEmpty) {
    out.add(_sub('A. Primary Movement Findings'));
    for (final f in findings) {
      out.add(_bullet(f));
    }
  }

  final crit = _map(m['critical_indicator']);
  if (_s(crit, 'exact_response').isNotEmpty) {
    out.add(_sub('B. Critical Indicator'));
    out.add(_callout(bg: HydraReport.red50, border: HydraReport.red500, children: [
      _kv('Exact Response', _s(crit, 'exact_response'), color: HydraReport.red900),
      if (_s(crit, 'muscle_group_implicated').isNotEmpty)
        _kv('Muscle Group Implicated', _s(crit, 'muscle_group_implicated'), color: HydraReport.red900),
      if (_s(crit, 'mechanical_significance').isNotEmpty)
        _kv('Mechanical Significance', _s(crit, 'mechanical_significance'), color: HydraReport.red900),
    ]));
  }

  final sensations = _mapList(m['post_movement_sensations']);
  if (sensations.isNotEmpty) {
    out.add(_sub('C. Post-Movement Sensations'));
    for (final s in sensations) {
      final side = _s(s, 'side').isNotEmpty ? ' (${_s(s, 'side')})' : '';
      out.add(_kv(_s(s, 'location') + side, _s(s, 'quality')));
    }
  }

  final dir = _map(m['secondary_pattern_direction']);
  if (_s(dir, 'chain_map').isNotEmpty) {
    out.add(_sub('D. Secondary Pattern Direction'));
    if (_s(dir, 'classification').isNotEmpty) {
      out.add(_chips([_unslug(_s(dir, 'classification'))],
          bg: HydraReport.darkTeal, fg: HydraReport.white, border: HydraReport.darkTeal));
    }
    out.add(_para(_s(dir, 'chain_map')));
  }

  if (_s(m, 'movement_bias_classification').isNotEmpty) {
    out.add(_sub('E. Movement Bias Classification'));
    out.add(_chips([_unslug(_s(m, 'movement_bias_classification'))],
        bg: HydraReport.cream, fg: HydraReport.tanDark, border: HydraReport.tanLight));
  }

  if (_s(m, 'user_insight_integration').isNotEmpty) {
    out.add(_sub('F. User Insight Integration'));
    out.add(_para(_s(m, 'user_insight_integration')));
  }
}

void _patternFull(Map<String, dynamic> r, String which, List<pw.Widget> out) {
  final isB = which == 'b';
  final p = _map(r['kinetic_chain_pattern_$which']);
  final confidence = _map(p['confidence']);
  out.add(_heading(isB
      ? 'Kinetic Chain Pattern B (Alternative)'
      : 'Kinetic Chain Pattern A'));

  // Identification.
  final idChildren = <pw.Widget>[];
  if (_s(p, 'pattern_label').isNotEmpty) {
    idChildren.add(pw.Text(_s(p, 'pattern_label'),
        style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _pc(HydraReport.darkTeal))));
  }
  if (_s(p, 'primary_driver_region').isNotEmpty) {
    idChildren.add(pw.SizedBox(height: 3));
    idChildren.add(_kv('Primary Driver', _s(p, 'primary_driver_region'),
        color: isB ? HydraReport.muted : HydraReport.tanDark));
  }
  if (_s(p, 'direction_of_dysfunction').isNotEmpty) {
    idChildren.add(_kv('Direction', _unslug(_s(p, 'direction_of_dysfunction'))));
  }
  if (_s(p, 'direction_rationale').isNotEmpty) {
    idChildren.add(_para(_s(p, 'direction_rationale')));
  }
  if (_s(confidence, 'level').isNotEmpty) {
    idChildren.add(pw.SizedBox(height: 3));
    idChildren.add(_kv('Confidence', '${_s(confidence, 'level')}%'));
  }
  out.add(_callout(
      bg: isB ? HydraReport.gray50 : HydraReport.cream,
      border: isB ? HydraReport.gray100 : HydraReport.tanLight,
      children: idChildren));

  // Chain map.
  final chain = _mapList(p['primary_kinetic_chain']);
  if (chain.isNotEmpty) {
    out.add(_sub(isB ? 'II. Chain Map' : 'II. Structural Kinetic Chain Map'));
    out.add(_para(chain.map((c) => _s(c, 'muscle')).where((s) => s.isNotEmpty).join('  ->  '),
        color: HydraReport.darkTeal));
    for (final link in chain) {
      if (_s(link, 'reason').isNotEmpty) {
        out.add(_kv(_s(link, 'muscle'), _s(link, 'reason')));
      }
    }
  }

  // Secondary compensatory.
  final secondary = _mapList(p['secondary_compensatory_regions']);
  if (secondary.isNotEmpty) {
    out.add(_sub('Secondary Compensatory Regions'));
    for (final sc in secondary) {
      final type = _s(sc, 'type').isNotEmpty ? ' [${_s(sc, 'type')}]' : '';
      out.add(_callout(bg: HydraReport.yellow50, border: HydraReport.yellow100, children: [
        pw.Text('${_s(sc, 'region')}$type',
            style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _pc(HydraReport.yellow900))),
        if (_s(sc, 'mechanism').isNotEmpty)
          _para(_s(sc, 'mechanism'), color: HydraReport.yellow700, size: 10),
      ]));
    }
  }

  if (isB) {
    _patternBTail(p, out);
  } else {
    _patternATail(p, out);
  }

  if (_s(confidence, 'justification').isNotEmpty) {
    out.add(_callout(label: 'Confidence Justification', bg: HydraReport.cream, border: HydraReport.tanLight, children: [
      _para(_s(confidence, 'justification')),
    ]));
  }

  if (isB) {
    final verdict = _s(p, 'summary_verdict');
    final hierarchy = _s(p, 'pattern_hierarchy');
    if (verdict.isNotEmpty || hierarchy.isNotEmpty) {
      out.add(_callout(bg: HydraReport.darkTeal, border: HydraReport.darkTeal, children: [
        if (verdict.isNotEmpty) _para('Summary Verdict: $verdict', color: HydraReport.white),
        if (hierarchy.isNotEmpty) _para('Pattern Hierarchy: $hierarchy', color: HydraReport.white),
      ]));
    }
  }
}

void _patternATail(Map<String, dynamic> p, List<pw.Widget> out) {
  final spinal = _mapList(p['primary_spinal_segments']);
  final dermatomes = _strList(p['corresponding_dermatomes']);
  final viscero = _strList(p['viscerosomatic_associations']);
  final myofascial = _mapList(p['myofascial_lines']);
  final supporting = _strList(p['supporting_findings']);
  final retests = _mapList(p['suggested_retests']);

  if (spinal.isNotEmpty || dermatomes.isNotEmpty || viscero.isNotEmpty) {
    out.add(_sub('III. Neurological & Segmental Context'));
    for (final seg in spinal) {
      final muscles = _s(seg, 'muscles').isNotEmpty ? ' — ${_s(seg, 'muscles')}' : '';
      out.add(_kv(_s(seg, 'segment'), _s(seg, 'functional_role') + muscles,
          color: HydraReport.purple700));
    }
    if (dermatomes.isNotEmpty) {
      out.add(_chips(dermatomes,
          bg: HydraReport.purple50, fg: HydraReport.purple700, border: HydraReport.purple100));
    }
    for (final v in viscero) {
      out.add(_para(v));
    }
  }

  if (myofascial.isNotEmpty) {
    out.add(_sub('IV. Fascial & Global Integration'));
    for (final ml in myofascial) {
      out.add(_kv(_s(ml, 'line_name'), _s(ml, 'relevance')));
    }
  }

  if (_s(p, 'biomechanical_explanation').isNotEmpty) {
    out.add(_sub('V. Biomechanical Explanation'));
    out.add(_para(_s(p, 'biomechanical_explanation')));
  }

  if (supporting.isNotEmpty) {
    out.add(_sub('VI. Supporting Findings'));
    for (final f in supporting) {
      out.add(_bullet(f, color: HydraReport.green900));
    }
  }

  if (retests.isNotEmpty) {
    out.add(_sub('Suggested Retests'));
    for (final rt in retests) {
      out.add(_callout(bg: HydraReport.gray50, border: HydraReport.gray100, children: [
        if (_s(rt, 'name').isNotEmpty)
          pw.Text(_s(rt, 'name'),
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _pc(HydraReport.darkTeal))),
        if (_s(rt, 'procedure').isNotEmpty) _para(_s(rt, 'procedure'), color: HydraReport.muted, size: 10),
        if (_s(rt, 'observation').isNotEmpty) _para('Look for: ${_s(rt, 'observation')}', color: HydraReport.tanDark, size: 10),
      ]));
    }
  }
}

void _patternBTail(Map<String, dynamic> p, List<pw.Widget> out) {
  if (_s(p, 'biomechanical_rationale').isNotEmpty) {
    out.add(_sub('III. Biomechanical Rationale'));
    out.add(_para(_s(p, 'biomechanical_rationale')));
  }
  final why = _strList(p['why_plausible']);
  final contra = _strList(p['contradicting_evidence']);
  if (why.isNotEmpty) {
    out.add(_callout(label: 'Why Plausible', bg: HydraReport.green50, border: HydraReport.green100, labelColor: HydraReport.green600, children: [
      for (final w in why) _para(w, color: HydraReport.green900, size: 10),
    ]));
  }
  if (contra.isNotEmpty) {
    out.add(_callout(label: 'Contradicting Evidence', bg: HydraReport.red50, border: HydraReport.red100, labelColor: HydraReport.red500, children: [
      for (final c in contra) _para(c, color: HydraReport.red900, size: 10),
    ]));
  }
  final support = _strList(p['supporting_evidence']);
  if (support.isNotEmpty) {
    out.add(_sub('Supporting Evidence'));
    for (final e in support) {
      out.add(_bullet(e));
    }
  }
  if (_s(p, 'user_insights_reframed').isNotEmpty) {
    out.add(_callout(label: 'User Insights Reframed', bg: HydraReport.cream, border: HydraReport.tanLight, children: [
      _para(_s(p, 'user_insights_reframed')),
    ]));
  }
}

void _loadRecovery(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['load_vs_recovery_profile']);
  out.add(_heading('Load vs Recovery Profile'));

  final exp = _map(m['positioning_exposure']);
  if (exp.isNotEmpty) {
    out.add(_sub('Positioning Exposure'));
    if (_s(exp, 'primary_activity').isNotEmpty) out.add(_kv('Primary Activity', _s(exp, 'primary_activity')));
    if (_s(exp, 'estimated_daily_hours').isNotEmpty) out.add(_kv('Daily Hours', '${_s(exp, 'estimated_daily_hours')}h'));
    final short = _strList(exp['tissues_chronically_shortened']);
    final long = _strList(exp['tissues_chronically_lengthened']);
    if (short.isNotEmpty) {
      out.add(_callout(label: 'Chronically Shortened', bg: HydraReport.red50, border: HydraReport.red100, labelColor: HydraReport.red500, children: [_chips(short, bg: HydraReport.red100, fg: HydraReport.red800, border: HydraReport.red100)]));
    }
    if (long.isNotEmpty) {
      out.add(_callout(label: 'Chronically Lengthened', bg: HydraReport.blue50, border: HydraReport.blue100, labelColor: HydraReport.blue500, children: [_chips(long, bg: HydraReport.blue100, fg: HydraReport.blue800, border: HydraReport.blue100)]));
    }
  }

  final sleep = _map(m['sleep_loading']);
  if (_s(sleep, 'position').isNotEmpty) {
    out.add(_callout(label: 'Sleep Loading', bg: HydraReport.purple50, border: HydraReport.purple100, labelColor: HydraReport.purple700, children: [
      _kv('Position', _s(sleep, 'position')),
      if (_s(sleep, 'effect_on_pattern').isNotEmpty) _kv('Effect', _s(sleep, 'effect_on_pattern')),
      if (_s(sleep, 'tissue_impact').isNotEmpty) _kv('Impact', _s(sleep, 'tissue_impact')),
    ]));
  }

  final temporal = _map(m['temporal_aggravation_patterns']);
  final morning = _s(temporal, 'morning');
  final endOfDay = _s(temporal, 'end_of_day');
  final exercise = _s(temporal, 'during_after_exercise');
  if (morning.isNotEmpty || endOfDay.isNotEmpty || exercise.isNotEmpty) {
    out.add(_sub('Temporal Aggravation Patterns'));
    if (morning.isNotEmpty) out.add(_callout(label: 'Morning', bg: HydraReport.yellow50, border: HydraReport.yellow100, labelColor: HydraReport.yellow600, children: [_para(morning, color: HydraReport.yellow900, size: 10)]));
    if (endOfDay.isNotEmpty) out.add(_callout(label: 'End of Day', bg: HydraReport.orange50, border: HydraReport.orange100, labelColor: HydraReport.orange600, children: [_para(endOfDay, color: HydraReport.orange900, size: 10)]));
    if (exercise.isNotEmpty) out.add(_callout(label: 'During / After Exercise', bg: HydraReport.red50, border: HydraReport.red100, labelColor: HydraReport.red500, children: [_para(exercise, color: HydraReport.red900, size: 10)]));
  }

  final factors = _strList(m['user_context_factors']);
  if (factors.isNotEmpty) {
    out.add(_sub('User Context Factors'));
    for (final f in factors) {
      out.add(_bullet(f));
    }
  }

  final balance = _map(m['load_recovery_balance']);
  if (balance.isNotEmpty && _has(balance)) {
    out.add(_callout(label: 'Load / Recovery Balance', bg: HydraReport.gray50, border: HydraReport.gray100, children: [
      if (_s(balance, 'daily_load_hours').isNotEmpty) _kv('Daily Load', '${_s(balance, 'daily_load_hours')}h'),
      if (_s(balance, 'recovery_status').isNotEmpty) _kv('Status', _unslug(_s(balance, 'recovery_status'))),
      if (_s(balance, 'critical_recovery_gap').isNotEmpty) _kv('Critical Gap', _s(balance, 'critical_recovery_gap')),
    ]));
  }

  if (_s(m, 'functional_summary').isNotEmpty) {
    out.add(_callout(label: 'Functional Summary', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'functional_summary'))]));
  }
}

void _positioning(String title, Map<String, dynamic> data, List<pw.Widget> out) {
  out.add(_sub(title));
  if (_s(data, 'activity').isNotEmpty) out.add(_kv('Activity', _s(data, 'activity')));
  if (_s(data, 'position_held').isNotEmpty) out.add(_kv('Position', _s(data, 'position_held')));
  if (_s(data, 'estimated_duration').isNotEmpty) out.add(_kv('Duration', _s(data, 'estimated_duration')));
  final short = _strList(data['tissues_shortened']);
  final long = _strList(data['tissues_lengthened']);
  if (short.isNotEmpty) out.add(_kv('Shortened', short.join(', '), color: HydraReport.red800));
  if (long.isNotEmpty) out.add(_kv('Lengthened', long.join(', '), color: HydraReport.blue800));
  if (_s(data, 'mechanical_consequence').isNotEmpty) out.add(_para(_s(data, 'mechanical_consequence')));
}

void _lifestyle(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['lifestyle_contributors']);
  out.add(_heading('Lifestyle Contributors'));

  final primary = _map(m['primary_positioning']);
  final secondary = _map(m['secondary_positioning']);
  if (_s(primary, 'activity').isNotEmpty) _positioning('Primary Positioning', primary, out);
  if (_s(secondary, 'activity').isNotEmpty) _positioning('Secondary Positioning', secondary, out);

  final sleep = _map(m['sleep_position_influence']);
  if (_s(sleep, 'position').isNotEmpty) {
    out.add(_callout(label: 'Sleep Position Influence', bg: HydraReport.purple50, border: HydraReport.purple100, labelColor: HydraReport.purple700, children: [
      _kv('Position', _s(sleep, 'position')),
      if (_s(sleep, 'effect').isNotEmpty) _kv('Effect', _s(sleep, 'effect')),
      if (_s(sleep, 'asymmetry_contribution').isNotEmpty) _kv('Asymmetry Contribution', _s(sleep, 'asymmetry_contribution')),
    ]));
  }

  final asym = _map(m['asymmetric_loading_factors']);
  final contributors = _strList(asym['user_insight_contributors']);
  if (_s(asym, 'clinical_laterality').isNotEmpty || contributors.isNotEmpty) {
    out.add(_sub('Asymmetric Loading Factors'));
    if (_s(asym, 'clinical_laterality').isNotEmpty) out.add(_kv('Clinical Laterality', _s(asym, 'clinical_laterality')));
    if (_s(asym, 'sleep_preference').isNotEmpty) out.add(_kv('Sleep Preference', _s(asym, 'sleep_preference')));
    for (final c in contributors) {
      out.add(_bullet(c));
    }
  }

  if (_s(m, 'reinforcement_loop_summary').isNotEmpty) {
    out.add(_callout(label: 'Reinforcement Loop Summary', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'reinforcement_loop_summary'))]));
  }
}

void _atHome(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['at_home_mobility_support']);
  out.add(_heading('At-Home Mobility Support'));

  if (_s(m, 'selection_rationale').isNotEmpty) {
    out.add(_callout(label: 'Selection Rationale', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'selection_rationale'))]));
  }

  final exercises = _mapList(m['exercises']);
  if (exercises.isNotEmpty) {
    out.add(_sub('Exercises'));
    for (var i = 0; i < exercises.length; i++) {
      final ex = exercises[i];
      final meta = [
        if (_s(ex, 'frequency').isNotEmpty) _s(ex, 'frequency'),
        if (_s(ex, 'duration_reps').isNotEmpty) _s(ex, 'duration_reps'),
      ].join(' · ');
      final children = <pw.Widget>[
        pw.Text('${i + 1}. ${_s(ex, 'name')}${meta.isNotEmpty ? '  ($meta)' : ''}',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pc(HydraReport.darkTeal))),
        if (_s(ex, 'addresses').isNotEmpty) _para('Addresses: ${_s(ex, 'addresses')}', color: HydraReport.tanDark, size: 10),
      ];
      final procedure = _strList(ex['procedure']);
      for (var si = 0; si < procedure.length; si++) {
        children.add(_para('${si + 1}. ${procedure[si]}', size: 10));
      }
      if (_s(ex, 'important_notes').isNotEmpty) {
        children.add(_para('Note: ${_s(ex, 'important_notes')}', color: HydraReport.yellow900, size: 10));
      }
      out.add(_callout(bg: HydraReport.white, border: HydraReport.tanLight, children: children));
    }
  }

  final relief = _strList(m['relief_based_mapping']);
  if (relief.isNotEmpty) {
    out.add(_sub('Relief-Based Mapping'));
    out.add(_chips(relief, bg: HydraReport.green50, fg: HydraReport.green800, border: HydraReport.green100));
  }
  if (_s(m, 'daily_integration_guidance').isNotEmpty) {
    out.add(_callout(label: 'Daily Integration Guidance', bg: HydraReport.gray50, border: HydraReport.gray100, children: [_para(_s(m, 'daily_integration_guidance'))]));
  }
  if (_s(m, 'functional_goal').isNotEmpty) {
    out.add(_callout(label: 'Functional Goal', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'functional_goal'))]));
  }
}

void _whyMatters(Map<String, dynamic> r, List<pw.Widget> out) {
  final v = r['why_this_pattern_matters'];
  final text = v is String ? v : (v is Map ? (v['explanation'] ?? '').toString() : '');
  if (text.trim().isEmpty) return;
  out.add(_heading('Why This Pattern Matters'));
  out.add(_para(text));
}

void _questions(Map<String, dynamic> r, List<pw.Widget> out) {
  final qs = _strList(r['practitioner_questions']);
  out.add(_heading('Questions for Your Practitioner'));
  for (var i = 0; i < qs.length; i++) {
    out.add(_para('${i + 1}. ${qs[i]}'));
  }
}

void _nextSteps(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['next_steps']);
  out.add(_heading('Next Steps'));
  final focus = _strList(m['recommended_focus_areas']);
  if (focus.isNotEmpty) {
    out.add(_sub('Recommended Focus Areas'));
    out.add(_chips(focus, bg: HydraReport.green50, fg: HydraReport.green800, border: HydraReport.green100));
  }
  final modalities = _strList(m['supportive_modalities']);
  if (modalities.isNotEmpty) {
    out.add(_sub('Supportive Modalities'));
    for (final mod in modalities) {
      out.add(_bullet(mod));
    }
  }
}

void _disclaimer(Map<String, dynamic> r, List<pw.Widget> out) {
  out.add(pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6, bottom: 10),
    child: pw.Text(_s(r, 'disclaimer'),
        style: pw.TextStyle(fontSize: 8.5, color: _pc(HydraReport.gray400))),
  ));
}

// --- Practitioner sections -------------------------------------------------

void _emitPractitioner(Map<String, dynamic> r, List<pw.Widget> out) {
  _padPlacement(r, out);
  if (_has(r['practitioner_hand_off'])) {
    out.add(_heading('Practitioner Hand-Off'));
    out.add(_para(_s(r, 'practitioner_hand_off')));
  }
  if (_has(r['kinetic_chain_pattern_a'])) _patternCompact(r, 'a', out);
  if (_has(r['kinetic_chain_pattern_b'])) _patternCompact(r, 'b', out);
  if (_has(r['practitioner_notes_template'])) _notes(r, out);
  if (_has(r['disclaimer'])) _disclaimer(r, out);
}

void _padPlacement(Map<String, dynamic> r, List<pw.Widget> out) {
  out.add(_heading('AI Pad Placement'));
  final intake = _map(r['intakeData']);
  var areas = [
    for (final a in _mapList(intake['discomfort_areas'])) _s(a, 'body_area'),
  ].where((s) => s.isNotEmpty).toSet().toList();
  if (areas.isEmpty) {
    areas = _strList(_map(r['next_steps'])['recommended_focus_areas']).toSet().toList();
  }
  if (areas.isEmpty) {
    out.add(_para('No focus areas captured for pad placement.', color: HydraReport.muted));
    return;
  }
  out.add(_para('Focus areas for Hydrawav3 pad placement:', color: HydraReport.muted, size: 10));
  out.add(_chips(areas, bg: HydraReport.cream, fg: HydraReport.darkTeal, border: HydraReport.tanLight));
  out.add(_para('Open the report in the app to view each area\'s Sun/Moon electrode placements.',
      color: HydraReport.gray400, size: 9));
}

void _patternCompact(Map<String, dynamic> r, String which, List<pw.Widget> out) {
  final isB = which == 'b';
  final p = _map(r['kinetic_chain_pattern_$which']);
  final confidence = _map(p['confidence']);
  out.add(_heading('Pattern ${which.toUpperCase()}: ${_s(p, 'pattern_label')}'));
  out.add(pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(children: [
      _percentPill(confidence['level'], alternative: isB),
    ]),
  ));
  if (_s(p, 'primary_driver_region').isNotEmpty) out.add(_kv('Driver', _s(p, 'primary_driver_region')));
  if (_s(p, 'direction_of_dysfunction').isNotEmpty) out.add(_kv('Direction', _unslug(_s(p, 'direction_of_dysfunction'))));

  final chain = _mapList(p['primary_kinetic_chain']);
  if (chain.isNotEmpty) {
    out.add(_sub('Kinetic Chain'));
    out.add(_para(chain.map((c) => _s(c, 'muscle')).where((s) => s.isNotEmpty).join('  ->  ')));
  }

  if (!isB) {
    final spinal = _mapList(p['primary_spinal_segments']);
    if (spinal.isNotEmpty) {
      out.add(_sub('Spinal Segments'));
      out.add(_chips([for (final s in spinal) _s(s, 'segment')], bg: HydraReport.purple100, fg: HydraReport.purple800, border: HydraReport.purple100));
    }
    final myofascial = _mapList(p['myofascial_lines']);
    if (myofascial.isNotEmpty) {
      out.add(_sub('Myofascial Lines'));
      out.add(_chips([for (final ml in myofascial) _s(ml, 'line_name')], bg: HydraReport.cream, fg: HydraReport.darkTeal, border: HydraReport.tanLight));
    }
    final retests = _mapList(p['suggested_retests']);
    if (retests.isNotEmpty) {
      out.add(_sub('Suggested Retests'));
      for (final rt in retests) {
        out.add(_kv(_s(rt, 'name'), _s(rt, 'observation').isNotEmpty ? 'Look for: ${_s(rt, 'observation')}' : _s(rt, 'procedure')));
      }
    }
  } else {
    final why = _strList(p['why_plausible']);
    final contra = _strList(p['contradicting_evidence']);
    if (why.isNotEmpty) {
      out.add(_callout(label: 'Why Plausible', bg: HydraReport.green50, border: HydraReport.green100, labelColor: HydraReport.green600, children: [for (final w in why) _para(w, color: HydraReport.green900, size: 10)]));
    }
    if (contra.isNotEmpty) {
      out.add(_callout(label: 'Contradicting Evidence', bg: HydraReport.red50, border: HydraReport.red100, labelColor: HydraReport.red500, children: [for (final c in contra) _para(c, color: HydraReport.red900, size: 10)]));
    }
    if (_s(p, 'summary_verdict').isNotEmpty) {
      out.add(_callout(bg: HydraReport.darkTeal, border: HydraReport.darkTeal, children: [_para('Verdict: ${_s(p, 'summary_verdict')}', color: HydraReport.white)]));
    }
  }
}

void _notes(Map<String, dynamic> r, List<pw.Widget> out) {
  final m = _map(r['practitioner_notes_template']);
  out.add(_heading('Practitioner Notes Template'));

  final manual = _strList(m['manual_assessment_areas']);
  if (manual.isNotEmpty) {
    out.add(_sub('Manual Assessment Areas'));
    for (final a in manual) {
      out.add(_bullet(a));
    }
  }
  final quality = _strList(m['movement_quality_checks']);
  if (quality.isNotEmpty) {
    out.add(_sub('Movement Quality Checks'));
    for (final c in quality) {
      out.add(_bullet(c));
    }
  }
  final retests = _strList(m['retests']);
  if (retests.isNotEmpty) {
    out.add(_sub('Retests'));
    for (final rt in retests) {
      out.add(_bullet(rt));
    }
  }
  if (_s(m, 'session_notes_placeholder').isNotEmpty) {
    out.add(_callout(label: 'Session Notes Placeholder', bg: HydraReport.gray50, border: HydraReport.gray100, children: [_para(_s(m, 'session_notes_placeholder'), color: HydraReport.muted)]));
  }
  if (_s(m, 'response_tracking').isNotEmpty) {
    out.add(_callout(label: 'Response Tracking', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'response_tracking'))]));
  }
  if (_s(m, 'user_insights_modifications').isNotEmpty) {
    out.add(_callout(label: 'User Insights & Modifications', bg: HydraReport.gray50, border: HydraReport.gray100, children: [_para(_s(m, 'user_insights_modifications'))]));
  }
  if (_s(m, 'follow_up').isNotEmpty) {
    out.add(_callout(label: 'Follow-Up', bg: HydraReport.cream, border: HydraReport.tanLight, children: [_para(_s(m, 'follow_up'))]));
  }
}
