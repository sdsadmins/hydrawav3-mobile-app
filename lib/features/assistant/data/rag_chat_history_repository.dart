import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// One row of `GET rag-chat-history/conversations`.
class RagConversationSummary {
  final String conversationId;
  final String lastMessage;
  final String lastRole;
  final DateTime? lastAt;
  final int messageCount;

  const RagConversationSummary({
    required this.conversationId,
    required this.lastMessage,
    required this.lastRole,
    required this.lastAt,
    required this.messageCount,
  });

  factory RagConversationSummary.fromJson(Map<String, dynamic> j) =>
      RagConversationSummary(
        conversationId: (j['conversationId'] ?? '').toString(),
        lastMessage: (j['lastMessage'] ?? '').toString(),
        lastRole: (j['lastRole'] ?? '').toString(),
        lastAt: DateTime.tryParse((j['lastAt'] ?? '').toString()),
        messageCount: (j['messageCount'] as num?)?.toInt() ?? 0,
      );
}

/// One saved message of a conversation.
class RagMessage {
  final bool isUser;
  final String message;
  final DateTime? createdAt;

  /// The pad placement this message showed (the full pad-set payload), when
  /// one was saved with it — reopens on the 3D body.
  final Map<String, dynamic>? placement;

  const RagMessage({
    required this.isUser,
    required this.message,
    this.createdAt,
    this.placement,
  });

  factory RagMessage.fromJson(Map<String, dynamic> j) => RagMessage(
        isUser: (j['role'] ?? '') == 'user',
        message: (j['message'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
        // The server's field is `placements`; `placement` is read too, for
        // anything saved under the earlier name.
        placement: j['placements'] is Map
            ? Map<String, dynamic>.from(j['placements'] as Map)
            : (j['placement'] is Map
                ? Map<String, dynamic>.from(j['placement'] as Map)
                : null),
      );
}

/// Node `rag-chat-history`: Assistant transcripts saved per client, or as
/// guest (guests can't be listed back — the list is keyed by client).
class RagChatHistoryRepository {
  final Dio _dio;
  RagChatHistoryRepository(this._dio);

  /// Saves one message. Omit [conversationId] on the first message of a
  /// thread; the server makes one and returns it.
  Future<String?> addMessage({
    required bool isGuest,
    String? clientId,
    String? conversationId,
    required bool isUser,
    required String message,
    List<String> sourceChunkIds = const [],
    Map<String, dynamic>? placement,
  }) async {
    // The server takes ~100 KB per request; a placement bigger than that is
    // left off (the message itself is still saved).
    final keepPlacement =
        placement != null && utf8.encode(jsonEncode(placement)).length < 90000;
    Map<String, dynamic> body({required bool withPlacement}) => {
          'userType': isGuest ? 'guest' : 'client',
          if (!isGuest && clientId != null) 'clientId': clientId,
          if (conversationId != null) 'conversationId': conversationId,
          'role': isUser ? 'user' : 'assistant',
          'message': message,
          if (sourceChunkIds.isNotEmpty) 'sourceChunkIds': sourceChunkIds,
          if (withPlacement) 'placements': placement,
        };
    Response<dynamic> res;
    try {
      res = await _dio.post(ApiEndpoints.ragChatHistory,
          data: body(withPlacement: keepPlacement));
    } on DioException catch (e) {
      // A server that doesn't accept `placements` yet rejects the whole
      // message (400, unknown property) — save the text without it rather
      // than lose the message.
      if (!keepPlacement || e.response?.statusCode != 400) rethrow;
      res = await _dio.post(ApiEndpoints.ragChatHistory,
          data: body(withPlacement: false));
    }
    final data = res.data;
    return data is Map ? data['conversationId']?.toString() : null;
  }

  /// A client's conversations; with [clientId] null, the guest chats this
  /// practitioner started.
  Future<List<RagConversationSummary>> conversations(String? clientId,
      {int page = 1, int limit = 50}) async {
    final res = clientId == null
        ? await _dio.get(ApiEndpoints.ragChatGuestConversations,
            queryParameters: {'page': page, 'limit': limit})
        : await _dio.get(ApiEndpoints.ragChatConversations, queryParameters: {
            'clientId': clientId,
            'page': page,
            'limit': limit
          });
    final data = res.data;
    final list = data is Map && data['conversations'] is List
        ? data['conversations'] as List
        : const [];
    return list
        .whereType<Map>()
        .map((m) =>
            RagConversationSummary.fromJson(Map<String, dynamic>.from(m)))
        .where((c) => c.conversationId.isNotEmpty)
        .toList();
  }

  Future<List<RagMessage>> conversation(String conversationId) async {
    final res = await _dio.get(
        ApiEndpoints.ragChatConversation(conversationId),
        queryParameters: {'page': 1, 'limit': 200});
    final data = res.data;
    final list = data is Map && data['messages'] is List
        ? data['messages'] as List
        : const [];
    return list
        .whereType<Map>()
        .map((m) => RagMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> deleteConversation(String conversationId) =>
      _dio.delete(ApiEndpoints.ragChatConversation(conversationId));
}

final ragChatHistoryRepositoryProvider = Provider<RagChatHistoryRepository>(
  (ref) => RagChatHistoryRepository(ref.read(nodeDioProvider)),
);

/// Keyed by client id; `null` = guest chats.
final ragConversationsProvider = FutureProvider.autoDispose
    .family<List<RagConversationSummary>, String?>((ref, clientId) {
  return ref.read(ragChatHistoryRepositoryProvider).conversations(clientId);
});

final ragConversationProvider =
    FutureProvider.autoDispose.family<List<RagMessage>, String>((ref, id) {
  return ref.read(ragChatHistoryRepositoryProvider).conversation(id);
});
