import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';
import '../../../session/domain/pending_session_outcome_model.dart';
import '../../../session/presentation/providers/pending_outcomes_provider.dart';
import '../../../session/presentation/widgets/post_session_outcomes_sheet.dart';

/// Session history — ported from the UI spec's `renderHistory()` (app.js:2656).
///
/// Rows group under day headers, and each carries the outcome-check result
/// rather than a raw duration. Everything comes from `GET /intake/all`.
class HistoryListScreen extends ConsumerStatefulWidget {
  /// Rendered as a tab inside the Users screen rather than as its own page:
  /// drops the Scaffold, the backbar and the segmented control (the host page
  /// already provides that context) and keeps the filter + list.
  final bool embedded;

  const HistoryListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  /// Null = the "All" chip; otherwise a client id.
  String? _clientId;
  bool _outcomesSheetOpen = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Retry any answered-but-unsynced outcome POSTs (best-effort).
      ref.read(pendingOutcomesProvider.notifier).drainSyncPending();
    });
    // Fire loadMore a bit before the physical bottom so the next page is
    // usually ready before the user actually reaches the end of the list.
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      // A specific client's history arrives complete in one call — nothing
      // to page through, so scroll-triggered loading only applies to "All".
      if (_clientId != null) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 300) {
        ref.read(historyPagingProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    // Sessions still awaiting a post-session review (unanswered only), pinned
    // above the history. No auto-prompt — the sheet opens on tap.
    final pendingReviews = ref
        .watch(pendingOutcomesProvider)
        .where((e) => e.answers == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final pageState = ref.watch(historyPagingProvider);
    final clients = ref.watch(clientListProvider).valueOrNull ?? const [];

    // "All" chip: the scroll-paginated org-wide list. A specific client chip:
    // that client's own endpoint (GET /intake/client/:clientId) — fast (one
    // client's sessions, not the whole org) and complete on the first call,
    // so it must NOT be answered by filtering whatever's currently loaded
    // from the "All" pages, which used to silently show nothing for a client
    // whose sessions hadn't been scrolled into view yet.
    final isAllMode = _clientId == null;
    final clientAsync =
        isAllMode ? null : ref.watch(clientHistoryProvider(_clientId!));

    final rows = isAllMode ? pageState.items : (clientAsync!.valueOrNull ?? const []);
    final rowsLoading = isAllMode ? pageState.isLoading : (clientAsync!.isLoading);
    final rowsError = isAllMode ? pageState.error : clientAsync!.error;

    final filtered = [...rows]
      ..sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1; // unknown dates sink
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

    // The whole roster from [clientListProvider], not filtered to "clients
    // who already have history" — that used to require [allSessionsProvider]
    // (the full org-wide session list) to load first, which is the slow,
    // multi-page fetch. clientListProvider is a single fast org-scoped call,
    // so the chip row now renders immediately regardless of session-list
    // load time. A client with no sessions yet just shows "No sessions yet"
    // when tapped, which is a fine, honest state.
    final chipClients = [...clients]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          HwBackBar(
            title: 'History',
            subtitle: '${filtered.length} session'
                '${filtered.length == 1 ? '' : 's'} · outcome checks build '
                'the story',
          ),
          const SizedBox(height: HwSpace.s2),
          HwSegmented(
            labels: const ['Team', 'AI Reports', 'History'],
            selectedIndex: 2,
            onSelected: (i) {
              if (i == 0) context.go(RoutePaths.users);
              if (i == 1) context.push(RoutePaths.aiReports);
            },
          ),
          const SizedBox(height: HwSpace.s3),
        ],
        if (chipClients.isNotEmpty) ...[
          HwChipRow(
            labels: [
              'All',
              // Full name, not just the first word — two clients sharing a
              // first name were indistinguishable in the filter row.
              for (final c in chipClients) c.displayName,
            ],
            selectedIndex: _clientId == null
                ? 0
                : chipClients.indexWhere((c) => c.id == _clientId) + 1,
            onSelected: (i) => setState(() {
              _clientId = i == 0 ? null : chipClients[i - 1].id;
            }),
          ),
          const SizedBox(height: HwSpace.s2),
        ],
        Expanded(
          child: RefreshIndicator(
            color: p.copper,
            backgroundColor: p.card,
            onRefresh: () => isAllMode
                ? ref.read(historyPagingProvider.notifier).refresh()
                : ref.refresh(clientHistoryProvider(_clientId!).future),
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: widget.embedded ? 16 : 108),
              children: [
                for (final entry in pendingReviews)
                  Padding(
                    padding: const EdgeInsets.only(bottom: HwSpace.s2),
                    child: _NeedsReviewCard(
                      entry: entry,
                      onTap: () => _reviewOutcomes(entry),
                    ),
                  ),
                if (rowsLoading && rows.isEmpty)
                  const _HistorySkeleton()
                else if (rowsError != null && rows.isEmpty)
                  _Message(
                    "Couldn't load history.",
                    onRetry: () => isAllMode
                        ? ref.read(historyPagingProvider.notifier).loadFirstPage()
                        : ref.invalidate(clientHistoryProvider(_clientId!)),
                  )
                else if (filtered.isEmpty)
                  const _Message(
                    'No sessions yet. Completed sessions land here.',
                  )
                else ...[
                  _SessionList(sessions: filtered, clients: clients),
                  // Bottom-of-list state — "All" mode only: a spinner while
                  // the next page loads, or a small inline retry if the last
                  // loadMore() failed (existing rows stay on screen either
                  // way). A single client's history arrives complete in one
                  // call, so there's no "more" to page through here.
                  if (isAllMode && pageState.isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: HwSpace.s3),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (isAllMode &&
                      pageState.error != null &&
                      rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: HwSpace.s2),
                      child: Center(
                        child: TextButton(
                          onPressed: () =>
                              ref.read(historyPagingProvider.notifier).loadMore(),
                          child: const Text('Couldn\'t load more, tap to retry'),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: content,
        ),
      ),
    );
  }

  /// Show the outcomes sheet for [entry], then finalize (single `/intake` POST
  /// with answers, or a bare log on Skip/dismiss).
  Future<void> _reviewOutcomes(PendingSessionOutcome entry) async {
    if (_outcomesSheetOpen) return;
    _outcomesSheetOpen = true;
    try {
      final outcomes = await showPostSessionOutcomesSheet(
        context,
        pendingOutcome: entry,
      );
      await ref
          .read(pendingOutcomesProvider.notifier)
          .finalize(entry.sessionId, outcomes);
    } finally {
      _outcomesSheetOpen = false;
    }
  }
}

// ---------------------------------------------------------------------------

/// The whole list lives in one card, with day headers injected between rows
/// whenever the date changes.
class _SessionList extends StatelessWidget {
  final List<SessionHistoryItem> sessions;
  final List<Client> clients;

  const _SessionList({required this.sessions, required this.clients});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final rows = <Widget>[];
    String? lastDay;

    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final day = _dayKey(s.createdAt);
      if (day != lastDay) {
        rows.add(Padding(
          padding: EdgeInsets.fromLTRB(0, rows.isEmpty ? 6 : 12, 0, 4),
          child: HwEyebrow(_dayLabel(s.createdAt)),
        ));
        lastDay = day;
      } else if (rows.isNotEmpty) {
        rows.add(Divider(height: 1, color: p.divider));
      }
      rows.add(_SessionRow(session: s, clients: clients));
    }

    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(children: rows),
    );
  }

  static String _dayKey(DateTime? at) {
    if (at == null) return 'unknown';
    final l = at.toLocal();
    return '${l.year}-${l.month}-${l.day}';
  }

  static String _dayLabel(DateTime? at) {
    if (at == null) return 'Undated';
    final l = at.toLocal();
    final now = DateTime.now();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return 'Today';
    }
    final y = now.subtract(const Duration(days: 1));
    if (l.year == y.year && l.month == y.month && l.day == y.day) {
      return 'Yesterday';
    }
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

