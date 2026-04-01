class ChatMessageModel {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? analysisContext;

  ChatMessageModel({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.analysisContext,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMessage() => {
        'role': isUser ? 'user' : 'assistant',
        'content': content,
      };
}

class ChatContext {
  final String? analysisContext;
  final String? pageContext;
  final String provider;
  final String? model;

  const ChatContext({
    this.analysisContext,
    this.pageContext,
    this.provider = 'anthropic',
    this.model,
  });
}
