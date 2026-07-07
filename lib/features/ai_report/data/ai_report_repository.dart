import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/exceptions.dart';
import '../../clients/domain/client_model.dart';
import '../../intake/domain/intake_models.dart';
import '../domain/ai_report_models.dart';
import 'ai_report_remote_source.dart';

final aiReportRepositoryProvider = Provider<AiReportRepository>((ref) {
  return AiReportRepository(ref.read(aiReportRemoteSourceProvider));
});

/// Drives the queued AI report flow (web parity):
/// 1) `POST ai/analyze` (with the live system prompt) → job id
/// 2) poll `GET ai/analyze/:id` until completed (~3-5 min)
/// The backend queue processor persists the report itself on completion, so we
/// do NOT persist it again here (that created duplicate reports).
class AiReportRepository {
  final AiReportRemoteSource _remote;

  AiReportRepository(this._remote);

  static const _pollInterval = Duration(seconds: 5);
  static const _maxPolls = 72; // ~6 minutes

  /// The live analysis system prompt, fetched once and reused. The web sends
  /// this with every analyze call; without it the backend uses an older default
  /// prompt that can emit non-numeric fields (e.g. age "not provided") the
  /// AiReport schema rejects.
  String? _cachedSystemPrompt;

  Future<String> _liveSystemPrompt() async {
    final cached = _cachedSystemPrompt;
    if (cached != null && cached.isNotEmpty) return cached;
    final prompt = await _remote.liveAnalysisPrompt();
    if (prompt.isNotEmpty) _cachedSystemPrompt = prompt;
    return prompt;
  }

  Future<Map<String, dynamic>> generate({
    required GuidedAssessmentData intake,
    required Client? client,
    required bool isGuest,
    required int organizationId,
    String? userId,
    String aiProvider = 'anthropic',
    void Function(String status)? onStatus,
  }) async {
    final intakeData = intake.toPatientIntakeInput(client);

    // Phase 1 — enqueue. Send the live analysis prompt as `customSystemPrompt`
    // (web parity): without it the backend's fallback prompt can produce
    // fields the schema rejects (e.g. guest age "not provided" → Cast to Number
    // failed). Best-effort — if the prompt can't be fetched, proceed without.
    onStatus?.call('analyzing');
    final systemPrompt = await _liveSystemPrompt();
    final started = await _remote.analyze({
      'intakeData': intakeData,
      if (systemPrompt.isNotEmpty) 'customSystemPrompt': systemPrompt,
      'provider': aiProvider,
      'organizationId': organizationId,
      if (!isGuest && client != null) 'clientId': client.id,
      'guestMode': isGuest,
    });

    // Some deployments return the result inline; otherwise poll the job.
    AnalysisStatus current = started;
    if (!current.isTerminal && current.id.isNotEmpty) {
      for (var i = 0; i < _maxPolls && !current.isTerminal; i++) {
        await Future.delayed(_pollInterval);
        current = await _remote.status(current.id);
        onStatus?.call(current.status);
      }
    }

    if (current.isFailed) {
      throw ServerException(current.error ?? 'AI analysis failed');
    }
    final result = current.result;
    if (result == null) {
      throw const ServerException(
          'AI analysis timed out. Please try again in a few minutes.');
    }

    // The backend queue processor already saves the report (keyed by the
    // client's ObjectId) when the job completes — so we must NOT persist it
    // again here, or each generation creates a SECOND doc and the client's
    // report list shows every report twice.
    onStatus?.call('completed');
    return result;
  }

  Future<Map<String, dynamic>?> recent({
    String? userId,
    int? organizationId,
  }) =>
      _remote.recent(userId: userId, organizationId: organizationId);

  Future<List<Map<String, dynamic>>> list({
    String? userId,
    int? organizationId,
    int page = 1,
    int limit = 10,
  }) =>
      _remote.list(
        userId: userId,
        organizationId: organizationId,
        page: page,
        limit: limit,
      );

  Future<Map<String, dynamic>?> getById(String id) => _remote.getById(id);
}
