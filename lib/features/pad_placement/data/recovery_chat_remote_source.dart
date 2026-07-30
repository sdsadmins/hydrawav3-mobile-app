import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/recovery_chat_models.dart';

final recoveryChatRemoteSourceProvider =
    Provider<RecoveryChatRemoteSource>((ref) {
  return RecoveryChatRemoteSource(ref.read(nodeDioProvider));
});

/// `POST recovery-chat/message` — the recovery engine's conversational front
/// door, the counterpart to `PerformanceRemoteSource.chatMessage`.
///
/// The engine runs its universal safety gate BEFORE anything else, so a normal
/// 200 can still be a refusal: check [RecoveryChatReply.isRefusal] before
/// treating a reply as a placement. The user is resolved server-side from the
/// token and is never sent in the body.
class RecoveryChatRemoteSource {
  final Dio _dio;
  RecoveryChatRemoteSource(this._dio);

  /// [slots] is the conversation memory — thread the previous reply's slots
  /// back every turn, otherwise each message starts from a blank region.
  /// [redFlags] is the recovery name for screen answers already collected.
  Future<RecoveryChatReply> message({
    required String message,
    required String sessionId,
    Map<String, dynamic> slots = const {},
    Map<String, dynamic> redFlags = const {},
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.recoveryChat,
        data: {
          'message': message,
          if (sessionId.trim().isNotEmpty) 'sessionId': sessionId,
          'slots': slots,
          'redFlags': redFlags,
        },
        // A turn embeds the message and reads the corpus; the 30 s Dio default
        // is well under what it takes.
        options: Options(
          receiveTimeout: AppConstants.padChatTimeout,
          sendTimeout: AppConstants.padChatTimeout,
        ),
      );
      final data = res.data;
      if (data is Map) {
        return RecoveryChatReply.fromJson(Map<String, dynamic>.from(data));
      }
      // Not a chat envelope at all — a dev tunnel interstitial or a wrong base
      // URL. Say so rather than showing an empty bubble.
      final preview = data.toString();
      throw ServerException(
        'The recovery assistant didn’t return a chat reply. Check that the '
        'recovery-chat service is deployed at this base URL. '
        'Got: ${preview.substring(0, preview.length.clamp(0, 120))}',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      // A gate block can arrive as a 4xx with the refusal envelope in the body;
      // that is an answer, not a transport failure.
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final reply = RecoveryChatReply.fromJson(map);
        if (reply.isRefusal && reply.reply.trim().isNotEmpty) return reply;
        throw ServerException(
          map['message']?.toString() ?? 'Couldn’t reach the recovery assistant',
          statusCode: e.response?.statusCode,
        );
      }
      throw ServerException(
        'Couldn’t reach the recovery assistant',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
