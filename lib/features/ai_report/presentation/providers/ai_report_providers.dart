import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../intake/domain/intake_models.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../data/ai_report_repository.dart';

enum AiReportPhase { analyzing, processing, persisting, done, error }

/// One in-flight (or finished) background report generation. Multiple can run
/// concurrently — each job updates only its own entry by [id] (web parity with
/// the session-manager `aiJobs` array + header "Generating N reports" pill).
class AiReportJob {
  final String id;
  final String label; // client / guest name, shown in the pill
  final AiReportPhase phase;
  final String? message; // error text when phase == error
  final Map<String, dynamic>? report; // result when phase == done

  const AiReportJob({
    required this.id,
    required this.label,
    required this.phase,
    this.message,
    this.report,
  });

  bool get isBusy =>
      phase == AiReportPhase.analyzing ||
      phase == AiReportPhase.processing ||
      phase == AiReportPhase.persisting;

  AiReportJob copyWith({
    AiReportPhase? phase,
    String? message,
    Map<String, dynamic>? report,
  }) {
    return AiReportJob(
      id: id,
      label: label,
      phase: phase ?? this.phase,
      message: message,
      report: report ?? this.report,
    );
  }
}

/// Tracks all background report generations as a list so the UI never blocks
/// and the practitioner can start another while one is running.
class AiReportGenerationNotifier extends StateNotifier<List<AiReportJob>> {
  final Ref _ref;
  int _seq = 0;

  AiReportGenerationNotifier(this._ref) : super(const []);

  bool get isBusy => state.any((j) => j.isBusy);

  /// The most recently completed report (for "view latest" shortcuts).
  Map<String, dynamic>? get lastDoneReport {
    for (final j in state.reversed) {
      if (j.phase == AiReportPhase.done && j.report != null) return j.report;
    }
    return null;
  }

  /// Remove a single finished (or in-flight) job from the list.
  void dismiss(String id) =>
      state = state.where((j) => j.id != id).toList(growable: false);

  /// Clear every job (used by the banner's clear-all / on sign-out).
  void reset() => state = const [];

  /// Validate the current intake/client/org and kick off a background
  /// generation. Returns an error string when nothing could be queued, or null
  /// when a job was started. The heavy work runs detached (fire-and-forget) so
  /// the UI stays free and several jobs can run at once.
  String? startGenerate() {
    final auth = _ref.read(authStateProvider);
    final orgId = int.tryParse(auth.selectedOrgId ?? '');
    if (orgId == null) {
      return 'Select an organization before generating a report.';
    }

    final mode = _ref.read(sessionClientModeProvider);
    final isGuest = mode == ClientMode.guest;
    final client = isGuest ? null : _ref.read(selectedClientProvider);
    if (!isGuest && client == null) {
      return 'Select a client before generating a report.';
    }

    // Snapshot the intake now — the user may edit it or switch clients while
    // this job runs in the background.
    final intake = _ref.read(guidedAssessmentProvider);
    final label =
        isGuest ? 'Guest report' : (client?.displayName ?? 'Client report');
    final id = 'job_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

    state = [
      ...state,
      AiReportJob(id: id, label: label, phase: AiReportPhase.analyzing),
    ];

    _run(
      id: id,
      intake: intake,
      client: client,
      isGuest: isGuest,
      orgId: orgId,
      userId: auth.user?.id,
    );
    return null;
  }

  Future<void> _run({
    required String id,
    required GuidedAssessmentData intake,
    required Client? client,
    required bool isGuest,
    required int orgId,
    String? userId,
  }) async {
    try {
      final report = await _ref.read(aiReportRepositoryProvider).generate(
            intake: intake,
            client: client,
            isGuest: isGuest,
            organizationId: orgId,
            userId: userId,
            onStatus: (s) {
              final lower = s.toLowerCase();
              final phase = switch (lower) {
                'analyzing' || 'pending' => AiReportPhase.analyzing,
                'processing' => AiReportPhase.processing,
                'persisting' => AiReportPhase.persisting,
                _ => null,
              };
              if (phase != null) {
                _patch(id, (j) => j.copyWith(phase: phase));
              }
            },
          );
      _patch(id, (j) => j.copyWith(phase: AiReportPhase.done, report: report));
    } catch (e) {
      _patch(
        id,
        (j) => j.copyWith(phase: AiReportPhase.error, message: e.toString()),
      );
    }
  }

  void _patch(String id, AiReportJob Function(AiReportJob) f) {
    if (!mounted) return;
    state = [
      for (final j in state)
        if (j.id == id) f(j) else j,
    ];
  }
}

final aiReportGenerationProvider =
    StateNotifierProvider<AiReportGenerationNotifier, List<AiReportJob>>(
  (ref) => AiReportGenerationNotifier(ref),
);

/// Whether any report is currently generating — for gating dependent buttons
/// (e.g. "View report" / "3D pattern") without blocking the generate flow.
final aiReportBusyProvider = Provider<bool>(
  (ref) => ref.watch(aiReportGenerationProvider).any((j) => j.isBusy),
);
