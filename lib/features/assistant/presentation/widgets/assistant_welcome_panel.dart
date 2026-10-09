import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../../devices/presentation/widgets/session_plan_widgets.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/session_history_model.dart';
import '../../../home/presentation/providers/hub_stats_provider.dart';
import '../../../home/presentation/widgets/hub_modules.dart'
    show watchHubUnitsReady;
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';

/// v5 `58-assistant` — the Assistant's opening view on an empty
/// conversation: a greeting card with today's real numbers and Start a
/// session, the last people you worked with, and a grid of what the
/// Assistant does. It goes away as soon as anything is said or tapped.
class AssistantWelcomePanel extends ConsumerWidget {
  final bool university;
  final VoidCallback onPrepUser;
  final VoidCallback onRecovery;
  final VoidCallback onFindPads;

  const AssistantWelcomePanel({
    super.key,
    required this.university,
    required this.onPrepUser,
    required this.onRecovery,
    required this.onFindPads,
  });

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final d = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'yesterday';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.day}';
  }

  /// The last three people with a session, most recent first.
  static List<(Client, SessionHistoryItem)> _recent(
      List<SessionHistoryItem> sessions, List<Client> clients) {
    final byId = {for (final c in clients) c.id: c};
    final sorted = [...sessions]..sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final seen = <String>{};
    final out = <(Client, SessionHistoryItem)>[];
    for (final s in sorted) {
      final id = s.clientId;
      if (s.isGuest || id == null || id.isEmpty || !seen.add(id)) continue;
      final c = byId[id];
      if (c == null) continue;
      out.add((c, s));
      if (out.length == 3) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final user = ref.watch(authStateProvider).user;
    final first = (user?.firstName?.trim().isNotEmpty ?? false)
        ? user!.firstName!.trim()
        : (user?.displayName ?? '').trim().split(' ').first;
    final stats = ref.watch(hubStatsProvider).valueOrNull;
    final prepData =
        university ? ref.watch(gamePrepProvider(null)).valueOrNull : null;
    // A team with no players on the roster yet reads as sessions today.
    final prep = (prepData == null ||
            prepData.prepped.length + prepData.left.length == 0)
        ? null
        : prepData;
    final units = watchHubUnitsReady(ref);
    final credits = ref.watch(tokenBalanceProvider);
    final sessions = ref.watch(allSessionsProvider).valueOrNull;
    final clients = ref.watch(clientListProvider).valueOrNull;
    final recent = (sessions == null || clients == null)
        ? const <(Client, SessionHistoryItem)>[]
        : _recent(sessions, clients);

    final strong = TextStyle(fontWeight: FontWeight.w800, color: p.ink);
    final facts = <InlineSpan>[
      if (prep != null) ...[
        TextSpan(text: '${prep.prepped.length}', style: strong),
        TextSpan(
            text:
                ' of ${prep.prepped.length + prep.left.length} prepped today'),
      ] else if (stats != null) ...[
        TextSpan(text: '${stats.sessionsToday}', style: strong),
        TextSpan(text: ' session${stats.sessionsToday == 1 ? '' : 's'} today'),
      ],
      if (units.total > 0) ...[
        const TextSpan(text: ' · '),
        TextSpan(text: '${units.ready}', style: strong),
        TextSpan(
            text: ' of ${units.total} unit${units.total == 1 ? '' : 's'} '
                'ready'),
      ],
      if (credits != null) ...[
        const TextSpan(text: ' · '),
        TextSpan(
          text: credits == credits.roundToDouble()
              ? '${credits.round()}'
              : credits.toStringAsFixed(1),
          style: strong,
        ),
        const TextSpan(text: ' credits left on the plan'),
      ],
    ];
    // Drop a leading separator when the first fact is missing.
    if (facts.isNotEmpty &&
        facts.first is TextSpan &&
        (facts.first as TextSpan).text == ' · ') {
      facts.removeAt(0);
    }

    void go(String path) => context.go(path);

    // The squad tiles need a team roster (Game Prep). Clinic accounts see
    // them as placeholders — the grid keeps the prototype's six tiles.
    void teamsOnly() => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Available on team accounts.')),
        );

    final tiles = <_Tile>[
      _Tile(Icons.bolt_outlined, 'Prep a user', 'readiness then protocol',
          onPrepUser),
      _Tile(Icons.groups_outlined, 'Prep the squad', 'who still needs one',
          university ? () => go(RoutePaths.home) : teamsOnly,
          placeholder: !university),
      _Tile(Icons.waves_rounded, 'Recovery', 'after training or a game',
          onRecovery),
      _Tile(Icons.scatter_plot_outlined, 'Find pad placements',
          'Sun & Moon on the body', onFindPads),
      _Tile(Icons.assignment_outlined, 'Game Ready board', 'the whole roster',
          university ? () => go(RoutePaths.users) : teamsOnly,
          placeholder: !university),
      _Tile(Icons.history_rounded, 'Past sessions', 'history and outcomes',
          () => go(RoutePaths.history)),
    ];

    // Tablet (v6 `97-tablet`): the greeting card is a narrow centred card
    // and the pick-up rows sit in the 680px reading column; the tiles keep
    // the full width, two across. Phone is unchanged.
    final tablet = HwTablet.of(context);
    Widget column(double max, Widget child) => tablet
        ? Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: max),
              child: child,
            ),
          )
        : child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── greeting card ──────────────────────────────────────────────────
        column(
            420,
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.cardline),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: PlanTones.dark(context)
                      ? const [Color(0xFF2A2420), Color(0xFF1C1F26)]
                      : const [Color(0xFFF6E9DC), Color(0xFFFBF7F3)],
                ),
                boxShadow: p.shadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_greeting(DateTime.now())}${first.isEmpty ? '' : ', $first'}',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: facts),
                      style:
                          TextStyle(fontSize: 14, height: 1.45, color: p.ink2),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PlanPrimaryButton(
                    label: '▶  Start a session',
                    onTap: () => go(RoutePaths.devices),
                  ),
                ],
              ),
            )),

        // ── pick up where you left off ─────────────────────────────────────
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          const _Eyebrow('Pick up where you left off'),
          for (final (c, s) in recent)
            column(
                HwTablet.read,
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PickUpRow(
                    client: c,
                    line: [
                      if (s.protocols.isNotEmpty &&
                          (s.protocols.first.protocol?.trim().isNotEmpty ??
                              false))
                        s.protocols.first.protocol!.trim(),
                      _when(s.createdAt),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    onTap: () {
                      // Session Plan with this person already selected.
                      ref.read(selectedClientProvider.notifier).state = c;
                      ref.read(sessionClientModeProvider.notifier).state =
                          ClientMode.client;
                      go(RoutePaths.devices);
                    },
                  ),
                )),
        ],

        // ── what I can do ──────────────────────────────────────────────────
        const SizedBox(height: 18),
        const _Eyebrow('What I can do'),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in tiles) SizedBox(width: w, child: _TileCard(t)),
            ],
          );
        }),
        const SizedBox(height: 16),
        Text(
          'Or just ask — try “pads for a tight hamstring”.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: p.ink3),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: RefPalette.of(context).ink3,
          ),
        ),
      );
}

class _PickUpRow extends StatelessWidget {
  final Client client;
  final String line;
  final VoidCallback onTap;
  const _PickUpRow({
    required this.client,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final initials = client.clientName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.cardline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.tanSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: p.copperInk,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.ink3),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  /// Shown but not available for this account (dimmed, "Teams" tag).
  final bool placeholder;
  const _Tile(this.icon, this.title, this.sub, this.onTap,
      {this.placeholder = false});
}

class _TileCard extends StatelessWidget {
  final _Tile t;
  const _TileCard(this.t);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      label: t.placeholder
          ? '${t.title}, available on team accounts'
          : '${t.title}, ${t.sub}',
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: t.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.cardline),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(t.icon,
                          size: 24, color: t.placeholder ? p.ink3 : p.ink2),
                      const Spacer(),
                      if (t.placeholder)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.bg2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Teams',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: p.ink3,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.placeholder ? p.ink3 : p.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.sub,
                    style: TextStyle(fontSize: 12.5, color: p.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
