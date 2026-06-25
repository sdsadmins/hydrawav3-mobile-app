import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../data/ai_report_repository.dart';

enum AiReportPhase { idle, analyzing, processing, persisting, done, error }

class AiReportGenerationState {
  final AiReportPhase phase;
  final String? message;
  final Map<String, dynamic>? report;

  const AiReportGenerationState({
    this.phase = AiReportPhase.idle,
    this.message,
    this.report,
  });

  bool get isBusy =>
      phase == AiReportPhase.analyzing ||
      phase == AiReportPhase.processing ||
      phase == AiReportPhase.persisting;

  AiReportGenerationState copyWith({
    AiReportPhase? phase,
    String? message,
    Map<String, dynamic>? report,
  }) {
    return AiReportGenerationState(
      phase: phase ?? this.phase,
      message: message,
      report: report ?? this.report,
    );
  }
}

class AiReportGenerationNotifier
    extends StateNotifier<AiReportGenerationState> {
  final Ref _ref;

  AiReportGenerationNotifier(this._ref)
      : super(const AiReportGenerationState());

  void reset() => state = const AiReportGenerationState();

  /// Generate (and persist) an AI report for the current intake. Returns the
  /// AnalysisOutput map on success, or null on failure (state holds the error).
  Future<Map<String, dynamic>?> generate() async {
    final auth = _ref.read(authStateProvider);
    final orgIdRaw = auth.selectedOrgId;
    final orgId = int.tryParse(orgIdRaw ?? '');
    if (orgId == null) {
      state = const AiReportGenerationState(
        phase: AiReportPhase.error,
        message: 'Select an organization before generating a report.',
      );
      return null;
    }

    final mode = _ref.read(sessionClientModeProvider);
    final isGuest = mode == ClientMode.guest;
    final client = isGuest ? null : _ref.read(selectedClientProvider);
    if (!isGuest && client == null) {
      state = const AiReportGenerationState(
        phase: AiReportPhase.error,
        message: 'Select a client before generating a report.',
      );
      return null;
    }

    final intake = _ref.read(guidedAssessmentProvider);

    state = const AiReportGenerationState(phase: AiReportPhase.analyzing);
    try {
      final report = await _ref.read(aiReportRepositoryProvider).generate(
            intake: intake,
            client: client,
            isGuest: isGuest,
            organizationId: orgId,
            userId: auth.user?.id,
            onStatus: (s) {
              final lower = s.toLowerCase();
              final phase = switch (lower) {
                'analyzing' || 'pending' => AiReportPhase.analyzing,
                'processing' => AiReportPhase.processing,
                'persisting' => AiReportPhase.persisting,
                _ => state.phase,
              };
              if (mounted) state = state.copyWith(phase: phase, message: null);
            },
          );
      state = AiReportGenerationState(
        phase: AiReportPhase.done,
        report: report,
      );
      return report;
    } catch (e) {
      state = AiReportGenerationState(
        phase: AiReportPhase.error,
        message: e.toString(),
      );
      return null;
    }
  }
}

final aiReportGenerationProvider = StateNotifierProvider<
    AiReportGenerationNotifier, AiReportGenerationState>(
  (ref) => AiReportGenerationNotifier(ref),
);
