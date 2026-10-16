import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../ai_report/presentation/widgets/client_reports_section.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/session_history_model.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';
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

    final university =
        (ref.watch(authStateProvider).user?.organizationType ?? '')
                .toUpperCase() ==
            'UNIVERSITY';
    // "Prepped today ✓" — a University player with a session today.
    final now = DateTime.now();
    final preppedToday = university &&
        (history.valueOrNull ?? const <SessionHistoryItem>[]).any((s) {
          final at = s.createdAt?.toLocal();
          return at != null &&
              at.year == now.year &&
              at.month == now.month &&
              at.day == now.day;
        });
    final side = HwTablet.sidePadding(context, column: HwTablet.wide, phone: 18);

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
            padding: EdgeInsets.fromLTRB(side, 10, side, 108),
            children: [
              // ── header (v6 `openPlayer`) ──────────────────────────────────
              _Header(
                name: client?.displayName ?? title ?? 'Client',
                jersey: client?.jerseyNumber,
                subtitle: _subtitle(client),
                preppedToday: preppedToday,
                onBack: () => _back(context),
                onEdit: client == null
                    ? null
                    : () => showEditClientSheet(context, ref, client),
              ),
              const SizedBox(height: 14),

              _StatTiles(history: history),
              const SizedBox(height: HwSpace.s5),

              // The two things a practitioner does from a profile. Both carry
              // this client into the flow, so nobody re-picks them.
              const HwEyebrow('Pad placements'),
              Row(
                children: [
                  Expanded(
                    child: _PadTile(
                      label: 'Performance',
                      icon: Icons.bolt_rounded,
                      performance: true,
                      onTap: () =>
                          _startFlow(context, ref, client, 'performance'),
                    ),
                  ),
                  const SizedBox(width: HwSpace.s3),
                  Expanded(
                    child: _PadTile(
                      label: 'Recovery',
                      icon: Icons.waves_rounded,
                      performance: false,
                      onTap: () =>
                          _startFlow(context, ref, client, 'recovery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HwSpace.s4),

              // ── AI Mobility Reports ───────────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'AI Mobility Reports',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                    ClientReportsSection(clientId: clientId),
                    const SizedBox(height: 4),
                    _OutlineButton(
                      label: 'New Mobility Report',
                      icon: Icons.star_border_rounded,
                      onTap: () => _newReport(context, ref, client),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HwSpace.s3),

              // ── hand off a unit → the existing lease screen ──────────────
              _DarkButton(
                label: 'Hand off a unit',
                icon: Icons.key_rounded,
                onTap: () => context.push(
                  RoutePaths.clientLease,
                  extra: <String, dynamic>{
                    'clientId': clientId,
                    'title': client?.displayName ?? title,
                  },
                ),
              ),
              const SizedBox(height: HwSpace.s3),

              // ── history ───────────────────────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Session & outcome history',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _SessionHistory(history: history),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "New Mobility Report": the existing guided assessment, for this client.
  static void _newReport(BuildContext context, WidgetRef ref, Client? client) {
    if (client != null) {
      ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
      ref.read(selectedClientProvider.notifier).state = client;
    }
    context.push(RoutePaths.guidedAssessment);
  }

  static String? _subtitle(Client? c) {
    if (c == null) return null;
    final bits = <String>[
      // The full stored name, under the nickname (profile only).
      if (c.displayName != c.fullName) c.fullName,
      if (c.sport?.isNotEmpty == true) c.sport!,
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
                  ? '--'
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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

/// v6 profile header: back, name with the jersey, the line under it (and
/// "Prepped today ✓" for a University player), and Edit.
class _Header extends StatelessWidget {
  final String name;
  final int? jersey;
  final String? subtitle;
  final bool preppedToday;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  const _Header({
    required this.name,
    required this.jersey,
    required this.subtitle,
    required this.preppedToday,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.card,
                border: Border.all(color: p.cardline),
              ),
              child: Icon(Icons.chevron_left_rounded, color: p.ink2, size: 26),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: name),
                  if (jersey != null && jersey! > 0)
                    TextSpan(
                      text: '  #$jersey',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink3,
                      ),
                    ),
                ]),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              if (subtitle != null || preppedToday) ...[
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    if (subtitle != null) TextSpan(text: subtitle),
                    if (subtitle != null && preppedToday)
                      const TextSpan(text: ' · '),
                    if (preppedToday)
                      TextSpan(
                        text: 'Prepped today ✓',
                        style: TextStyle(color: p.good),
                      ),
                  ]),
                  style: TextStyle(fontSize: 13.5, color: p.ink3),
                ),
              ],
            ],
          ),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Edit',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onEdit,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.cardline),
                ),
                child: Center(
                  child: HwIcon(HwIcons.pencil, size: 20, color: p.ink2),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// White section card.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.cardline),
      ),
      child: child,
    );
  }
}

/// v6 Pad placements tile — copper Performance, navy Recovery.
class _PadTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool performance;
  final VoidCallback onTap;
  const _PadTile({
    required this.label,
    required this.icon,
    required this.performance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final fg = performance ? const Color(0xFF2B1D12) : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: HwPress(
        onTap: onTap,
        child: Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: performance ? p.sunGrad : null,
            color: performance ? null : const Color(0xFF1F2B33),
            borderRadius: BorderRadius.circular(18),
            boxShadow: performance ? p.shadow : null,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 34, color: fg),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: fg,
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
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.cardline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: p.ink),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: p.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DarkButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0xFF1F2B33),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ],
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
      loading: () => Text(
        'Loading sessions…',
        style: TextStyle(fontSize: HwType.cap, color: p.ink3),
      ),
      error: (_, __) => Text(
        "Couldn't load this client's sessions.",
        style: TextStyle(fontSize: HwType.sm, color: p.ink2),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Text(
            'No sessions logged yet. The first one will appear here.',
            style: TextStyle(fontSize: HwType.sm, height: 1.45, color: p.ink2),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < sessions.take(_max).length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.divider),
              _SessionRow(sessions[i]),
            ],
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
