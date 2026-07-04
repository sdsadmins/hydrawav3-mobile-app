import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/exceptions.dart';
import '../../clients/domain/client_model.dart';
import '../../intake/domain/intake_models.dart';
import '../domain/ai_report_models.dart';
import 'ai_report_remote_source.dart';

final aiReportRepositoryProvider = Provider<AiReportRepository>((ref) {
  return AiReportRepository(ref.read(aiReportRemoteSourceProvider));
});

/// Drives the two-phase, queued AI report flow (web parity):
/// 1) `POST ai/analyze` → job id
/// 2) poll `GET ai/analyze/:id` until completed (~3-5 min)
/// 3) `POST ai-reports` with the mapped result (guest vs client branch)
class AiReportRepository {
  final AiReportRemoteSource _remote;

  AiReportRepository(this._remote);

  static const _pollInterval = Duration(seconds: 5);
  static const _maxPolls = 72; // ~6 minutes

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

    // Phase 1 — enqueue.
    onStatus?.call('analyzing');
    final started = await _remote.analyze({
      'intakeData': intakeData,
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

    // Phase 3 — persist.
    onStatus?.call('persisting');
    final body = _buildPersistBody(
      result: result,
      intakeData: intakeData,
      isGuest: isGuest,
      organizationId: organizationId,
      userId: userId,
      clientId: client?.id,
      aiProvider: aiProvider,
    );
    await _remote.persist(body);

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

  // --- Mapping helpers (mirror web `createAIReport`) ---

  Map<String, dynamic> _buildPersistBody({
    required Map<String, dynamic> result,
    required Map<String, dynamic> intakeData,
    required bool isGuest,
    required int organizationId,
    String? userId,
    String? clientId,
    required String aiProvider,
  }) {
    Map<String, dynamic> obj(String key) {
      final v = result[key];
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    }

    // why_this_pattern_matters is a string in the AI output but an object in
    // the DTO — wrap it.
    Map<String, dynamic> whyMatters() {
      final v = result['why_this_pattern_matters'];
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is String) return {'explanation': v};
      return <String, dynamic>{};
    }

    final personalSnapshot = obj('personal_snapshot');

    // `age` MUST be a Number for the backend AiReport schema. The AI returns
    // "Not provided" (string) when age is unknown, which makes Mongoose throw
    // `Cast to Number failed for value "not provided"`. Coerce a valid age to
    // a num, otherwise drop the field entirely. This runs in BOTH guest and
    // client mode — the web cleans age in both branches (action.ts
    // createAIReport), and a client with no recorded age hits the same error.
    final rawAge = personalSnapshot['age'];
    final numAge =
        rawAge is num ? rawAge : num.tryParse(rawAge?.toString() ?? '');
    if (numAge != null && numAge > 0) {
      personalSnapshot['age'] = numAge;
    } else {
      personalSnapshot.remove('age');
    }

    if (isGuest) {
      // Guest reports also strip name/gender that were never provided
      // (web guest cleaning) — no client history is attached.
      final gender = personalSnapshot['gender'];
      if (gender is! String ||
          gender.trim().isEmpty ||
          gender.toLowerCase() == 'not provided') {
        personalSnapshot.remove('gender');
      }
      final name = personalSnapshot['name'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.toLowerCase() == 'not provided') {
        personalSnapshot.remove('name');
      }
    }

    final loadVsRecovery = _coerceLoadVsRecovery(obj('load_vs_recovery_profile'));

    return {
      // Identity branch.
      if (isGuest) ...{
        'guestMode': 'true',
        'organizationId': organizationId,
      } else ...{
        // A client report is stored under the CLIENT's ObjectId. The backend
        // validates `userId` as an ObjectId, so sending the practitioner's
        // numeric id (e.g. "662") fails with "Invalid userId format". The
        // acting practitioner (createdBy) is derived server-side from the token.
        if (clientId != null) 'userId': clientId,
        if (clientId != null) 'clientId': clientId,
        'organizationId': organizationId,
      },
      'aiProvider': aiProvider,
      'schema_version':
          (result['schema_version'] ?? '2.0').toString(),
      'report_type': (result['report_type'] ??
              'general_mobility_kinetic_chain')
          .toString(),
      'intakeData': intakeData,
      // Required report sections (default to {} when missing).
      'personal_snapshot': personalSnapshot,
      'clinical_insight_snapshot': obj('clinical_insight_snapshot'),
      'movement_mobility_summary': obj('movement_mobility_summary'),
      'kinetic_chain_pattern_a': obj('kinetic_chain_pattern_a'),
      'kinetic_chain_pattern_b': obj('kinetic_chain_pattern_b'),
      'load_vs_recovery_profile': loadVsRecovery,
      'lifestyle_contributors': obj('lifestyle_contributors'),
      'at_home_mobility_support': obj('at_home_mobility_support'),
      'why_this_pattern_matters': whyMatters(),
      if (result['practitioner_questions'] is List)
        'practitioner_questions': result['practitioner_questions'],
      'practitioner_hand_off':
          (result['practitioner_hand_off'] ?? '').toString(),
      'practitioner_notes_template': obj('practitioner_notes_template'),
      'next_steps': obj('next_steps'),
      'disclaimer': (result['disclaimer'] ?? '').toString(),
    };
  }

  /// Backend requires numeric `estimated_daily_hours` / `daily_load_hours`.
  Map<String, dynamic> _coerceLoadVsRecovery(Map<String, dynamic> lvr) {
    num toNum(dynamic v) {
      if (v is num) return v < 0 ? 0 : v;
      final parsed = num.tryParse(v?.toString() ?? '');
      if (parsed == null || parsed < 0) return 0;
      return parsed;
    }

    final exposure = lvr['positioning_exposure'] is Map
        ? Map<String, dynamic>.from(lvr['positioning_exposure'] as Map)
        : <String, dynamic>{};
    exposure['estimated_daily_hours'] =
        toNum(exposure['estimated_daily_hours']);

    final balance = lvr['load_recovery_balance'] is Map
        ? Map<String, dynamic>.from(lvr['load_recovery_balance'] as Map)
        : <String, dynamic>{};
    balance['daily_load_hours'] = toNum(balance['daily_load_hours']);

    return {
      ...lvr,
      'positioning_exposure': exposure,
      'load_recovery_balance': balance,
    };
  }
}
