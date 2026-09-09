import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';

/// One session's record — the UI spec's `openHistDetail()` (app.js:2680).
///
/// Normally the list hands over the model via `extra`; the id path is the
/// fallback for a deep link or a cold start.
class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  final SessionHistoryItem? item;

  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item != null) return _Detail(session: item!);

    // Deep-link/cold-start fallback only — the list screen normally hands the
    // item over directly via `extra`. History is scroll-paginated now, so a
    // session outside the pages already loaded isn't visible yet; keep
    // pulling more pages until it turns up or the list is exhausted.
    final pageState = ref.watch(historyPagingProvider);
    for (final s in pageState.items) {
      if (s.id == sessionId) return _Detail(session: s);
    }
    if (pageState.error != null) {
      return const _Status("Couldn't load this session.");
    }
    if (pageState.hasMore && !pageState.isLoading && !pageState.isLoadingMore) {
      Future.microtask(
          () => ref.read(historyPagingProvider.notifier).loadMore());
    }
    if (!pageState.hasMore) {
      return const _Status('Session not found.');
    }
    return const _Status('Loading session…');
  }
}

class _Detail extends ConsumerWidget {
  final SessionHistoryItem session;
  const _Detail({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final clients = ref.watch(clientListProvider).valueOrNull ?? const [];
    final name = session.isGuest
        ? 'Guest'
        : clients
                .where((c) => c.id == session.clientId)
                .map((c) => c.displayName)
                .firstOrNull ??
            'Client';

    final first = session.protocols.isEmpty ? null : session.protocols.first;
    final at = session.createdAt?.toLocal();

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Session detail',
                subtitle: at == null ? null : _stamp(at),
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),

              // Match the handoff detail layout: key facts first, then the
              // outcome-readiness summary and notes.
              HwCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailRow('Client', name),
                    const Divider(height: 1),
                    _DetailRow('Session', first?.protocol ?? '--'),
                    const Divider(height: 1),
                    _DetailRow('Duration', _formatDuration(first?.duration)),
                    const Divider(height: 1),
                    _DetailRow('Device', first?.deviceName ?? '--'),
                    const Divider(height: 1),
                    _DetailRow('Music', 'Off'),
                  ],
                ),
              ),

              if (_answers(session).isNotEmpty) ...[
                const SizedBox(height: HwSpace.s2),
                const HwEyebrow('Outcome check'),
                HwCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final qa in _answers(session)) _AnswerRow(qa),
                    ],
                  ),
                ),
              ],

              if (session.sessionNotes?.isNotEmpty == true) ...[
                const SizedBox(height: HwSpace.s2),
                const HwEyebrow('Notes'),
                HwCard(
                  child: Text(
                    session.sessionNotes!,
                    style: TextStyle(
                        fontSize: HwType.sm, height: 1.5, color: p.ink2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Every answered outcome question across the session's protocols, de-duped
  /// by question text (a Protocol Plus run logs the same question per
  /// sub-protocol).
  static List<HistoryQuestionAnswer> _answers(SessionHistoryItem s) {
    final seen = <String>{};
    final out = <HistoryQuestionAnswer>[];
    for (final p in s.protocols) {
      for (final qa in p.questionAnswers) {
        if (qa.answer.trim().isEmpty) continue;
        if (!seen.add(qa.question)) continue;
        out.add(qa);
      }
    }
    return out;
  }

  static String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }

  static String _stamp(DateTime at) {
    two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} · '
        '${two(at.hour)}:${two(at.minute)}';
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.history);
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: HwType.cap, color: p.ink3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HwType.sm, color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// One outcome-check question and the answer that was given.
class _AnswerRow extends StatelessWidget {
  final HistoryQuestionAnswer qa;
  const _AnswerRow(this.qa);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            qa.question,
            style: TextStyle(fontSize: HwType.cap, color: p.ink3),
          ),
          const SizedBox(height: 2),
          Text(
            qa.answer,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String message;
  const _Status(this.message);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Session detail',
                onBack: () => _Detail._back(context),
              ),
              const SizedBox(height: 60),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HwType.sm, color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
