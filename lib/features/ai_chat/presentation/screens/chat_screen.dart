import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/glass_container.dart';
import '../../data/chat_repository.dart';
import '../../domain/chat_message.dart';
import '../../services/voice_input_service.dart';

final chatMessagesProvider =
    StateProvider<List<ChatMessageModel>>((ref) => []);
final isSendingProvider = StateProvider<bool>((ref) => false);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isListening = false;
  late AnimationController _entryAnim;

  @override
  void initState() {
    super.initState();
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final messages = ref.read(chatMessagesProvider.notifier);
    ref.read(isSendingProvider.notifier).state = true;

    messages.state = [
      ...messages.state,
      ChatMessageModel(content: text, isUser: true),
    ];
    _scrollToBottom();

    // Stream from chat repository
    final chatRepo = ref.read(chatRepositoryProvider);
    final buffer = StringBuffer();

    try {
      // Add placeholder assistant message
      messages.state = [
        ...messages.state,
        ChatMessageModel(content: '', isUser: false),
      ];

      await for (final chunk in chatRepo.chat(text)) {
        buffer.write(chunk);
        final updated = List<ChatMessageModel>.from(messages.state);
        updated[updated.length - 1] =
            ChatMessageModel(content: buffer.toString(), isUser: false);
        messages.state = updated;
        _scrollToBottom();
      }
    } catch (e) {
      final updated = List<ChatMessageModel>.from(messages.state);
      updated[updated.length - 1] = ChatMessageModel(
        content:
            '🤖 I can help you with protocol selection and pad placement. Connect to the backend to get AI-powered responses!\n\n💡 Try asking about:\n• Recommended protocols for specific pain areas\n• Pad placement guidance\n• Session type suggestions',
        isUser: false,
      );
      messages.state = updated;
    }

    ref.read(isSendingProvider.notifier).state = false;
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
    final isSending = ref.watch(isSendingProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ThemeConstants.darkTeal, Color(0xFF0F1E25)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
                parent: _entryAnim, curve: Curves.easeOut),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('🤖 AI Assistant',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                      GestureDetector(
                        onTap: () {
                          ref.read(chatMessagesProvider.notifier).state = [];
                          ref.read(chatRepositoryProvider).clearHistory();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white54, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages
                Expanded(
                  child: messages.isEmpty
                      ? _buildWelcome()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) =>
                              _MessageBubble(message: messages[index]),
                        ),
                ),

                // Input bar
                ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 🎤 Voice
                          GestureDetector(
                            onTap: () async {
                              final voice =
                                  ref.read(voiceInputServiceProvider);
                              if (_isListening) {
                                await voice.stopListening();
                                setState(() => _isListening = false);
                              } else {
                                setState(() => _isListening = true);
                                await voice
                                    .startListening((text) {
                                  _controller.text = text;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isListening
                                    ? ThemeConstants.error
                                        .withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _isListening
                                    ? ThemeConstants.error
                                    : Colors.white54,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Text input
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                              cursorColor: ThemeConstants.tanLight,
                              decoration: InputDecoration(
                                hintText:
                                    '💬 Ask about protocols, placement...',
                                hintStyle: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.35),
                                    fontSize: 14),
                                filled: true,
                                fillColor:
                                    Colors.white.withValues(alpha: 0.08),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Send
                          GestureDetector(
                            onTap: isSending ? null : _sendMessage,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeConstants.copper,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: isSending
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.send_rounded,
                                      color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ThemeConstants.copper.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  size: 48, color: ThemeConstants.tanLight),
            ),
            const SizedBox(height: 24),
            const Text('🤖 Hi! I\'m your AI Assistant',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 12),
            Text(
              '💡 I can help you with:\n\n'
              '🎯 Protocol recommendations\n'
              '📍 Pad placement guidance\n'
              '💪 Session type suggestions\n'
              '📊 Pain assessment analysis',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isUser
                ? ThemeConstants.copper
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: isUser
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            message.content.isEmpty ? '...' : message.content,
            style: TextStyle(
              color: isUser ? Colors.white : Colors.white.withValues(alpha: 0.85),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
