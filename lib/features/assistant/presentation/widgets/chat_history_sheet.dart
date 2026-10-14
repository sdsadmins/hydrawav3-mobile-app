import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../data/rag_chat_history_repository.dart';

/// Past Assistant conversations (`rag-chat-history`) for a client, or — with
/// [clientId] null — the guest chats this practitioner started. Tap to read,
/// trash to delete. Reading is view-only — typing in the Assistant starts a
/// new conversation.
Future<void> showChatHistorySheet(
  BuildContext context, {
  required String? clientId,
  required String clientName,
}) {
  return showPlanSheet<void>(
    context,
    title: 'Past conversations',
    subtitle: clientName,
    builder: (_) => _HistoryList(clientId: clientId),
  );
}

String _when(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final mm = l.minute.toString().padLeft(2, '0');
  return '${m[l.month - 1]} ${l.day} · $hh:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
}

class _HistoryList extends ConsumerWidget {
  final String? clientId;
  const _HistoryList({required this.clientId});

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RagConversationSummary c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This removes it for everyone in your organization.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(ragChatHistoryRepositoryProvider)
          .deleteConversation(c.conversationId);
      ref.invalidate(ragConversationsProvider(clientId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t delete. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(ragConversationsProvider(clientId));
    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: p.copper)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Couldn’t load conversations.',
                style: TextStyle(color: p.ink2)),
            TextButton(
              onPressed: () => ref.invalidate(ragConversationsProvider(clientId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (list) => list.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No saved conversations yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink3)),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = list[i];
                return Material(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => showPlanSheet<void>(
                      context,
                      title: 'Conversation',
                      subtitle: _when(c.lastAt),
                      builder: (_) => _Transcript(id: c.conversationId),
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.cardline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 20, color: p.copperInk),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.lastMessage,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: p.ink),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_when(c.lastAt)} · ${c.messageCount} messages',
                                  style:
                                      TextStyle(fontSize: 12, color: p.ink3),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete conversation',
                            icon: Icon(Icons.delete_outline_rounded,
                                color: p.ink3),
                            onPressed: () => _delete(context, ref, c),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Transcript extends ConsumerWidget {
  final String id;
  const _Transcript({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(ragConversationProvider(id));
    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: p.copper)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Couldn’t load this conversation.',
            style: TextStyle(color: p.ink2)),
      ),
      data: (msgs) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: msgs.length,
        itemBuilder: (context, i) {
          final m = msgs[i];
          return Align(
            alignment:
                m.isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.isUser ? p.copper : p.card,
                borderRadius: BorderRadius.circular(16),
                border: m.isUser ? null : Border.all(color: p.cardline),
              ),
              child: Text(
                m.message,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: m.isUser ? Colors.white : p.ink),
              ),
            ),
          );
        },
      ),
    );
  }
}
