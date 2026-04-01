import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../domain/chat_message.dart';
import 'chat_sse_source.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.read(chatSseSourceProvider));
});

/// Abstraction layer for chat - supports future local LLM migration.
abstract class ChatEngine {
  Stream<String> sendMessage(
    List<ChatMessageModel> history,
    ChatContext context,
  );
}

class ChatRepository implements ChatEngine {
  final ChatSseSource _sseSource;
  final List<ChatMessageModel> _history = [];

  ChatRepository(this._sseSource);

  List<ChatMessageModel> get history => List.unmodifiable(_history);

  void addUserMessage(String content) {
    _history.add(ChatMessageModel(content: content, isUser: true));
  }

  @override
  Stream<String> sendMessage(
    List<ChatMessageModel> history,
    ChatContext context,
  ) async* {
    final buffer = StringBuffer();

    try {
      await for (final chunk in _sseSource.streamChat(
        messages: history.map((m) => m.toApiMessage()).toList(),
        analysisContext: context.analysisContext,
        pageContext: context.pageContext,
        provider: context.provider,
        model: context.model,
      )) {
        buffer.write(chunk);
        yield chunk;
      }

      // Add complete assistant message to history
      _history
          .add(ChatMessageModel(content: buffer.toString(), isUser: false));
    } catch (e) {
      appLogger.e('Chat error: $e');
      rethrow;
    }
  }

  /// Send a message and get streaming response.
  Stream<String> chat(String userMessage, {ChatContext? context}) {
    addUserMessage(userMessage);
    return sendMessage(
      _history,
      context ?? const ChatContext(),
    );
  }

  void clearHistory() => _history.clear();
}
