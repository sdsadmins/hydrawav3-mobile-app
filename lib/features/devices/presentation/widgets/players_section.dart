import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../clients/presentation/widgets/new_client_sheet.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../history/data/history_repository.dart';
import 'plan_sheet.dart';
import 'ref_palette.dart';
import 'session_plan_widgets.dart';

/// The Session-Plan "Select User" / "Select Client" card (copper handoff design,
/// `renderSetup` + `styles.css`) — shown for ALL account types. The only
/// account-type difference: `organizationType == "UNIVERSITY"` shows **Players**
/// (local roster + Add Player), everyone else shows **Clients** (the real
/// Clients API + Add Client).
class PlayersSection extends ConsumerWidget {
  const PlayersSection({super.key});

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// Clinic client subline — age · gender · nickname.
  static String _clientSubline(Client c) {
    final bits = <String>[
      if (c.age != null) '${c.age} yrs',
      if (c.gender != null && c.gender!.trim().isNotEmpty) c.gender!,
      if (c.nickname != null && c.nickname!.trim().isNotEmpty) c.nickname!,
    ];
    return bits.isEmpty ? 'Client' : bits.join(' · ');
  }

  /// Player subline — sport · #jersey.
  static String _playerSubline(Client c) {
    final bits = <String>[
      if (c.sport != null && c.sport!.trim().isNotEmpty) c.sport!,
      if (c.jerseyNumber != null && c.jerseyNumber! > 0) '#${c.jerseyNumber}',
    ];
    return bits.isEmpty ? 'Player' : bits.join(' · ');
  }

  static bool _isUniversity(WidgetRef ref) =>
      (ref.watch(authStateProvider).user?.organizationType ?? '')
          .toUpperCase() ==
      'UNIVERSITY';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final university = _isUniversity(ref);

    // Both variants read the SAME Clients API (`getClients`); university filters
    // to players (`memberType: "Player"`) and uses the player subline / add form.
    final client = ref.watch(selectedClientProvider);
    final isGuest = ref.watch(sessionClientModeProvider) == ClientMode.guest ||
        client == null;

    return _card(
      p,
      title: university ? 'Select User' : 'Select Client',
      addLabel: university ? 'Add User' : 'Add Client',
      onAdd: () => university
          ? showAddPlayerSheet(context, ref)
          : showNewClientSheet(context, ref),
      name: isGuest ? 'Guest' : client.displayName,
      initials: isGuest ? null : _initials(client.displayName),
      subline: isGuest
          ? 'Anonymous session, no profile saved'
          : (university ? _playerSubline(client) : _clientSubline(client)),
      onTapSelector: () =>
          showClientSelectSheet(context, ref, playersOnly: university),
      // Tablet: the prototype's RECENT row (v6 `93-recent`).
      recent: HwTablet.of(context)
          ? _RecentRow(
              people: _recents(ref, university),
              selectedId: isGuest ? null : client.id,
              onGuest: () {
                ref.read(selectedClientProvider.notifier).state = null;
                ref.read(sessionClientModeProvider.notifier).state =
                    ClientMode.guest;
              },
              onPick: (c) {
                ref.read(selectedClientProvider.notifier).state = c;
                ref.read(sessionClientModeProvider.notifier).state =
                    ClientMode.client;
              },
            )
          : null,
    );
  }

  /// The 5 people most recently in a session (newest first), topped up from
  /// the roster when history is short — the prototype's `recents(5)`.
  static List<Client> _recents(WidgetRef ref, bool university) {
    final all = ref.watch(clientListProvider).valueOrNull ?? const <Client>[];
    final pool = university ? all.where((c) => c.isPlayer).toList() : all;
    final byId = {for (final c in pool) c.id: c};
    final sessions = [
      ...(ref.watch(allSessionsProvider).valueOrNull ?? const []),
    ]..sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final out = <Client>[];
    final seen = <String>{};
    for (final s in sessions) {
      final c = byId[s.clientId];
      if (c != null && seen.add(c.id)) out.add(c);
      if (out.length >= 5) return out;
    }
    for (final c in pool) {
      if (seen.add(c.id)) out.add(c);
      if (out.length >= 5) break;
    }
    return out;
  }

  // Shared card layout (v6 `#ry-ses-user`): uppercase label + "+ Add", then
  // the picker row. Same actions as before — Add opens the add sheet, the
  // row opens the picker.
  Widget _card(
    RefPalette p, {
    required String title,
    required String addLabel,
    required VoidCallback onAdd,
    required String name,
    required String? initials,
    required String subline,
    required VoidCallback onTapSelector,
    Widget? recent,
  }) {
    return Builder(builder: (context) {
      final dark = PlanTones.dark(context);
      final link = dark ? const Color(0xFFE2C0A2) : const Color(0xFFB98457);
      return PlanCard(
        neutralBorder: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: PlanEyebrow(title)),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: addLabel,
                  child: PlanPress(
                    onTap: onAdd,
                    scale: .94,
                    child: SizedBox(
                      height: 32,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 14, color: link),
                          const SizedBox(width: 3),
                          Text(
                            'Add',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: link,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ProtoDrop(
              palette: p,
              name: name,
              initials: initials,
              subline: subline,
              onTap: onTapSelector,
            ),
            if (recent != null) recent,
          ],
        ),
      );
    });
  }
}

