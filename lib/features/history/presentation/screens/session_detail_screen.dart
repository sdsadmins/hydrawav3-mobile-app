import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../session_coach/data/coach_plan_store.dart';
import '../../../session_coach/domain/session_coach_models.dart';
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
                    if (session.isSessionCoach) ...[
                      _DetailRow('Session type', 'Session Coach'),
                      const Divider(height: 1),
                    ],
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

              if (session.sessionCoach?.isValid == true) ...[
                const SizedBox(height: HwSpace.s2),
                _SessionCoachDetails(
                  run: session.sessionCoach!,
                  protocols: session.protocols,
                ),
                const SizedBox(height: HwSpace.s2),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final run = session.sessionCoach!;
                      final plan = CoachPlanRecord.fromRun(
                        run,
                        savedAt: session.createdAt,
                        advancedSettingsByMac: {
                          for (final protocol in session.protocols)
                            if (protocol.macAddress?.trim().isNotEmpty ==
                                    true &&
                                protocol.advancedSettings != null)
                              protocol.macAddress!.trim():
                                  protocol.advancedSettings!,
                        },
                      );
                      if (plan == null) return;
                      final selected = clients
                          .where((c) => c.id == session.clientId)
                          .firstOrNull;
                      if (session.isGuest) {
                        ref.read(sessionClientModeProvider.notifier).state =
                            ClientMode.guest;
                        ref.read(selectedClientProvider.notifier).state = null;
                      } else if (selected != null) {
                        ref.read(sessionClientModeProvider.notifier).state =
                            ClientMode.client;
                        ref.read(selectedClientProvider.notifier).state =
                            selected;
                      }
                      ref
                          .read(coachHistoryRestoreRequestProvider.notifier)
                          .state = plan;
                      context.go(RoutePaths.devices);
                    },
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Load in Session Coach'),
                  ),
                ),
              ],

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

class _SessionCoachDetails extends StatefulWidget {
  final SessionCoachRun run;
  final List<HistoryProtocol> protocols;

  const _SessionCoachDetails({
    required this.run,
    required this.protocols,
  });

  @override
  State<_SessionCoachDetails> createState() => _SessionCoachDetailsState();
}

class _SessionCoachDetailsState extends State<_SessionCoachDetails> {
  final Set<int> _expandedSets = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Session Coach details'),
        HwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailRow('Body area', widget.run.bodyPartName),
              const Divider(height: 1),
              _DetailRow('Support type', widget.run.supportType),
            ],
          ),
        ),
        for (final (index, set) in widget.run.sets.indexed) ...[
          const SizedBox(height: HwSpace.s2),
          HwCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set ${index + 1} · ${set.name}',
                  style: const TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _DetailRow('Protocol', set.protocolName),
                _DetailRow('Protocol ID', set.protocolId),
                _DetailRow('Device MAC', set.macAddress),
                if (set.startDelay != null)
                  _DetailRow('Start delay', '${set.startDelay}s'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: Icon(
                      _expandedSets.contains(index)
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                    label: const Text('Advanced settings'),
                    onPressed: () => setState(() {
                      if (!_expandedSets.add(index)) {
                        _expandedSets.remove(index);
                      }
                    }),
                  ),
                ),
                if (_expandedSets.contains(index)) ...[
                  const Divider(height: 1),
                  ..._settingsFor(set).entries.map(
                        (entry) => _DetailRow(
                          _settingLabel(entry.key),
                          _settingValue(entry.value),
                        ),
                      ),
                  if (_settingsFor(set).isEmpty)
                    const _DetailRow('Settings', 'No saved settings'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Map<String, dynamic> _settingsFor(SessionCoachRunSet set) {
    final matching = widget.protocols.where((protocol) =>
        protocol.protocolId == set.protocolId &&
        protocol.macAddress == set.macAddress);
    final protocol = matching.firstOrNull ??
        widget.protocols
            .where((protocol) => protocol.protocolId == set.protocolId)
            .firstOrNull ??
        widget.protocols
            .where((protocol) => protocol.macAddress == set.macAddress)
            .firstOrNull;
    return protocol?.advancedSettings ?? const {};
  }

  static String _settingLabel(String key) {
    final words = key.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static String _settingValue(dynamic value) {
    if (value is bool) return value ? 'On' : 'Off';
    if (value is Map || value is List) return value.toString();
    return value?.toString() ?? '--';
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
