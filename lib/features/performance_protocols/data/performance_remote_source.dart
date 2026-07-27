import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/performance_models.dart';

final performanceRemoteSourceProvider =
    Provider<PerformanceRemoteSource>((ref) {
  return PerformanceRemoteSource(ref.read(nodeDioProvider));
});

/// The performance-protocols client — both ways in to a pad set.
///
/// The three catalogue metadata calls are cheap and ungated. [chain], [query]
/// and [chatMessage] all go through the service's `safety.guard()`, so each can
/// come back as a refusal envelope; that is a normal response, not an error.
///
/// `sessionId` is passed on every call because a tier-1 safety lock is per
/// session. The user id is never sent — the server resolves it from the token.
class PerformanceRemoteSource {
  final Dio _dio;
  PerformanceRemoteSource(this._dio);

  Future<List<Discipline>> listDisciplines({String? sessionId}) async {
    final data = await _get(
      sessionId == null || sessionId.isEmpty
          ? ApiEndpoints.perfDisciplines
          : '${ApiEndpoints.perfDisciplines}?sessionId=${Uri.encodeQueryComponent(sessionId)}',
      'Couldn’t load disciplines',
    );
    _requireList(data, 'disciplines');
    return Discipline.listFrom(data);
  }

  Future<List<RoleOption>> listRoles(
    String discipline, {
    String? sessionId,
  }) async {
    final data = await _get(
      ApiEndpoints.perfRoles(discipline, sessionId: sessionId),
      'Couldn’t load positions',
    );
    _requireList(data, 'positions');
    return RoleOption.listFrom(data);
  }

  /// The chain MENU for a position — unranked, no scores.
  Future<List<ChainSummary>> listChains(
    String discipline,
    String role, {
    String? subtype,
    String? sessionId,
  }) async {
    final data = await _get(
      ApiEndpoints.perfChains(discipline, role,
          subtype: subtype, sessionId: sessionId),
      'Couldn’t load chains',
    );
    _requireList(data, 'chains');
    return ChainSummary.listFrom(data);
  }

  /// Guards the difference between "the catalogue is empty" and "that wasn't a
  /// catalogue response". Only the first is a real, reportable emptiness; the
  /// second means the service isn't answering here (wrong base URL, a dev tunnel
  /// serving its HTML interstitial, a renamed field) and must not be dressed up
  /// as "nothing is authored yet".
  static void _requireList(dynamic data, String what) {
    if (rowsOrNull(data) != null) return;
    final preview = data.toString();
    throw ServerException(
      'The server didn’t return a $what list. Check that the '
      'performance-protocols service is deployed at this base URL. '
      'Got: ${preview.substring(0, preview.length.clamp(0, 120))}',
    );
  }

  /// ★ The pad set. Gated — check [PadSetPayload.isRefusal] before rendering pads.
  Future<PadSetPayload> chain({
    required String discipline,
    required String role,
    required String chainId,
    required String sessionId,
    String? subtype,
  }) async {
    final data = await _get(
      ApiEndpoints.perfChain(discipline, role, chainId,
          subtype: subtype, sessionId: sessionId),
      'Couldn’t load the pad set',
    );
    return PadSetPayload.fromJson(_asMap(data));
  }

  /// Ranked chains + their pads over the `pad_protocols` corpus.
  Future<List<RankedChain>> query({
    required String query,
    required String sessionId,
    String? role,
    String? subtype,
    int topK = 3,
    Map<String, dynamic> screenAnswers = const {},
  }) async {
    final data = await _post(
      ApiEndpoints.perfQuery,
      {
        'query': query,
        'role': role,
        'subtype': subtype,
        'topK': topK,
        'sessionId': sessionId,
        'screenAnswers': screenAnswers,
      },
      'Couldn’t run that search',
    );
    final map = _asMap(data);
    final results = RankedChain.listFrom(map['results'] ?? map['data'] ?? data);
    if (results.isEmpty) {
      // Either genuinely nothing matched or the guard blocked it. Surface the
      // refusal text so the caller can say which.
      final refusal = PadSetPayload.refusalMessageFrom(map);
      if (refusal != null) {
        throw PerformanceRefusal(refusal);
      }
    }
    return results;
  }

  /// The conversational wrapper over [query]. Thread [slots] back every turn —
  /// that is the conversation memory.
  Future<ChatReply> chatMessage({
    required String message,
    required String sessionId,
    Map<String, dynamic> slots = const {},
    Map<String, dynamic> screenAnswers = const {},
  }) async {
    final data = await _post(
      ApiEndpoints.perfChat,
      {
        'message': message,
        'sessionId': sessionId,
        'slots': slots,
        'screenAnswers': screenAnswers,
      },
      'Couldn’t reach the assistant',
    );
    return ChatReply.fromJson(_asMap(data));
  }

  // ── transport ──────────────────────────────────────────────────────────────

  Future<dynamic> _get(String path, String fallbackMessage) async {
    try {
      final res = await _dio.get(path);
      return res.data;
    } on DioException catch (e) {
      throw _toException(e, fallbackMessage);
    }
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body,
    String fallbackMessage,
  ) async {
    try {
      final res = await _dio.post(
        path,
        data: {...body}..removeWhere((_, v) => v == null),
      );
      return res.data;
    } on DioException catch (e) {
      throw _toException(e, fallbackMessage);
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Exception _toException(DioException e, String fallback) {
    final data = e.response?.data;
    // A guard block can arrive as a 4xx with the refusal in the body.
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final refusal = PadSetPayload.refusalMessageFrom(map);
      final status = e.response?.statusCode ?? 0;
      if (refusal != null && status >= 400 && status < 500) {
        return PerformanceRefusal(refusal);
      }
      return ServerException(
        map['message']?.toString() ?? fallback,
        statusCode: status == 0 ? null : status,
      );
    }
    return ServerException(fallback, statusCode: e.response?.statusCode);
  }
}

/// A safety-guard block, not a transport failure. Render the message; never
/// render pads alongside it.
class PerformanceRefusal implements Exception {
  final String message;
  const PerformanceRefusal(this.message);

  @override
  String toString() => message;
}