/// `.v6rc`: a thin rule, "RECENT", then Guest + recent people as chips —
/// tapping one picks them, exactly like the Select sheet.
class _RecentRow extends StatelessWidget {
  final List<Client> people;
  final String? selectedId;
  final VoidCallback onGuest;
  final ValueChanged<Client> onPick;
  const _RecentRow({
    required this.people,
    required this.selectedId,
    required this.onGuest,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlanEyebrow('Recent'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _RecentChip(
                name: 'Guest',
                initials: 'GU',
                guest: true,
                on: selectedId == null,
                onTap: onGuest,
              ),
              for (final c in people)
                _RecentChip(
                  name: c.displayName,
                  initials: PlayersSection._initials(c.displayName),
                  on: selectedId == c.id,
                  onTap: () => onPick(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String name;
  final String initials;
  final bool guest;
  final bool on;
  final VoidCallback onTap;
  const _RecentChip({
    required this.name,
    required this.initials,
    required this.on,
    required this.onTap,
    this.guest = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card2 = dark ? const Color(0xFF212C33) : const Color(0xFFFBF8F5);
    return Semantics(
      button: true,
      selected: on,
      label: name,
      child: PlanPress(
        onTap: onTap,
        scale: .97,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(5, 0, 12, 0),
          decoration: BoxDecoration(
            color: on
                ? Color.alphaBlend(
                    Color.fromRGBO(198, 158, 131, dark ? .16 : .14), p.card)
                : card2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? const Color.fromRGBO(198, 158, 131, .75) : p.line),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: guest ? p.bg2 : null,
                    gradient: guest
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: dark
                                ? const [Color(0xFF3A4A57), Color(0xFF2A3742)]
                                : const [Color(0xFFEDDDCF), Color(0xFFDDC3AC)],
                          ),
                    border: guest ? Border.all(color: p.line) : null,
                  ),
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: guest
                          ? p.ink3
                          : (dark
                              ? const Color(0xFFE7D3C0)
                              : const Color(0xFF6B4A32)),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? p.ink : p.ink2,
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

/// Client / player picker — Guest + the org's members (`clientListProvider`,
/// i.e. `getClients`). When [playersOnly] is set, only `memberType: "Player"`
/// rows show, with the player subline + "Add User". Styled after the v6
/// `.ry-ses-dd` list: a search pill, then flat rows with the copper dot on the
/// one in use.
Future<void> showClientSelectSheet(
  BuildContext context,
  WidgetRef ref, {
  bool playersOnly = false,
}) {
  final dark = PlanTones.dark(context);
  final link = dark ? const Color(0xFFE2C0A2) : const Color(0xFFB98457);
  return showPlanSheet<void>(
    context,
    title: playersOnly ? 'Select User' : 'Select Client',
    headerAction: Builder(
      builder: (sheetContext) => Semantics(
        button: true,
        label: playersOnly ? 'Add User' : 'Add Client',
        child: PlanPress(
          onTap: () {
            Navigator.of(sheetContext).pop();
            if (playersOnly) {
              showAddPlayerSheet(context, ref);
            } else {
              showNewClientSheet(context, ref);
            }
          },
          scale: .94,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 16, color: link),
                const SizedBox(width: 3),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: link,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    builder: (_) => _WhoPicker(playersOnly: playersOnly),
  );
}

class _WhoPicker extends ConsumerStatefulWidget {
  final bool playersOnly;
  const _WhoPicker({required this.playersOnly});

  @override
  ConsumerState<_WhoPicker> createState() => _WhoPickerState();
}

class _WhoPickerState extends ConsumerState<_WhoPicker> {
  String _q = '';

  void _pickGuest() {
    ref.read(selectedClientProvider.notifier).state = null;
    ref.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
    Navigator.of(context).pop();
  }

  void _pickClient(Client c) {
    ref.read(selectedClientProvider.notifier).state = c;
    ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final playersOnly = widget.playersOnly;
    final clientsAsync = ref.watch(clientListProvider);
    final selected = ref.watch(selectedClientProvider);
    final isGuest = ref.watch(sessionClientModeProvider) == ClientMode.guest ||
        selected == null;
    final sub = PlanTones.sub(context);
    final q = _q.trim().toLowerCase();

    String subOf(Client c) => playersOnly
        ? PlayersSection._playerSubline(c)
        : PlayersSection._clientSubline(c);
    String nameOf(Client c) => c.displayName;

    Widget message(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Text(text, style: TextStyle(fontSize: 13, color: sub)),
        );

    final rows = <Widget>[
      if (q.isEmpty)
        _WhoRow(
          initials: null,
          name: 'Guest',
          subline: 'Anonymous session, no profile saved',
          selected: isGuest,
          onTap: _pickGuest,
        ),
      ...clientsAsync.when(
        loading: () => [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(PlanTones.copper),
                ),
              ),
            ),
          ),
        ],
        error: (e, _) => [message('Failed to load clients: $e')],
        data: (clients) {
          final all =
              playersOnly ? clients.where((c) => c.isPlayer).toList() : clients;
          if (all.isEmpty) {
            return [
              message(playersOnly
                  ? 'No players yet. Tap Add User to create one.'
                  : 'No clients yet. Tap Add Client to create one.'),
            ];
          }
          final list = q.isEmpty
              ? all
              : all
                  .where((c) =>
                      // shows the nickname, but search matches the full
                      // name and nickname too
                      '${nameOf(c)} ${c.clientName} ${c.nickname ?? ''} ${subOf(c)}'
                          .toLowerCase()
                          .contains(q))
                  .toList();
          if (list.isEmpty) return [message('No match.')];
          return [
            for (final c in list)
              _WhoRow(
                initials: PlayersSection._initials(c.displayName),
                name: nameOf(c),
                subline: subOf(c),
                selected: !isGuest && selected.id == c.id,
                onTap: () => _pickClient(c),
              ),
          ];
        },
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanSearchField(
          hint: playersOnly ? 'Search users…' : 'Search clients…',
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: PlanTones.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PlanTones.hairline(context)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: PlanTones.hairline(context)),
              itemBuilder: (_, i) => rows[i],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

/// `.protodrop` — inset selector: `.pava` (or guest icon) + name + subline +
/// `.chev`, on a card2 fill with a cardline border.
class _ProtoDrop extends StatelessWidget {
  final RefPalette palette;
  final String name;
  final String? initials;
  final String subline;
  final VoidCallback onTap;
  const _ProtoDrop({
    required this.palette,
    required this.name,
    required this.initials,
    required this.subline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dark = PlanTones.dark(context);
    return PlanPress(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          // the prototype's light grey line (not copper)
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // `.ry-ses-ava` — initials on warm pink, or a dashed "GU"
                // ring for Guest.
                if (initials != null)
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF1D4C4),
                    ),
                    child: Text(
                      initials!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7A5142),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CustomPaint(
                      painter: _DashedCircle(p.ink2.withValues(alpha: .75)),
                      child: Center(
                        child: Text(
                          'GU',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: p.ink2.withValues(alpha: .75),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Icon(Icons.expand_more_rounded,
                    size: 18,
                    color: dark
                        ? const Color(0xFFAFBCC6)
                        : const Color(0xFF948B82)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              // No line cap — full name always shown, wraps rather than
              // being clipped.
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: dark ? const Color(0xFFAFBCC6) : const Color(0xFF948B82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 2px dashed ring — the Guest avatar.
class _DashedCircle extends CustomPainter {
  final Color color;
  const _DashedCircle(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 1;
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const dashes = 14;
    const step = 2 * 3.141592653589793 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step,
          step * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// `.ry-ses-urow` — avatar, name + subline, and the copper dot when chosen.
class _WhoRow extends StatelessWidget {
  final String? initials;
  final String name;
  final String subline;
  final bool selected;
  final VoidCallback onTap;
  const _WhoRow({
    required this.initials,
    required this.name,
    required this.subline,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? (dark ? const Color(0xFF221D19) : PlanTones.warmFill)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  PlanAvatar(initials: initials),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // No line cap — full name always shown, wraps
                          // rather than being clipped.
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: dark
                                ? const Color(0xFFF1E4D6)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: PlanTones.sub(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    const PlanPickedDot(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add Player — the one "Add client / athlete" sheet, athlete switch on ──

Future<void> showAddPlayerSheet(BuildContext context, WidgetRef ref) =>
    showAddClientAthleteSheet(context, ref, athlete: true);
