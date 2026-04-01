import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

final chatMessagesProvider =
    StateProvider<List<ChatMessage>>((ref) => []);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isListening = false;
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final messages = ref.read(chatMessagesProvider.notifier);

    // Add user message
    messages.state = [
      ...messages.state,
      ChatMessage(content: text, isUser: true),
    ];

    setState(() => _isSending = true);
    _scrollToBottom();

    // TODO: Send to /api/chat via SSE and stream response
    await Future.delayed(const Duration(seconds: 1));

    messages.state = [
      ...messages.state,
      ChatMessage(
        content:
            'I can help you with protocol selection and pad placement. This is a placeholder response. The AI chat will be connected to the backend SSE endpoint.',
        isUser: false,
      ),
    ];

    setState(() => _isSending = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).state = [];
            },
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.all(ThemeConstants.spacingMd),
                    itemCount: messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && _isSending) {
                        return _buildTypingIndicator();
                      }
                      return _MessageBubble(message: messages[index]);
                    },
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.all(ThemeConstants.spacingSm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Voice input
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? ThemeConstants.error
                          : ThemeConstants.textTertiary,
                    ),
                    onPressed: () {
                      setState(() => _isListening = !_isListening);
                      // TODO: speech_to_text integration
                    },
                  ),
                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Ask about protocols, placement...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeConstants.radiusXl),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: ThemeConstants.spacingMd,
                          vertical: ThemeConstants.spacingSm,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: ThemeConstants.spacingSm),
                  // Send button
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: ThemeConstants.primaryColor,
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined,
                size: 64, color: ThemeConstants.primaryColor.withOpacity(0.5)),
            const SizedBox(height: ThemeConstants.spacingMd),
            Text(
              'AI Assistant',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ThemeConstants.spacingSm),
            Text(
              'Ask me about protocols, pad placement, or get session recommendations based on your discomfort areas.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(ThemeConstants.spacingMd),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        ),
        child: const SizedBox(
          width: 40,
          child: LinearProgressIndicator(),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(ThemeConstants.spacingMd),
        decoration: BoxDecoration(
          color: message.isUser
              ? ThemeConstants.primaryColor
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: message.isUser ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}
