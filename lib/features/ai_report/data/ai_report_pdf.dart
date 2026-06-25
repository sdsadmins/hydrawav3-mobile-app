import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../presentation/ai_report_style.dart';

/// Build a multi-page A4 PDF of the AI report, styled to match the on-screen
/// report (`ai_report_screen.dart`) — same Hydra palette, section cards, chips,
/// confidence badges and colored callouts (web parity with `analysis-display.tsx`).
///
/// Every entry in the MultiPage children list is a SMALL widget so MultiPage can
/// paginate freely (avoids `TooManyPagesException` from tall, unbreakable cards).
Future<Uint8List> buildAiReportPdf(
  Map<String, dynamic> rawReport, {
  String? title,
}) async {
  final report = HydraReport.normalize(rawReport);
  final doc = pw.Document();
  final widgets = <pw.Widget>[];

  void addSection(String key, String heading, dynamic value) {
    widgets.add(_sectionHeading(heading));
    if (key == 'disclaimer') {
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text(value.toString(),
            style: pw.TextStyle(fontSize: 9, color: _pc(HydraReport.muted))),
      ));
    } else {
      _emit(value, widgets, 0);
      widgets.add(pw.SizedBox(height: 14));
    }
  }

  for (final s in HydraReport.sections) {
    final value = report[s.key];
    if (!HydraReport.hasContent(value)) continue;
    addSection(s.key, s.title, value);
  }
  // Any extra content keys the API returns that aren't known sections.
  for (final e in HydraReport.extraSections(report)) {
    addSection(e.key, HydraReport.humanize(e.key), e.value);
  }
  if (widgets.isEmpty) {
    widgets.add(pw.Text('No report content available.',
        style: pw.TextStyle(color: _pc(HydraReport.muted))));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      header: (ctx) => ctx.pageNumber == 1 ? _titleHeader(title) : pw.SizedBox(),
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

PdfColor _pc(Color c) => PdfColor(c.r, c.g, c.b);

pw.Widget _titleHeader(String? title) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _pc(HydraReport.darkTeal),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title ?? 'AI Kinetic Chain Report',
              style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white)),
          pw.SizedBox(height: 2),
          pw.Text('COMPLETE AI ANALYSIS REPORT',
              style: pw.TextStyle(
                  fontSize: 9, color: _pc(HydraReport.tanLight))),
        ],
      ),
    );

pw.Widget _sectionHeading(String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8),
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

/// Append styled widgets for [value] to [out] (kept flat for safe pagination).
void _emit(dynamic value, List<pw.Widget> out, int depth) {
  if (value is String || value is num || value is bool) {
    out.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(value.toString(),
          style: pw.TextStyle(fontSize: 11, color: _pc(HydraReport.darkTeal))),
    ));
    return;
  }

  if (value is List) {
    final items = value.where(HydraReport.hasContent).toList();
    if (items.isEmpty) return;
    if (items.every((e) => e is String || e is num || e is bool)) {
      out.add(_chips(items.map((e) => e.toString()).toList()));
      return;
    }
    for (final item in items) {
      _emit(item, out, depth + 1);
      out.add(pw.SizedBox(height: 4));
    }
    return;
  }

  if (value is Map) {
    if (value['level'] is num) {
      out.add(_confidence(value));
      return;
    }
    for (final e in value.entries.where((e) => HydraReport.hasContent(e.value))) {
      final key = e.key.toString();
      final v = e.value;
      final isScalar = v is String || v is num || v is bool;
      final isChips = v is List &&
          v.where(HydraReport.hasContent).every(
              (x) => x is String || x is num || x is bool);

      if (v is Map && v['level'] is num) {
        out.add(_kvCard(HydraReport.humanize(key), [_confidence(v)],
            HydraReport.toneForKey(key)));
      } else if (isScalar || isChips) {
        final child = isChips
            ? _chips([for (final x in v) x.toString()])
            : pw.Text(v.toString(),
                style: pw.TextStyle(
                    fontSize: 11, color: _pc(HydraReport.darkTeal)));
        out.add(_kvCard(HydraReport.humanize(key), [child],
            HydraReport.toneForKey(key)));
      } else {
        // Nested map / list-of-maps → label heading then flat content.
        out.add(_label(HydraReport.humanize(key),
            _pc(HydraReport.toneForKey(key).accent)));
        _emit(v, out, depth + 1);
        out.add(pw.SizedBox(height: 2));
      }
    }
    return;
  }
}

pw.Widget _label(String text, PdfColor color) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3, top: 2),
      child: pw.Text(text.toUpperCase(),
          style: pw.TextStyle(
              fontSize: 9, fontWeight: pw.FontWeight.bold, color: color)),
    );

pw.Widget _kvCard(String label, List<pw.Widget> children, CalloutTone tone) =>
    pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _pc(tone.bg),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pc(tone.border)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _pc(tone.accent))),
          pw.SizedBox(height: 4),
          ...children,
        ],
      ),
    );

pw.Widget _chips(List<String> items) => pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in items)
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(999),
              border: pw.Border.all(color: _pc(HydraReport.tanLight)),
            ),
            child: pw.Text(t,
                style: pw.TextStyle(
                    fontSize: 10, color: _pc(HydraReport.darkTeal))),
          ),
      ],
    );

pw.Widget _confidence(Map value) {
  final level = value['level'] as num;
  final justification = value['justification']?.toString();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: pw.BoxDecoration(
          color: _pc(HydraReport.tanLight),
          borderRadius: pw.BorderRadius.circular(999),
        ),
        child: pw.Text('${level.round()}% confidence',
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _pc(HydraReport.darkTeal))),
      ),
      if (justification != null && justification.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(justification,
            style:
                pw.TextStyle(fontSize: 11, color: _pc(HydraReport.darkTeal))),
      ],
    ],
  );
}
