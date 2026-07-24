import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../ai_report/presentation/widgets/client_reports_section.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../devices/presentation/providers/players_provider.dart';
import '../../../devices/presentation/widgets/players_section.dart';
import '../../../devices/presentation/widgets/ref_palette.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/presentation/screens/history_list_screen.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';
import '../widgets/new_client_sheet.dart';

enum _UsersTab { users, reports, history }

/// The org roster (`GET clients`), grouped by sport — plus the AI Reports and
/// Session History lists as segments, which is where those two moved when this
/// screen took over the History slot in the nav bar.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  _UsersTab _tab = _UsersTab.users;

  bool get _isUniversity =>
      (ref.watch(authStateProvider).user?.organizationType ?? '')
          .toUpperCase() ==
      'UNIVERSITY';

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final university = _isUniversity;
    final clients = ref.watch(clientListProvider);
    final count = clients.asData?.value.length ?? 0;
    final orgName = ref.watch(authStateProvider).selectedOrgName ?? '';

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          university ? 'Users' : 'Clients',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: p.ink,
                          ),
                        ),
                      ),
                      _IconBtn(
                        icon: Icons.add_rounded,
                        color: p.copperInk,
                        palette: p,
                        onTap: () async {
                          university
                              ? await showAddPlayerSheet(context, ref)
                              : await showNewClientSheet(context, ref);
                          ref.invalidate(clientListProvider);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _OrgChip(
                    palette: p,
                    label: [
                      '$count ${count == 1 ? 'user' : 'users'}',
                      if (orgName.isNotEmpty) orgName,
                    ].join(' · '),
                  ),
                  const SizedBox(height: 14),
                  _Segments(
                    palette: p,
                    tab: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(p, university, clients)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    RefPalette p,
    bool university,
    AsyncValue<List<Client>> clients,
  ) {
    switch (_tab) {
      case _UsersTab.reports:
        return const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ClientReportsSection(),
        );
      case _UsersTab.history:
        // The History screen renders without its own title/Scaffold here — the
        // page header above already names the screen.
        return const HistoryListScreen(embedded: true);
      case _UsersTab.users:
        return clients.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Empty(
            palette: p,
            title: 'Couldn\'t load users',
            subtitle: 'Pull down to retry. ($e)',
            onRetry: () => ref.invalidate(clientListProvider),
          ),
          data: (all) => _roster(p, university, all),
        );
    }
  }

  Widget _roster(RefPalette p, bool university, List<Client> all) {
    if (all.isEmpty) {
      return _Empty(
        palette: p,
        title: university ? 'No users yet' : 'No clients yet',
        subtitle: university
            ? 'Tap + to add your first player.'
            : 'Tap + to add your first client.',
        onRetry: () => ref.invalidate(clientListProvider),
      );
    }

    // Session counts per user, from the same history feed the History tab
    // shows. Absent (still loading / failed) → the row just omits the count.
    final sessionCounts = <String, int>{};
    for (final s in ref.watch(allSessionsProvider).asData?.value ?? const []) {
      final id = s.clientId;
      if (id == null || id.isEmpty) continue;
      sessionCounts[id] = (sessionCounts[id] ?? 0) + 1;
    }

    // Position ObjectId → display name, from the org's sport mappings.
    final positionNames = <String, String>{};
    for (final sport
        in ref.watch(orgSportsProvider).asData?.value ?? const []) {
      for (final pos in sport.positions) {
        if (pos.id.isNotEmpty) positionNames[pos.id] = pos.name;
      }
    }

    // Group by sport (clinic clients have none → one unlabelled group).
    final groups = <String, List<Client>>{};
    for (final c in all) {
      final sport = (c.sport ?? '').trim();
      groups.putIfAbsent(sport.isEmpty ? '' : sport, () => []).add(c);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1; // the unlabelled group sinks to the bottom
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return RefreshIndicator(
      color: p.copperInk,
      onRefresh: () async {
        ref.invalidate(clientListProvider);
        ref.invalidate(allSessionsProvider);
        await ref.read(clientListProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          for (final key in sortedKeys) ...[
            _GroupHeader(
              palette: p,
              label: key.isEmpty
                  ? (university ? 'Users' : 'Clients')
                  : key.toUpperCase(),
              count: groups[key]!.length,
            ),
            const SizedBox(height: 8),
            _UserGroupCard(
              palette: p,
              clients: groups[key]!,
              university: university,
              sessionCounts: sessionCounts,
              positionNames: positionNames,
              onTap: (c) async {
                await context.pushNamed(
                  RouteNames.clientDetail,
                  extra: {'clientId': c.id, 'title': c.displayName},
                );
                ref.invalidate(clientListProvider);
              },
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final RefPalette palette;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.cardline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 21, color: color),
        ),
      ),
    );
  }
}

/// The copper "N users · Org" pill under the page title.
class _OrgChip extends StatelessWidget {
  final RefPalette palette;
  final String label;

  const _OrgChip({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: p.tanSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.copper),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: p.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final RefPalette palette;
  final _UsersTab tab;
  final ValueChanged<_UsersTab> onChanged;

  const _Segments({
    required this.palette,
    required this.tab,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardline),
      ),
      child: Row(
        children: [
          _seg('Users', _UsersTab.users, p),
          const SizedBox(width: 4),
          _seg('AI Reports', _UsersTab.reports, p),
          const SizedBox(width: 4),
          _seg('History', _UsersTab.history, p),
        ],
      ),
    );
  }

  Widget _seg(String label, _UsersTab value, RefPalette p) {
    final selected = tab == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1F2B33) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : p.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final RefPalette palette;
  final String label;
  final int count;

  const _GroupHeader({
    required this.palette,
    required this.label,
    required this.count,
  });

  /// Rough sport → glyph match; anything unrecognised gets the generic one.
  IconData get _icon {
    final l = label.toLowerCase();
    if (l.contains('football')) return Icons.sports_football_outlined;
    if (l.contains('basketball')) return Icons.sports_basketball_outlined;
    if (l.contains('soccer')) return Icons.sports_soccer_outlined;
    if (l.contains('baseball')) return Icons.sports_baseball_outlined;
    if (l.contains('hockey')) return Icons.sports_hockey_outlined;
    if (l.contains('tennis')) return Icons.sports_tennis_outlined;
    if (l.contains('user') || l.contains('client')) {
      return Icons.people_outline_rounded;
    }
    return Icons.sports_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Row(
      children: [
        Icon(_icon, size: 15, color: p.copper),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: p.ink2,
            ),
          ),
        ),
        Text(
          '$count ${count == 1 ? 'user' : 'users'}',
          style: TextStyle(fontSize: 12, color: p.ink3),
        ),
      ],
    );
  }
}