class _SessionRow extends StatelessWidget {
  final SessionHistoryItem session;
  final List<Client> clients;

  const _SessionRow({required this.session, required this.clients});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final name = session.isGuest
        ? 'Guest'
        : clients
                .where((c) => c.id == session.clientId)
                .map((c) => c.displayName)
                .firstOrNull ??
            'Client';

    return HwRow(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: p.tanSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            _initials(name),
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.copperInk,
            ),
          ),
        ),
      ),
      title: name,
      subtitle: _label(session),
      trailing: _OutcomePill(session),
      onTap: () => context.push('/history/${session.id}', extra: session),
    );
  }

  static String _label(SessionHistoryItem s) {
    final protocol = s.protocols.isEmpty
        ? 'Session'
        : (s.protocols.first.protocol ?? 'Session');
    final at = s.createdAt?.toLocal();
    final time = at == null
        ? null
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final duration = _formatDuration(s.protocols.firstOrNull?.duration);
    final device = s.protocols.firstOrNull?.deviceName;
    final parts = <String>[];
    if (protocol.isNotEmpty) parts.add(protocol);
    if (time != null) parts.add(time);
    if (duration != null && duration.isNotEmpty) parts.add(duration);
    if (device != null && device.isNotEmpty) parts.add(device);
    return parts.join(' · ');
  }

  static String? _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '–';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// The spec's trailing status, in its precedence order (app.js:1338): the
/// outcome check first, then "—".
///
/// The outcome check is the ONLY thing the post-session sheet collects, and it
/// lands in `protocols[].questionAnswers`.
class _OutcomePill extends StatelessWidget {
  final SessionHistoryItem session;
  const _OutcomePill(this.session);

  @override
  Widget build(BuildContext context) {
    final answer = _firstAnswer(session);
    if (answer != null) {
      final normalized = answer.toLowerCase();
      if (normalized == 'yes') {
        return const HwPill('YES ✓', tone: HwPillTone.good);
      }
      if (normalized == 'no') return const HwPill('NO', tone: HwPillTone.low);
      // Preset sets aren't always yes/no — show what was actually answered
      // rather than forcing it into a verdict the data doesn't support.
      return HwPill(
          answer.length > 14 ? '${answer.substring(0, 13)}…' : answer);
    }

    return const HwPill('--');
  }

  /// The first non-empty outcome answer logged on any of the session's
  /// protocols, or null when the review was skipped.
  static String? _firstAnswer(SessionHistoryItem s) {
    for (final p in s.protocols) {
      for (final qa in p.questionAnswers) {
        final a = qa.answer.trim();
        if (a.isNotEmpty) return a;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------

class _NeedsReviewCard extends StatelessWidget {
  final PendingSessionOutcome entry;
  final VoidCallback onTap;

  const _NeedsReviewCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwCard(
      accented: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: HwRow(
        leading: HwIcon(HwIcons.chat, size: 19, color: p.copperInk),
        title: 'Session needs a quick check',
        subtitle: 'One check, builds your proof board',
        trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
        onTap: onTap,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _Message(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HwType.sm, height: 1.5, color: p.ink2),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: HwSpace.s3),
            HwPress(
              onTap: onRetry!,
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: HwType.sm,
                  fontWeight: FontWeight.w700,
                  color: p.copperInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: HwSpace.s2),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(HwRadius.lg),
                border: Border.all(color: p.cardline),
              ),
            ),
          ),
      ],
    );
  }
}
