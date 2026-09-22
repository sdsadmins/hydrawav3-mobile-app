import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/assistant_chat_models.dart';

final assistantChatRemoteSourceProvider =
    Provider<AssistantChatRemoteSource>((ref) {
  return AssistantChatRemoteSource(ref.read(nodeDioProvider));
});

/// `POST chat` — the unified assistant route (`src/modules/pad-chat`), which
/// replaces the split `performance-chat/message` + `recovery-chat/message` calls
/// for the Assistant's typed free-text path.
///
/// The backend runs its universal safety gate before classification, so a 200
/// can still be a refusal envelope (`ok: false`, `kind: "refusal"`) — that is an
/// answer, not a transport failure. The user is resolved server-side from the
/// token and is never sent in the body.
class AssistantChatRemoteSource {
  final Dio _dio;
  AssistantChatRemoteSource(this._dio);

  /// [threadId] is the conversation handle — pass back the previous reply's
  /// `threadId` on every following turn or the backend starts a new
  /// conversation. [sessionId] keeps a per-session safety lock consistent, the
  /// same reason the other chat surfaces send it.
  Future<AssistantChatReply> send({
    required String message,
    String? sessionId,
    String? threadId,
    Map<String, dynamic>? slots,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.assistantChat,
        data: {
          'message': message,
          // ALWAYS sent, `{}` included — it is the conversation's slot memory
          // and the backend walks the performance flow (`perfAccept` →
          // `perfChain` → placement) off it. Web parity: `slots: carried`.
          'slots': slots ?? const {},
          if ((sessionId ?? '').trim().isNotEmpty) 'sessionId': sessionId,
          if ((threadId ?? '').trim().isNotEmpty) 'threadId': threadId,
        },
        // A turn is retrieval + a model round trip server-side; the 30 s Dio
        // default is well under what it takes.
        options: Options(
          receiveTimeout: AppConstants.padChatTimeout,
          sendTimeout: AppConstants.padChatTimeout,
        ),
      );
      final data = res.data;
      if (data is Map) {
        return AssistantChatReply.fromJson(Map<String, dynamic>.from(data));
      }
      // Not a chat envelope — a dev tunnel interstitial or a wrong base URL.
      final preview = data.toString();
      throw ServerException(
        'The assistant didn’t return a chat reply. Check that the chat service '
        'is deployed at this base URL. '
        'Got: ${preview.substring(0, preview.length.clamp(0, 120))}',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      // A gate block can arrive as a 4xx carrying the refusal envelope; that is
      // an answer, not a failure.
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final reply = AssistantChatReply.fromJson(map);
        if (reply.reply.trim().isNotEmpty) return reply;
        throw ServerException(
          map['message']?.toString() ?? 'Couldn’t reach the assistant',
          statusCode: e.response?.statusCode,
        );
      }
      throw ServerException(
        'Couldn’t reach the assistant',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