/// One sport's users, as divider-separated rows in a single card.
class _UserGroupCard extends StatelessWidget {
  final RefPalette palette;
  final List<Client> clients;
  final bool university;
  final Map<String, int> sessionCounts;
  final Map<String, String> positionNames;
  final void Function(Client) onTap;

  const _UserGroupCard({
    required this.palette,
    required this.clients,
    required this.university,
    required this.sessionCounts,
    required this.positionNames,
    required this.onTap,
  });

  /// Position name(s) for a player, resolved from the org's sport mappings.
  /// Falls back to the clinic subline (age · gender) for non-players.
  String _subline(Client c) {
    if (university) {
      final names = [
        for (final id in c.positions ?? const <String>[])
          if ((positionNames[id] ?? '').trim().isNotEmpty) positionNames[id]!,
      ];
      if (names.isNotEmpty) return names.join(' · ');
      return c.sport ?? 'Player';
    }
    final bits = <String>[
      if (c.age != null) '${c.age} yrs',
      if ((c.gender ?? '').trim().isNotEmpty) c.gender!,
    ];
    return bits.isEmpty ? 'Client' : bits.join(' · ');
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardline),
        boxShadow: p.shadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < clients.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: p.line),
            _UserRow(
              palette: p,
              client: clients[i],
              initials: _initials(clients[i].clientName),
              subline: _subline(clients[i]),
              sessions: sessionCounts[clients[i].id],
              onTap: () => onTap(clients[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final RefPalette palette;
  final Client client;
  final String initials;
  final String subline;
  final int? sessions;
  final VoidCallback onTap;

  const _UserRow({
    required this.palette,
    required this.client,
    required this.initials,
    required this.subline,
    required this.sessions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final count = sessions ?? 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1F2B33),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          client.clientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.ink,
                          ),
                        ),
                      ),
                      if (client.jerseyNumber != null &&
                          client.jerseyNumber! > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '#${client.jerseyNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.ink3,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.ink2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count ${count == 1 ? 'session' : 'sessions'}',
                    style: TextStyle(fontSize: 12, color: p.ink3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final RefPalette palette;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  const _Empty({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return RefreshIndicator(
      color: p.copperInk,
      onRefresh: () async => onRetry(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
        children: [
          Icon(Icons.people_outline_rounded, size: 42, color: p.ink3),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.ink3),
          ),
        ],
      ),
    );
  }
}
