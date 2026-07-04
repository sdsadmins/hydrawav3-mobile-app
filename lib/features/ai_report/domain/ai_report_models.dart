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

/// Lightweight view over an AnalysisOutput / persisted report. Sections are
/// rendered flexibly from the raw map so the UI tolerates missing fields.
class AiReportView {
  final Map<String, dynamic> data;

  const AiReportView(this.data);

  String? get string1 => _str('clinical_insight_snapshot', 'summary_statement');

  Map<String, dynamic> section(String key) {
    final v = data[key];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  String? topString(String key) {
    final v = data[key];
    if (v is String) return v;
    if (v is Map && v['explanation'] is String) {
      return v['explanation'] as String;
    }
    return null;
  }

  List<String> stringList(String key) {
    final v = data[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  String? _str(String section, String field) {
    final s = data[section];
    if (s is Map && s[field] is String) return s[field] as String;
    return null;
  }
}
