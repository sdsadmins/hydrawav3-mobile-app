import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../data/ai_report_pdf.dart';
import '../ai_report_style.dart';
import '../widgets/report_sections.dart';
import '../widgets/sections/pad_placement_section.dart';

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
              onPressed: () =>
                  shareAiReport(context, data, practitioner: _tab == 1),
            ),
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded),
              onPressed: () =>
                  downloadAiReport(context, data, practitioner: _tab == 1),
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
                ...(_tab == 0
                    ? _clientSections(data)
                    : _practitionerSections(data)),
              ],
            ),
    );
  }

  /// "Your Report" (client) sections, in web order (shared with the PDF).
  List<Widget> _clientSections(Map<String, dynamic> data) =>
      clientReportSections(data);

  /// Practitioner sections (live pad placement + the shared tail).
  List<Widget> _practitionerSections(Map<String, dynamic> data) => [
        PadPlacementSection(data),
        ...practitionerTailSections(data),
      ];

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

}

/// Build the report PDF and open the native SHARE sheet (iOS + Android) via
/// share_plus — same plugin the app already uses for log sharing.
Future<void> shareAiReport(
  BuildContext context,
  Map<String, dynamic> report, {
  String? filename,
  bool practitioner = false,
}) async {
  try {
    final bytes = await buildAiReportPdf(report, practitioner: practitioner);
    final name = filename ??
        (practitioner
            ? 'hydrawav-practitioner-report.pdf'
            : 'hydrawav-your-report.pdf');
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
  bool practitioner = false,
}) async {
  try {
    final bytes = await buildAiReportPdf(report, practitioner: practitioner);
    final name = filename ??
        (practitioner
            ? 'hydrawav-practitioner-report.pdf'
            : 'hydrawav-your-report.pdf');
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
