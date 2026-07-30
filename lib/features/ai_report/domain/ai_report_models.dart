/// Status of a queued AI analysis job (`GET ai/analyze/:id` / the `POST`
/// response). `result` holds the full AnalysisOutput once `status == completed`.
class AnalysisStatus {
  final String id;
  final String status; // pending | processing | completed | failed
  final Map<String, dynamic>? result;
  final String? error;

  const AnalysisStatus({
    required this.id,
    required this.status,
    this.result,
    this.error,
  });

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isTerminal => isCompleted || isFailed;

  factory AnalysisStatus.fromJson(Map<String, dynamic> j) {
    final res = j['result'];

    // Some backends (and the web `analyzePatientIntake`) return the full
    // AnalysisOutput INLINE as the response body — no { id, status, result }
    // job envelope. Detect that shape via its required sections so a finished
    // analysis isn't misread as a still-pending job and wrongly surfaced as
    // "AI analysis timed out".
    final isInlineResult = res is! Map &&
        (j.containsKey('personal_snapshot') ||
            j.containsKey('clinical_insight_snapshot') ||
            j.containsKey('kinetic_chain_pattern_a'));

    return AnalysisStatus(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      status:
          (j['status'] ?? (isInlineResult ? 'completed' : 'pending')).toString(),
      result: res is Map
          ? Map<String, dynamic>.from(res)
          : (isInlineResult ? Map<String, dynamic>.from(j) : null),
      error: j['error']?.toString(),
    );
  }
}

// `AiReportView` used to live here — a loose accessor over the raw report map.
// It was never referenced: every section widget reads the map directly, and the
// content decisions it was reaching for now live in `domain/report_summary.dart`
// (shared with the PDF). Removed rather than left as a second, unused way to
// read the same data.
