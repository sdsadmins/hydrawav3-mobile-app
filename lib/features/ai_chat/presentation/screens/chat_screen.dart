import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../data/chat_repository.dart';
import '../../domain/chat_message.dart';
import '../../services/voice_input_service.dart';

final chatMessagesProvider = StateProvider<List<ChatMessageModel>>((ref) => []);
final isSendingProvider = StateProvider<bool>((ref) => false);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isListening = false;

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
    ref.read(isSendingProvider.notifier).state = true;

    messages.state = [...messages.state, ChatMessageModel(content: text, isUser: true)];
    _scrollToBottom();

    final chatRepo = ref.read(chatRepositoryProvider);
    final buffer = StringBuffer();

    try {
      messages.state = [...messages.state, ChatMessageModel(content: '', isUser: false)];
      await for (final chunk in chatRepo.chat(text)) {
        buffer.write(chunk);
        final updated = List<ChatMessageModel>.from(messages.state);
        updated[updated.length - 1] = ChatMessageModel(content: buffer.toString(), isUser: false);
        messages.state = updated;
        _scrollToBottom();
      }
    } catch (_) {
      final updated = List<ChatMessageModel>.from(messages.state);
      updated[updated.length - 1] = ChatMessageModel(
        content: 'I can help with protocol selection and pad placement. Connect to the backend to get AI-powered responses.\n\nTry asking about:\n- Recommended protocols for specific pain areas\n- Pad placement guidance\n- Session type suggestions',
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
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final isSending = ref.watch(isSendingProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: ThemeConstants.textTertiary), onPressed: () {
            ref.read(chatMessagesProvider.notifier).state = [];
            ref.read(chatRepositoryProvider).clearHistory();
          }),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) => _Bubble(msg: messages[i]),
                  ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(color: ThemeConstants.surface, border: Border(top: BorderSide(color: ThemeConstants.border))),
            child: SafeArea(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final voice = ref.read(voiceInputServiceProvider);
                      if (_isListening) {
                        await voice.stopListening();
                        setState(() => _isListening = false);
                      } else {
                        setState(() => _isListening = true);
                        await voice.startListening((text) => _controller.text = text);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _isListening ? ThemeConstants.error.withValues(alpha: 0.15) : ThemeConstants.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                      child: Icon(_isListening ? Icons.mic_rounded : Icons.mic_none_rounded, color: _isListening ? ThemeConstants.error : ThemeConstants.textTertiary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask about protocols, placement...',
                        hintStyle: const TextStyle(color: ThemeConstants.textTertiary, fontSize: 14),
                        filled: true,
                        fillColor: ThemeConstants.surfaceVariant,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: isSending ? null : _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: ThemeConstants.accent, borderRadius: BorderRadius.circular(8)),
                      child: isSending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            Icon(Icons.smart_toy_outlined, size: 48, color: ThemeConstants.accent.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('AI Assistant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              'Get protocol recommendations, pad placement guidance, and session suggestions based on your discomfort areas.',
              style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessageModel msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? ThemeConstants.accent : ThemeConstants.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4), bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: isUser ? null : Border.all(color: ThemeConstants.border),
        ),
        child: Text(
          msg.content.isEmpty ? '...' : msg.content,
          style: TextStyle(color: isUser ? Colors.white : ThemeConstants.textPrimary, fontSize: 14, height: 1.4),
        ),
      ),
    );
  }
}
