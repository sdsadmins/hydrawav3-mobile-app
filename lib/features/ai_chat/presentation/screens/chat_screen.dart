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
      body: Column(
        children: [
          // Header — matches prototype chat header
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            decoration: const BoxDecoration(
              color: ThemeConstants.surface,
              border: Border(bottom: BorderSide(color: ThemeConstants.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: ThemeConstants.metallic400, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeConstants.accent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.25), blurRadius: 10)],
                    ),
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HydraAssistant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: ThemeConstants.textPrimary)),
                        Row(children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: ThemeConstants.success, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('Online', style: TextStyle(fontSize: 12, color: ThemeConstants.success)),
                        ]),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      ref.read(chatMessagesProvider.notifier).state = [];
                      ref.read(chatRepositoryProvider).clearHistory();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Messages
          Expanded(child: msgs.isEmpty ? _welcome() : ListView.builder(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length + (sending ? 1 : 0),
            itemBuilder: (c, i) {
              if (i == msgs.length && sending) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18), topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(4), bottomRight: Radius.circular(18),
                      ),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ThemeConstants.accentLight)),
                      const SizedBox(width: 10),
                      const Text('Thinking...', style: TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
                    ]),
                  ),
                );
              }
              return _Bubble(msg: msgs[i], index: i);
            },
          )),

          // Input Area — matches prototype (rounded-full pill, navy-900 bg)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: ThemeConstants.surface,
              border: const Border(top: BorderSide(color: ThemeConstants.border)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: ThemeConstants.background,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: Row(children: [
                  // Mic button
                  GestureDetector(
                    onTap: () async {
                      final v = ref.read(voiceInputServiceProvider);
                      if (_listening) { await v.stopListening(); setState(() => _listening = false); }
                      else { setState(() => _listening = true); await v.startListening((t) => _ctrl.text = t); }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? ThemeConstants.error : ThemeConstants.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Text input
                  Expanded(child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Ask about recovery...',
                      hintStyle: TextStyle(color: ThemeConstants.textTertiary, fontSize: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  )),
                  const SizedBox(width: 4),
                  // Send button
                  GestureDetector(
                    onTap: sending ? null : _send,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: ThemeConstants.accent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
              ),
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
            const Text('HydraAssistant', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ThemeConstants.textPrimary)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ThemeConstants.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, color: ThemeConstants.accentLight, fontWeight: FontWeight.w500)),
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
            // User: copper-600 bg; AI: navy-800 with border
            color: isUser ? ThemeConstants.accentDark : ThemeConstants.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4), bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: isUser ? null : Border.all(color: ThemeConstants.border),
            boxShadow: isUser
                ? [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Role label
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isUser ? Icons.person_rounded : Icons.auto_awesome_rounded, size: 12, color: isUser ? Colors.white70 : ThemeConstants.accentLight),
                const SizedBox(width: 6),
                Text(isUser ? 'You' : 'Assistant', style: TextStyle(fontSize: 11, color: isUser ? Colors.white70 : ThemeConstants.textSecondary)),
              ]),
              const SizedBox(height: 4),
              Text(
                msg.content.isEmpty ? '...' : msg.content,
                style: TextStyle(color: isUser ? Colors.white : ThemeConstants.textPrimary, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
