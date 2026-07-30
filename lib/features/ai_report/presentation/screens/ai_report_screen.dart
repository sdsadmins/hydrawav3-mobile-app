import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../data/ai_report_pdf.dart';
import '../../domain/report_summary.dart';
import '../ai_report_style.dart';
import '../widgets/report_sections.dart';
import '../widgets/report_spec_sections.dart';
import '../widgets/sections/pad_placement_section.dart';

/// The AI report, laid out as the UI handoff spec draws it — `openReport()`,
/// `hydrawav3-ui-handoff/app.js:2781`.
///
/// The spec's report is six numbered sections (I–VI) with a copper eyebrow each
/// and a PDF / QR share / Start session row at the foot. Ours is fed by a real
/// AI response that carries far more than six sections' worth, so each numbered
/// section shows the spec's summary and the full clinical detail sits in an
/// expander beneath it — see `report_spec_sections.dart`.
///
/// The Practitioner tab is not in the spec at all, but the app has one and the
/// PDF has a practitioner variant, so it stays: same chrome, existing sections.
class AiReportScreen extends StatefulWidget {
  final Map<String, dynamic>? report;

  const AiReportScreen({super.key, this.report});

  @override
  State<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends State<AiReportScreen> {
  int _tab = 0; // 0 = Your report, 1 = Practitioner

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final raw = widget.report;
    final data = raw == null ? null : HydraReport.normalize(raw);
    final empty = data == null || data.isEmpty;
    final subtitle = raw == null ? '' : reportSubtitle(raw);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HwSpace.s4),
              child: HwBackBar(
                title: 'AI Kinetic Chain Report',
                subtitle: subtitle.isEmpty ? null : subtitle,
                onBack: () => Navigator.of(context).maybePop(),
                trailing: const HwPill('AI', tone: HwPillTone.copper),
              ),
            ),
            Expanded(
              child: empty
                  ? Center(
                      child: Text(
                        'No report available.',
                        style: TextStyle(
                            fontSize: HwType.cap, color: p.ink3),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          HwSpace.s4, 0, HwSpace.s4, HwSpace.s5),
                      children: [
                        HwSegmented(
                          labels: const ['Your report', 'Practitioner'],
                          selectedIndex: _tab,
                          onSelected: (i) => setState(() => _tab = i),
                        ),
                        const SizedBox(height: HwSpace.s4),
                        ...(_tab == 0
                            ? reportSpecSections(context, data)
                            : _practitionerSections(data)),
                        _disclaimer(p, data),
                        const SizedBox(height: HwSpace.s3),
                        _actionRow(data),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Practitioner sections — unchanged content, new chrome around it.
  List<Widget> _practitionerSections(Map<String, dynamic> data) => [
        PadPlacementSection(data),
        ...practitionerTailSections(data),
      ];

  /// The spec's centred micro line, using the backend's own disclaimer when it
  /// sent one.
  Widget _disclaimer(RefPalette p, Map<String, dynamic> data) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          disclaimerText(data),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: HwType.eyebrow, height: 1.5, color: p.ink3),
        ),
      );

  /// The spec's `.btnrow`: PDF · QR share · Start session.
  Widget _actionRow(Map<String, dynamic> data) {
    return Row(
      children: [
        Expanded(
          child: HwButton(
            label: 'PDF',
            filled: false,
            onTap: () => _pdfSheet(data),
          ),
        ),
        const SizedBox(width: HwSpace.s2),
        Expanded(
          child: HwButton(
            label: 'QR share',
            filled: false,
            // Not yet wired: the spec's share URL (hydrawav3.studio/r/{id})
            // doesn't exist, and a QR that resolves to nothing is worse than no
            // QR. Kept visible so the row matches the spec and the gap is
            // obvious rather than silently missing.
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('QR sharing is coming to this screen'),
              ),
            ),
          ),
        ),
        const SizedBox(width: HwSpace.s2),
        Expanded(
          child: HwButton(
            label: 'Start session',
            // Hands off to device selection rather than starting anything — a
            // report should never silently power a device.
            onTap: () => context.go(RoutePaths.devices),
          ),
        ),
      ],
    );
  }

  /// Save vs share, so the spec's single `PDF` button keeps both of the actions
  /// the old app bar had.
  void _pdfSheet(Map<String, dynamic> data) {
    final practitioner = _tab == 1;
    showHwSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            practitioner ? 'Practitioner report' : 'Your report',
            style: TextStyle(
              fontSize: HwType.lg,
              fontWeight: FontWeight.w700,
              color: RefPalette.of(sheetContext).ink,
            ),
          ),
          const SizedBox(height: HwSpace.s4),
          HwButton(
            label: 'Save to files',
            onTap: () {
              Navigator.pop(sheetContext);
              downloadAiReport(context, data, practitioner: practitioner);
            },
          ),
          const SizedBox(height: HwSpace.s2),
          HwButton(
            label: 'Share',
            filled: false,
            onTap: () {
              Navigator.pop(sheetContext);
              shareAiReport(context, data, practitioner: practitioner);
            },
          ),
          HwSkipLink(
            label: 'Cancel',
            onTap: () => Navigator.pop(sheetContext),
          ),
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
