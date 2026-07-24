import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';
import '../../../session/domain/pending_session_outcome_model.dart';
import '../../../session/presentation/providers/pending_outcomes_provider.dart';
import '../../../session/presentation/widgets/post_session_outcomes_sheet.dart';

enum _HistoryFilter { all, guest }

class HistoryListScreen extends ConsumerStatefulWidget {
  /// Rendered as a tab inside the Users screen rather than as its own page:
  /// drops the Scaffold and the "Session History" title (the host page already
  /// has a header) and keeps the summary chips + list.
  final bool embedded;

  const HistoryListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  bool _outcomesSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Retry any answered-but-unsynced outcome POSTs (best-effort).
      ref.read(pendingOutcomesProvider.notifier).drainSyncPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sessions still awaiting a post-session review (unanswered only). Rendered
    // as "Needs review" cards pinned above the saved history, persisting until
    // the user answers or skips. Answered-but-unsynced entries are excluded
    // (they retry silently and never re-appear).
    //
    // No auto-prompt (web parity): the sheet opens on tap, or via the session
    // screen's Stop All / Done.
    final pendingReviews = ref
        .watch(pendingOutcomesProvider)
        .where((e) => e.answers == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final sessionsAsync = ref.watch(allSessionsProvider);
    final savedSessions =
        sessionsAsync.asData?.value ?? const <SessionHistoryItem>[];
    final trackedMinutes = savedSessions.fold<int>(
      0,
      (sum, s) => sum + (_intakeDurationSeconds(s) ~/ 60),
    );

    final content = Padding(
      padding: widget.embedded
          ? const EdgeInsets.fromLTRB(16, 0, 16, 0)
          : const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedEntrance(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.embedded) ...[
                  Text('Session History',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  _SummaryChip(
                      value: '${savedSessions.length}',
                      label: 'History',
                      icon: Icons.history_rounded),
                  const SizedBox(width: 8),
                  _SummaryChip(
                      value: '${trackedMinutes}m',
                      label: 'Tracked',
                      icon: Icons.timer_outlined),
                  if (pendingReviews.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _SummaryChip(
                        value: '${pendingReviews.length}',
                        label: 'To review',
                        icon: Icons.rate_review_outlined),
                  ],
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildHistorySessions(sessionsAsync, pendingReviews),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(child: content),
    );
  }

  /// Show the outcomes sheet for [entry], then finalize (single `/intake` POST
  /// with answers, or a bare log on Skip/dismiss). Removing the entry drops its
  /// "Needs review" card from the list.
  Future<void> _reviewOutcomes(PendingSessionOutcome entry) async {
    if (_outcomesSheetOpen) return;
    _outcomesSheetOpen = true;
    try {
      final outcomes = await showPostSessionOutcomesSheet(
        context,
        protocolQuestions: entry.orderedProtocolQuestions,
        discomfortAreas: entry.discomfortAreasForSheet,
      );
      await ref
          .read(pendingOutcomesProvider.notifier)
          .finalize(entry.sessionId, outcomes);
    } finally {
      _outcomesSheetOpen = false;
    }
  }

  /// Any unanswered "Needs review" cards, pinned above the saved history and
  /// shown whatever the guest/all filter is — they're prompts to act on, not
  /// history rows.
  List<Widget> _reviewCards(List<PendingSessionOutcome> pendingReviews) {
    return [
      for (var i = 0; i < pendingReviews.length; i++)
        AnimatedEntrance(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _NeedsReviewCard(
              entry: pendingReviews[i],
              onTap: () => _reviewOutcomes(pendingReviews[i]),
            ),
          ),
        ),
    ];
  }

  Widget _buildHistorySessions(
    AsyncValue<List<SessionHistoryItem>> sessionsAsync,
    List<PendingSessionOutcome> pendingReviews,
  ) {
    return Column(
      children: [
        _HistoryFilterToggle(
          filter: _historyFilter,
          onChanged: (value) => setState(() => _historyFilter = value),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: sessionsAsync.when(
            loading: () => ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ..._reviewCards(pendingReviews),
                for (var i = 0; i < 7; i++) ...[
                  const _HistoryCardSkeleton(),
                  const SizedBox(height: 8),
                ],
              ],
            ),
            error: (error, _) => _EmptyHistoryState(
              title: 'Couldn\'t load history',
              subtitle: 'Pull down to retry. ($error)',
              icon: Icons.cloud_off_rounded,
              onRetry: () => ref.invalidate(allSessionsProvider),
            ),
            data: (sessions) {
              final filtered = _historyFilter == _HistoryFilter.guest
                  ? sessions.where((s) => s.isGuest).toList()
                  : [...sessions];

              // Most recent first (the backend returns these unsorted).
              filtered.sort((a, b) {
                final aDate = a.createdAt;
                final bDate = b.createdAt;
                if (aDate == null && bDate == null) return 0;
                if (aDate == null) return 1; // unknown dates sink to the bottom
                if (bDate == null) return -1;
                return bDate.compareTo(aDate);
              });

              if (filtered.isEmpty) {
                return RefreshIndicator(
                  color: ThemeConstants.accent,
                  onRefresh: () => ref.refresh(allSessionsProvider.future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      ..._reviewCards(pendingReviews),
                      const SizedBox(height: 40),
                      _EmptyHistoryState(
                        title: _historyFilter == _HistoryFilter.guest
                            ? 'No guest sessions'
                            : 'No saved sessions',
                        subtitle: _historyFilter == _HistoryFilter.guest
                            ? 'Guest sessions saved to the database will appear here.'
                            : 'Completed sessions saved to the database will appear here.',
                        icon: Icons.history_rounded,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: ThemeConstants.accent,
                onRefresh: () => ref.refresh(allSessionsProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ..._reviewCards(pendingReviews),
                    for (var i = 0; i < filtered.length; i++) ...[
                      AnimatedEntrance(
                        index: pendingReviews.length + i,
                        child: _HistorySessionCard(session: filtered[i]),
                      ),
                      if (i < filtered.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Total session duration (seconds) for an intake — the longest protocol run.
int _intakeDurationSeconds(SessionHistoryItem session) {
  var maxSeconds = 0;
  for (final protocol in session.protocols) {
    final value = protocol.duration ?? 0;
    if (value > maxSeconds) maxSeconds = value;
  }
  return maxSeconds;
}

String _formatHistoryDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year}  $hour:$minute';
}

String _formatHistoryDuration(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${safeSeconds}s';
}

class _SummaryChip extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _SummaryChip(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: ThemeConstants.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterToggle extends StatelessWidget {
  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onChanged;

  const _HistoryFilterToggle({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterPill(
          label: 'All',
          icon: Icons.all_inclusive_rounded,
          selected: filter == _HistoryFilter.all,
          onTap: () => onChanged(_HistoryFilter.all),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          label: 'Guest only',
          icon: Icons.person_outline_rounded,
          selected: filter == _HistoryFilter.guest,
          onTap: () => onChanged(_HistoryFilter.guest),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.16)
              : ThemeConstants.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? ThemeConstants.accent
                  : ThemeConstants.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? ThemeConstants.accent
                    : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCardSkeleton extends StatelessWidget {
  const _HistoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 40, height: 40, borderRadius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 130, height: 13, borderRadius: 6),
                SizedBox(height: 8),
                ShimmerBox(width: double.infinity, height: 11, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySessionCard extends StatelessWidget {
  final SessionHistoryItem session;

  const _HistorySessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final protocolName = session.protocols.isNotEmpty
        ? (session.protocols.first.protocol ?? 'Session')
        : 'Session';
    final deviceCount = session.protocols
        .map((p) => p.deviceName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;
    final durationLabel =
        _formatHistoryDuration(_intakeDurationSeconds(session));
    final dateLabel = session.createdAt != null
        ? _formatHistoryDate(session.createdAt!)
        : '—';
    final meta = StringBuffer('$dateLabel  •  $durationLabel');
    if (deviceCount > 0) {
      meta.write('  •  $deviceCount device(s)');
    }

    return GradientCard(
      onTap: () => context.push('/history/${session.id ?? ''}', extra: session),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      showShadow: false,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 20,
              color: ThemeConstants.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  protocolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            color: ThemeConstants.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// A completed session awaiting its post-session outcomes. Persists on the Live
/// tab until the user answers or skips, then finalizes (single `/intake` POST).
class _NeedsReviewCard extends StatelessWidget {
  final PendingSessionOutcome entry;
  final VoidCallback onTap;
  const _NeedsReviewCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final deviceCount = entry.deviceIds.length;
    final qCount = entry.orderedProtocolQuestions
        .fold<int>(0, (sum, p) => sum + p.questions.length);
    return GradientCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      showShadow: false,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.assignment_turned_in_rounded,
                color: ThemeConstants.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.protocolName.isEmpty ? 'Session' : entry.protocolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$deviceCount device(s) • Completed',
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ThemeConstants.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    qCount > 0
                        ? 'Needs review • $qCount question(s)'
                        : 'Needs review',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: ThemeConstants.textTertiary),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onRetry;

  const _EmptyHistoryState({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: ThemeConstants.textTertiary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ThemeConstants.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded,
                    size: 18, color: ThemeConstants.accent),
                label: Text(
                  'Retry',
                  style: TextStyle(
                    color: ThemeConstants.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
