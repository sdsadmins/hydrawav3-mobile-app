import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/recovery_engine_models.dart';

final recoveryEngineRemoteSourceProvider =
    Provider<RecoveryEngineRemoteSource>((ref) {
  return RecoveryEngineRemoteSource(ref.read(nodeDioProvider));
});

/// The cutover verdict AND the two payloads it authorises, as one value.
///
/// Bundled deliberately. A generation is a SET — screen, catalogue and resolve —
/// and handing them out separately is what let the web ask v3's questions and
/// resolve against v2. One provider means a caller cannot hold a screen from one
/// library and a region list from another.
///
/// Fetched once per app run: it describes the deployment, not the user or the
/// session. `keepAlive` because the assistant screen is disposed on every tab
/// change, and the intake read is expensive.
final recoveryDispatchProvider = FutureProvider<RecoveryDispatch>((ref) async {
  ref.keepAlive();
  return ref.read(recoveryEngineRemoteSourceProvider).dispatch();
});

/// The recovery ENGINE — the chip flow's data source, and the counterpart to
/// `PerformanceRemoteSource` on the performance side. Web parity:
/// `RecoveryEngineFlow.jsx` + `engine/recoveryGeneration.js`.
class RecoveryEngineRemoteSource {
  final Dio _dio;
  RecoveryEngineRemoteSource(this._dio);

  /// Ask which library is serving, then fetch that library's screen and
  /// catalogue — never one from each.
  ///
  /// A FAILED CUTOVER IS AN ERROR, NOT A v2. Treating "I could not find out" as
  /// v2 pins the whole session to a generation nobody chose, with no message to
  /// say so, and the wrong answer comes back looking exactly like a right one.
  Future<RecoveryDispatch> dispatch() async {
    final Map<String, dynamic> verdict;
    try {
      final res = await _dio.get(
        ApiEndpoints.recoveryCutover,
        options: Options(receiveTimeout: AppConstants.padChatTimeout),
      );
      if (res.data is! Map) {
        throw ServerException(_notAnEnvelope('cutover verdict', res.data));
      }
      verdict = Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw ServerException(
        _message(e) ??
            'Couldn’t find out which recovery library is serving. '
                'The placement can’t be resolved until the server says.',
        statusCode: e.response?.statusCode,
      );
    }

    final generation = RecoveryGeneration.readFrom(verdict);
    if (generation == null) {
      throw ServerException(
        'The cutover didn’t name a recovery library this app knows '
        '(got "${verdict['generation']}").',
      );
    }

    // ONE GENERATION, EVERY CALL — or the answers cannot match the questions.
    final results = await Future.wait([
      _screen(generation),
      _catalog(generation),
    ]);

    return RecoveryDispatch(
      generation: generation,
      reason: (verdict['reason'] ?? '').toString(),
      servingNothing: verdict['serving_nothing'] == true,
      // The count for THIS generation. An empty catalogue next to a non-zero
      // count is the "present and being refused" case, which is a different
      // fault from "nothing authored" — see RecoveryDispatch.emptyCatalogReason.
      livePoints: _int(
          verdict[generation.isV3 ? 'v3LivePoints' : 'v2LivePoints']),
      screen: results[0] as RecoverySafetyScreen,
      catalog: results[1] as RecoveryIntakeCatalog,
    );
  }

