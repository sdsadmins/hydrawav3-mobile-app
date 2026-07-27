import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../ai_report/presentation/widgets/client_reports_section.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/session_history_model.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';
import '../widgets/client_lease_section.dart';
import '../widgets/edit_client_sheet.dart';

/// The player / client portfolio — the UI spec's `openPlayer(id)`
/// (app.js:1756).
///
/// This was an AppBar plus two embedded widgets. The spec makes it the hub for
/// one person: who they are, what they've done, and the two actions a
/// practitioner actually takes from here.
class ClientDetailScreen extends ConsumerWidget {
  final String clientId;
  final String? title;

  const ClientDetailScreen({super.key, required this.clientId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final client = ref
        .watch(clientListProvider)
        .valueOrNull
        ?.where((c) => c.id == clientId)
        .firstOrNull;
    final history = ref.watch(clientHistoryProvider(clientId));

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.copper,
          backgroundColor: p.card,
          onRefresh: () async {
            ref.invalidate(clientHistoryProvider(clientId));
            ref.invalidate(clientListProvider);
            await ref.read(clientHistoryProvider(clientId).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
            children: [
              HwBackBar(
                title: client?.displayName ?? title ?? 'Client',
                subtitle: _subtitle(client),
                onBack: () => _back(context),
                trailing: client == null
                    ? null
                    : HwIconButton(
                        asset: HwIcons.pencil,
                        size: 34,
                        onTap: () =>
                            showEditClientSheet(context, ref, client),
                      ),
              ),
              const SizedBox(height: HwSpace.s2),

              _StatTiles(history: history),
              const SizedBox(height: HwSpace.s5),

              // The two things a practitioner does from a profile. Both carry
              // this client into the flow, so nobody re-picks them.
              const HwEyebrow('Pad placements'),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: '⚡ Performance',
                        filled: true,
                        onTap: () =>
                            _startFlow(context, ref, client, 'performance'),
                      ),
                    ),
                    const SizedBox(width: HwSpace.s3),
                    Expanded(
                      child: _ActionButton(
                        label: '〰 Recovery',
                        filled: false,
                        onTap: () =>
                            _startFlow(context, ref, client, 'recovery'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HwSpace.s5),

              const HwEyebrow('Device lease'),
              ClientLeaseSection(clientId: clientId),
              const SizedBox(height: HwSpace.s5),

              const HwEyebrow('AI mobility reports'),
              ClientReportsSection(clientId: clientId),
              const SizedBox(height: HwSpace.s5),

              const HwEyebrow('Sessions & outcomes'),
              _SessionHistory(history: history),
            ],
          ),
        ),
      ),
    );
  }

  static String? _subtitle(Client? c) {
    if (c == null) return null;
    final bits = <String>[
      if (c.sport?.isNotEmpty == true) c.sport!,
      if (c.jerseyNumber != null && c.jerseyNumber! > 0) '#${c.jerseyNumber}',
      if (c.age != null) '${c.age} yrs',
      if (c.gender?.isNotEmpty == true) c.gender!,
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// Hands the flow this person before navigating — the spec's
  /// `prepFromProfile` / `recoveryFromProfile`. The Assistant reads the
  /// selection and skips its "who are we prepping?" step.
  static void _startFlow(
    BuildContext context,
    WidgetRef ref,
    Client? client,
    String intent,
  ) {
    if (client != null) {
      ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
      ref.read(selectedClientProvider.notifier).state = client;
    }
    context.go('${RoutePaths.assistant}?intent=$intent');
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.users);
    }
  }
}

// ---------------------------------------------------------------------------

/// Sessions · improvement rate · assessments, from this client's own history.
class _StatTiles extends StatelessWidget {
  final AsyncValue<List<SessionHistoryItem>> history;
  const _StatTiles({required this.history});

  @override
  Widget build(BuildContext context) {
    final sessions = history.valueOrNull ?? const <SessionHistoryItem>[];

    var scored = 0;
    var improved = 0;
    for (final s in sessions) {
      for (final d in s.discomfortAreas) {
        if (d.discomfortBefore == null || d.discomfortAfter == null) continue;
        scored++;
        if (d.discomfortAfter! < d.discomfortBefore!) improved++;
      }
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _Tile(value: '${sessions.length}', label: 'Sessions')),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: _Tile(
              // Nothing scored yet → an em-dash, never a fabricated 0%.
              value: scored == 0
                  ? '—'
                  : '${((improved / scored) * 100).round()}%',
              label: 'Improved',
              tone: _Tone.good,
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: _Tile(
              value: '${sessions.where((s) => s.discomfortAreas.isNotEmpty).length}',
              label: 'Assessed',
              tone: _Tone.copper,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { ink, good, copper }

class _Tile extends StatelessWidget {
  final String value;
  final String label;
  final _Tone tone;

  const _Tile({
    required this.value,
    required this.label,
    this.tone = _Tone.ink,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final color = switch (tone) {
      _Tone.good => p.good,
      _Tone.copper => p.copperInk,
      _Tone.ink => p.ink,
    };

    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: HwType.xxl,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          gradient: filled ? p.sunGrad : null,
          color: filled ? null : p.card,
          borderRadius: BorderRadius.circular(HwRadius.sm),
          border: filled ? null : Border.all(color: p.cardline, width: 1.5),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : p.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// This client's sessions with their outcome result — the spec's last-six list.
class _SessionHistory extends StatelessWidget {
  final AsyncValue<List<SessionHistoryItem>> history;
  const _SessionHistory({required this.history});

  static const _max = 6;

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return history.when(
      loading: () => HwCard(
        child: Text(
          'Loading sessions…',
          style: TextStyle(fontSize: HwType.cap, color: p.ink3),
        ),
      ),
      error: (_, __) => HwCard(
        child: Text(
          "Couldn't load this client's sessions.",
          style: TextStyle(fontSize: HwType.sm, color: p.ink2),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return HwCard(
            child: Text(
              'No sessions logged yet — the first one will appear here.',
              style:
                  TextStyle(fontSize: HwType.sm, height: 1.45, color: p.ink2),
            ),
          );
        }
        return HwRowGroup(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            for (final s in sessions.take(_max)) _SessionRow(s),
          ],
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  final SessionHistoryItem session;
  const _SessionRow(this.session);

  @override
  Widget build(BuildContext context) {
    final first = session.protocols.isEmpty ? null : session.protocols.first;

    var scored = 0;
    var improved = 0;
    for (final d in session.discomfortAreas) {
      if (d.discomfortBefore == null || d.discomfortAfter == null) continue;
      scored++;
      if (d.discomfortAfter! < d.discomfortBefore!) improved++;
    }

    return HwRow(
      title: first?.protocol ?? 'Session',
      subtitle: _stamp(session.createdAt),
      trailing: scored == 0
          ? const HwPill('no check')
          : improved > 0
              ? const HwPill('improved ✓', tone: HwPillTone.good)
              : const HwPill('no change', tone: HwPillTone.low),
      onTap: () => context.push('/history/${session.id}', extra: session),
    );
  }

  static String _stamp(DateTime? at) {
    if (at == null) return '';
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} · '
        '${two(l.hour)}:${two(l.minute)}';
  }
}
