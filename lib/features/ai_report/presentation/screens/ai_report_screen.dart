import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../data/ai_report_pdf.dart';
import '../ai_report_style.dart';

/// Renders an AI report styled like the web (`analysis-display.tsx`): brand
/// colors, section cards, chips, confidence badges, colored callouts. The same
/// styling/colors are mirrored in the downloaded PDF (`ai_report_pdf.dart`).
class AiReportScreen extends StatefulWidget {
  final Map<String, dynamic>? report;

  const AiReportScreen({super.key, this.report});

  @override
  State<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends State<AiReportScreen> {
  int _tab = 0; // 0 = Your Report, 1 = Practitioner Report

  @override
  Widget build(BuildContext context) {
    final raw = widget.report;
    final data = raw == null ? null : HydraReport.normalize(raw);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? ThemeConstants.background : HydraReport.cream,
      appBar: AppBar(
        backgroundColor: HydraReport.darkTeal,
        foregroundColor: Colors.white,
        title: const Text('AI Report'),
        actions: [
          if (data != null && data.isNotEmpty) ...[
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => shareAiReport(context, data),
            ),
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => downloadAiReport(context, data),
            ),
          ],
        ],
      ),
      body: data == null || data.isEmpty
          ? Center(
              child: Text('No report available.',
                  style: TextStyle(color: ThemeConstants.textSecondary)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                _header(),
                const SizedBox(height: 14),
                _tabs(),
                const SizedBox(height: 14),
                for (final s in HydraReport.sections)
                  if (HydraReport.hasContent(data[s.key]) &&
                      (_tab == 1 || !s.practitionerOnly))
                    _sectionCard(s, data[s.key]),
                // Any extra content keys the API returns that aren't known
                // sections — render them so nothing is dropped.
                for (final e in HydraReport.extraSections(data))
                  _sectionCard(
                    ReportSection(e.key, HydraReport.humanize(e.key),
                        Icons.article_outlined),
                    e.value,
                  ),
              ],
            ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HydraReport.darkTeal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: HydraReport.tanDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Kinetic Chain Report',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text('COMPLETE AI ANALYSIS REPORT',
                    style: TextStyle(
                        color: HydraReport.tanLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, int i, Color activeBg) {
      final active = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: active ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: active ? Colors.white : HydraReport.darkTeal,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: HydraReport.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          tab('YOUR REPORT', 0, HydraReport.tanDark),
          tab('PRACTITIONER', 1, HydraReport.darkTeal),
        ],
      ),
    );
  }

  Widget _sectionCard(ReportSection s, dynamic value) {
    final bg = switch (s.tone) {
      SectionTone.cream => HydraReport.cream,
      SectionTone.gray => const Color(0xFFF3F4F6),
      SectionTone.white => HydraReport.white,
    };
    final isDisclaimer = s.key == 'disclaimer';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s.icon, size: 16, color: HydraReport.tanDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title.toUpperCase(),
                  style: TextStyle(
                    color: HydraReport.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          isDisclaimer
              ? Text(value.toString(),
                  style: TextStyle(
                      color: HydraReport.muted, fontSize: 11, height: 1.5))
              : _node(value, 0),
        ],
      ),
    );
  }

  TextStyle get _bodyStyle =>
      const TextStyle(color: HydraReport.darkTeal, fontSize: 13.5, height: 1.4);

  Widget _node(dynamic value, int depth) {
    if (value is String || value is num || value is bool) {
      return Text(value.toString(), style: _bodyStyle);
    }
    if (value is List) {
      final items = value.where(HydraReport.hasContent).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      final allScalar =
          items.every((e) => e is String || e is num || e is bool);
      if (allScalar) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((e) => _chip(e.toString())).toList(),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _node(item, depth + 1),
            ),
        ],
      );
    }
    if (value is Map) {
      if (value['level'] is num) return _confidence(value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in value.entries.where((e) =>
              HydraReport.hasContent(e.value)))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _field(e.key.toString(), e.value, depth),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _field(String key, dynamic value, int depth) {
    final label = HydraReport.humanize(key);
    final isScalar = value is String || value is num || value is bool;
    final isChips = value is List &&
        value.where(HydraReport.hasContent).every(
            (e) => e is String || e is num || e is bool);

    if (value is Map && value['level'] is num) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _labelText(label, HydraReport.muted)),
          _confidenceBadge((value['level'] as num)),
        ],
      );
    }

    if (isScalar || isChips) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelText(label, HydraReport.muted),
          const SizedBox(height: 4),
          _node(value, depth + 1),
        ],
      );
    }

    // Nested map / list-of-maps → tinted callout sub-card.
    final tone = HydraReport.toneForKey(key);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelText(label, tone.accent),
          const SizedBox(height: 6),
          _node(value, depth + 1),
        ],
      ),
    );
  }

  Widget _labelText(String text, Color color) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: HydraReport.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HydraReport.tanLight),
        ),
        child: Text(text,
            style: const TextStyle(
                color: HydraReport.darkTeal,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );

  Widget _confidence(Map value) {
    final level = value['level'] as num;
    final justification = value['justification']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _confidenceBadge(level),
        if (justification != null && justification.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(justification, style: _bodyStyle),
        ],
      ],
    );
  }

  Widget _confidenceBadge(num level) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: HydraReport.tanDark.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: HydraReport.tanDark, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text('${level.round()}%',
                style: const TextStyle(
                    color: HydraReport.tanDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

/// Build the report PDF and open the native SHARE sheet (iOS + Android) via
/// share_plus — same plugin the app already uses for log sharing.
Future<void> shareAiReport(
  BuildContext context,
  Map<String, dynamic> report, {
  String? filename,
}) async {
  try {
    final bytes = await buildAiReportPdf(report);
    final name = filename ?? 'hydrawav-ai-report.pdf';
    // Temp dir from dart:io (no plugin needed); share_plus handles the sheet.
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Hydrawav AI Report',
      text: 'Hydrawav AI report',
    );
  } catch (e) {
    _reportPdfError(context, e);
  }
}

/// Build the report PDF and DOWNLOAD it — opens the native save dialog (SAF on
/// Android, document picker on iOS) via file_picker, which the app already uses.
Future<void> downloadAiReport(
  BuildContext context,
  Map<String, dynamic> report, {
  String? filename,
}) async {
  try {
    final bytes = await buildAiReportPdf(report);
    final name = filename ?? 'hydrawav-ai-report.pdf';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save AI report',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (context.mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report saved.')),
      );
    }
  } catch (e) {
    _reportPdfError(context, e);
  }
}

void _reportPdfError(BuildContext context, Object e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to create PDF: $e'),
        backgroundColor: ThemeConstants.error,
      ),
    );
  }
}