  Future<RecoverySafetyScreen> _screen(RecoveryGeneration generation) async {
    try {
      final res = await _dio.get(
        generation.screenPath,
        options: Options(receiveTimeout: AppConstants.padChatTimeout),
      );
      if (res.data is! Map) return const RecoverySafetyScreen();
      return RecoverySafetyScreen.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException {
      // The screen is not a UI gate, so a failure here must not close the flow:
      // the ENGINE runs the universal pre-gate on every resolve regardless, and
      // the disclaimer falls back to its generic line. What is lost is the
      // per-question `redFlags` map, which goes out empty — "not asked", which
      // is the truth when the screen never loaded.
      return const RecoverySafetyScreen();
    }
  }

  /// `GET …/intake` (v3) or `GET …/catalog` (v2). Two shapes, read the way each
  /// is actually sent — neither is a fallback for the other.
  Future<RecoveryIntakeCatalog> _catalog(RecoveryGeneration generation) async {
    try {
      final res = await _dio.get(
        generation.catalogPath,
        // NOT the cheap metadata read it looks like. v3's intake fetches the
        // whole live corpus and derives the catalogue from it — deliberately, so
        // the regions offered and the regions the resolve can serve come from
        // one query — and measures around 40 s against a dev tunnel, well past
        // the 30 s default. Timing out empties the first chip row, which reads
        // as "the library is empty" rather than "it is slow".
        options: Options(receiveTimeout: AppConstants.padChatTimeout),
      );
      final data = res.data;
      if (data is! Map) {
        throw ServerException(_notAnEnvelope('catalogue', data));
      }
      final json = Map<String, dynamic>.from(data);
      return generation.isV3
          ? RecoveryIntakeCatalog.fromV3Json(json)
          : RecoveryIntakeCatalog.fromV2Json(json);
    } on DioException catch (e) {
      throw ServerException(
        _message(e) ?? 'Couldn’t load the recovery areas',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// The pad set.
  ///
  /// EVERY FIELD NAME HERE IS THE CONTRACT. v3's DTO declares one canonical
  /// spelling per field and rejects anything else with a 400 — there are
  /// deliberately no aliases, because a tolerated second spelling is how the
  /// backend once served a placement computed without the referral it was sent.
  /// `referral_target` is snake and `movementTest` is camel because that is what
  /// each is called there; they are not normalised to one style.
  ///
  /// [movementTest], [aspect] and [referralSide] are v3-ONLY and are dropped for
  /// v2, whose DTO is narrower and would 400 on them. Dropping rather than
  /// erroring is right because nothing in a v2 intake can set them: v2 offers no
  /// aspects and records no chosen test.
  ///
  /// A refer-out is a 200 with no sets, not an error — check
  /// [RecoveryPlacement.hasPads], never the status code.
  Future<RecoveryPlacement> resolve({
    required RecoveryGeneration generation,
    required String goal,
    required String region,
    String? regionLabel,
    String? side,
    String? movementTest,
    bool movementTestSkipped = false,
    String? aspect,
    String? referralTarget,
    String? referralSide,
    List<String> symptomQuality = const [],
    String? acuity,
    String? query,
    Map<String, dynamic> redFlags = const {},
    bool nerveReferral = false,
    bool motorWeakness = false,
    bool bladderBowelChange = false,
    String sessionId = '',
  }) async {
    final v3 = generation.isV3;
    final body = <String, dynamic>{
      'goal': goal,
      'region': region,
      if (_has(side)) 'side': side,
      if (movementTestSkipped) 'movementTestSkipped': true,
      if (v3 && _has(movementTest)) 'movementTest': movementTest,
      if (v3 && _has(aspect)) 'aspect': aspect,
      if (_has(referralTarget)) 'referral_target': referralTarget,
      // Only alongside a target: a side with no destination is not a statement
      // about anything, and the DTO rejects the incoherent pair rather than
      // silently ignoring half of it.
      if (v3 && _has(referralTarget) && _has(referralSide))
        'referral_side': referralSide,
      if (symptomQuality.isNotEmpty) 'symptom_quality': symptomQuality,
      if (_has(acuity)) 'acuity': acuity,
      if (_has(query)) 'query': query,
      // A practitioner-marked nerve-referral pattern IS the case's condition
      // family, so it is passed through for SELECTION as well as to the gate.
      // Without this the flag only fed the radicular gate and a genuine
      // nerve-referral presentation could never reach its authored point.
      if (nerveReferral) 'condition_family': 'nerve_referral',
      if (nerveReferral) 'nerveReferral': true,
      if (motorWeakness) 'motorWeakness': true,
      if (bladderBowelChange) 'bladderBowelChange': true,
      // Every authored flag, answered NO — not `{}`, which says "not asked".
      if (redFlags.isNotEmpty) 'redFlags': redFlags,
      // The safety lock is per session, so a tier-1 block in one turn has to
      // stick in the next.
      if (sessionId.trim().isNotEmpty) 'sessionId': sessionId.trim(),
    };

    try {
      final res = await _dio.post(
        generation.resolvePath,
        data: body,
        options: Options(
          receiveTimeout: AppConstants.padChatTimeout,
          sendTimeout: AppConstants.padChatTimeout,
        ),
      );
      final data = res.data;
      if (data is! Map) {
        throw ServerException(_notAnEnvelope('placement', data));
      }
      return RecoveryPlacement.fromJson(
        Map<String, dynamic>.from(data),
        regionLabel: regionLabel,
      );
    } on DioException catch (e) {
      // A gate block can arrive as a 4xx carrying the refusal envelope. That is
      // an answer — deliver it — where a 400 from the strict DTO is a client bug
      // and must surface as one.
      final data = e.response?.data;
      if (data is Map && data['safety'] is Map) {
        return RecoveryPlacement.fromJson(
          Map<String, dynamic>.from(data),
          regionLabel: regionLabel,
        );
      }
      throw ServerException(
        _message(e) ?? 'Couldn’t reach the recovery engine',
        statusCode: e.response?.statusCode,
      );
    }
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// The server's own words, including the ValidationPipe's field-level list —
  /// without it a 400 from a mis-spelled field reads exactly like a network
  /// failure and there is nothing to act on.
  static String? _message(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final m = data['message'];
      if (m is List && m.isNotEmpty) return m.join('; ');
      final s = m?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static String _notAnEnvelope(String what, dynamic data) {
    final preview = data.toString();
    return 'The recovery engine didn’t return a $what. Check that '
        'recovery-engine-v3 is deployed at this base URL. '
        'Got: ${preview.substring(0, preview.length.clamp(0, 120))}';
  }
}
