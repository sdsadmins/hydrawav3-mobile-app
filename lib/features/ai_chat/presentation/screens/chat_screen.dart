import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
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
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _listening = false;

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    final msgs = ref.read(chatMessagesProvider.notifier);
    ref.read(isSendingProvider.notifier).state = true;
    msgs.state = [...msgs.state, ChatMessageModel(content: text, isUser: true)];
    _scrollEnd();

    final repo = ref.read(chatRepositoryProvider);
    final buf = StringBuffer();
    try {
      msgs.state = [...msgs.state, ChatMessageModel(content: '', isUser: false)];
      await for (final chunk in repo.chat(text)) {
        buf.write(chunk);
        final u = List<ChatMessageModel>.from(msgs.state);
        u[u.length - 1] = ChatMessageModel(content: buf.toString(), isUser: false);
        msgs.state = u;
        _scrollEnd();
      }
    } catch (_) {
      final u = List<ChatMessageModel>.from(msgs.state);
      u[u.length - 1] = ChatMessageModel(
        content: 'I can help with protocol selection and pad placement. Connect to the backend for AI-powered responses.\n\nTry asking about:\n• Recommended protocols for specific pain areas\n• Pad placement guidance\n• Session type suggestions',
        isUser: false,
      );
      msgs.state = u;
    }
    ref.read(isSendingProvider.notifier).state = false;
    _scrollEnd();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(chatMessagesProvider);
    final sending = ref.watch(isSendingProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: ThemeConstants.textTertiary, size: 20), onPressed: () {
            ref.read(chatMessagesProvider.notifier).state = [];
            ref.read(chatRepositoryProvider).clearHistory();
          }),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: msgs.isEmpty ? _welcome() : ListView.builder(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            itemBuilder: (c, i) => _Bubble(msg: msgs[i], index: i),
          )),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: ThemeConstants.surface,
              border: Border(top: BorderSide(color: ThemeConstants.border.withValues(alpha: 0.5))),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(children: [
                // Mic
                GestureDetector(
                  onTap: () async {
                    final v = ref.read(voiceInputServiceProvider);
                    if (_listening) { await v.stopListening(); setState(() => _listening = false); }
                    else { setState(() => _listening = true); await v.startListening((t) => _ctrl.text = t); }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _listening ? ThemeConstants.error.withValues(alpha: 0.15) : ThemeConstants.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: _listening ? ThemeConstants.error : ThemeConstants.textTertiary, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ask about protocols, placement...',
                    hintStyle: const TextStyle(color: ThemeConstants.textTertiary, fontSize: 14),
                    filled: true, fillColor: ThemeConstants.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                )),
                const SizedBox(width: 10),
                // Send
                GestureDetector(
                  onTap: sending ? null : _send,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [ThemeConstants.accent, Color(0xFFE09060)]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.25), blurRadius: 8)],
                    ),
                    child: sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AnimatedEntrance(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GlowIconBox(icon: Icons.smart_toy_outlined, size: 64, iconSize: 32),
            const SizedBox(height: 20),
            const Text('AI Assistant', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 10),
            const Text(
              'Get protocol recommendations, pad placement guidance, and session suggestions based on your discomfort areas.',
              style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8, runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip('Recommend a protocol'),
                _SuggestionChip('Where to place pads?'),
                _SuggestionChip('Lower back pain help'),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  const _SuggestionChip(this.label);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Pre-fill the text field — would need a ref but keeping simple
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ThemeConstants.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.15)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, color: ThemeConstants.accent, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessageModel msg;
  final int index;
  const _Bubble({required this.msg, required this.index});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return AnimatedEntrance(
      index: 0,
      durationMs: 300,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: isUser
                ? const LinearGradient(colors: [ThemeConstants.accent, Color(0xFFE09060)])
                : null,
            color: isUser ? null : ThemeConstants.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4), bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: isUser ? null : Border.all(color: ThemeConstants.border),
            boxShadow: isUser ? [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Text(
            msg.content.isEmpty ? '...' : msg.content,
            style: TextStyle(color: isUser ? Colors.white : ThemeConstants.textPrimary, fontSize: 14, height: 1.4),
          ),
        ),
      ),
    );
  }
}
