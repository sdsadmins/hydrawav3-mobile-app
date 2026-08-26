import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/data/client_repository.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../clients/presentation/widgets/new_client_sheet.dart';
import '../providers/players_provider.dart';
import 'ref_palette.dart';

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
    final isGuest =
        ref.watch(sessionClientModeProvider) == ClientMode.guest ||
            client == null;

    return _card(
      p,
      title: university ? 'Select User' : 'Select Client',
      addLabel: university ? 'Add User' : 'Add Client',
      onAdd: () => university
          ? showAddPlayerSheet(context, ref)
          : showNewClientSheet(context, ref),
      name: isGuest ? 'Guest' : client.clientName,
      initials: isGuest ? null : _initials(client.clientName),
      subline: isGuest
          ? 'Anonymous session, no profile saved'
          : (university ? _playerSubline(client) : _clientSubline(client)),
      onTapSelector: () =>
          showClientSelectSheet(context, ref, playersOnly: university),
    );
  }

  // Shared card layout: header (title + copper Add button) + selector row.
  Widget _card(
    RefPalette p, {
    required String title,
    required String addLabel,
    required VoidCallback onAdd,
    required String name,
    required String? initials,
    required String subline,
    required VoidCallback onTapSelector,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardline),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: p.copperInk),
                      const SizedBox(width: 3),
                      Text(
                        addLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: p.copperInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProtoDrop(
            palette: p,
            name: name,
            initials: initials,
            subline: subline,
            onTap: onTapSelector,
          ),
        ],
      ),
    );
  }
}

/// Client / player picker — Guest + the org's members (`clientListProvider`,
/// i.e. `getClients`). When [playersOnly] is set, only `memberType: "Player"`
/// rows show, with the player subline + "Add User".
Future<void> showClientSelectSheet(
  BuildContext context,
  WidgetRef ref, {
  bool playersOnly = false,
}) {
  final p = RefPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Consumer(
      builder: (ctx, r, _) {
        final clientsAsync = r.watch(clientListProvider);
        final selected = r.watch(selectedClientProvider);
        final isGuest =
            r.watch(sessionClientModeProvider) == ClientMode.guest ||
                selected == null;

        void pickGuest() {
          r.read(selectedClientProvider.notifier).state = null;
          r.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
          Navigator.of(ctx).pop();
        }

        void pickClient(Client c) {
          r.read(selectedClientProvider.notifier).state = c;
          r.read(sessionClientModeProvider.notifier).state = ClientMode.client;
          Navigator.of(ctx).pop();
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: p.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        playersOnly ? 'Select User' : 'Select Client',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (playersOnly) {
                          showAddPlayerSheet(context, ref);
                        } else {
                          showNewClientSheet(context, ref);
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 16, color: p.copperInk),
                            const SizedBox(width: 3),
                            Text(
                              playersOnly ? 'Add User' : 'Add Client',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: p.copperInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _WhoRow(
                  palette: p,
                  initials: null,
                  name: 'Guest',
                  subline: 'Anonymous session, no profile saved',
                  selected: isGuest,
                  onTap: pickGuest,
                ),
                clientsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Failed to load clients: $e',
                        style: TextStyle(fontSize: 13, color: p.ink2)),
                  ),
                  data: (clients) {
                    final rows = playersOnly
                        ? clients.where((c) => c.isPlayer).toList()
                        : clients;
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          playersOnly
                              ? 'No players yet. Tap Add User to create one.'
                              : 'No clients yet. Tap Add Client to create one.',
                          style: TextStyle(fontSize: 13, color: p.ink3),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final c in rows)
                          _WhoRow(
                            palette: p,
                            initials: PlayersSection._initials(c.clientName),
                            name: playersOnly ? c.clientName : c.displayName,
                            subline: playersOnly
                                ? PlayersSection._playerSubline(c)
                                : PlayersSection._clientSubline(c),
                            selected: !isGuest && selected.id == c.id,
                            onTap: () => pickClient(c),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
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
    return Material(
      color: p.card2,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: p.cardline, width: 1.5),
          ),
          child: Row(
            children: [
              // 34×34 avatar: pava (selected) or tan-soft guest icon.
              if (initials != null)
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.heroGrad,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    initials!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.tanSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: p.copperInk,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}


class _WhoRow extends StatelessWidget {
  final RefPalette palette;
  final String? initials;
  final String name;
  final String subline;
  final bool selected;
  final VoidCallback onTap;
  const _WhoRow({
    required this.palette,
    required this.initials,
    required this.name,
    required this.subline,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? p.tanSoft : p.card2,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? p.copper : p.cardline,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                if (initials != null)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: p.heroGrad,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      initials!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.tanSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_outline_rounded,
                        size: 18, color: p.copperInk),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: p.copper),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add Player sheet — port of `addPlayerSheet` (Name, Sport, Jersey#, chips) ─

Future<void> showAddPlayerSheet(BuildContext context, WidgetRef ref) {
  final p = RefPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddPlayerForm(palette: p),
    ),
  );
}

class _AddPlayerForm extends ConsumerStatefulWidget {
  final RefPalette palette;
  const _AddPlayerForm({required this.palette});

  @override
  ConsumerState<_AddPlayerForm> createState() => _AddPlayerFormState();
}

class _AddPlayerFormState extends ConsumerState<_AddPlayerForm> {
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _jersey = TextEditingController();
  final _age = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _pounds = TextEditingController();
  OrgSport? _sport; // null → default to the first fetched sport
  final Set<String> _positionIds = {}; // Position ObjectIds
  String? _gender;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    _jersey.dispose();
    _age.dispose();
    _feet.dispose();
    _inches.dispose();
    _pounds.dispose();
    super.dispose();
  }

  OrgSport? _effectiveSport(List<OrgSport> sports) =>
      _sport ?? (sports.isNotEmpty ? sports.first : null);

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim());
    final feet = int.tryParse(_feet.text.trim()) ?? 0;
    final inches = int.tryParse(_inches.text.trim()) ?? 0;
    final pounds = double.tryParse(_pounds.text.trim());
    // Feet/inches → cm and pounds → kg (backend is metric; web parity).
    final height = (feet * 12 + inches) * 2.54;
    final weight = (pounds ?? 0) * 0.453592;

    if (name.isEmpty) return _snack('Name required');
    if (age == null || age <= 0) return _snack('Enter a valid age');
    if (height <= 0) return _snack('Enter a valid height');
    if (pounds == null || pounds <= 0) return _snack('Enter a valid weight (lbs)');

    final sports = ref.read(orgSportsProvider).valueOrNull ?? const <OrgSport>[];
    final sport = _effectiveSport(sports);
    if (sport == null) return _snack('No sports available for this organization');

    final orgId = int.tryParse(ref.read(authStateProvider).selectedOrgId ?? '');
    if (orgId == null) return _snack('Select an organization first');

    // Positions default to the first if none chosen; sent as ObjectIds.
    final positionIds = _positionIds.isNotEmpty
        ? _positionIds.toList()
        : (sport.positions.isNotEmpty ? [sport.positions.first.id] : <String>[]);

    setState(() => _saving = true);
    try {
      final created = await ref.read(clientRepositoryProvider).create(
            CreateClientRequest.player(
              clientName: name,
              organizationId: orgId,
              age: age,
              height: height,
              weight: weight,
              sport: sport.name,
              gender: _gender,
              nickname:
                  _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
              jerseyNumber: int.tryParse(_jersey.text.trim()),
              positions: positionIds,
            ),
          );
      // Refresh the roster from getClients and select the new player.
      ref.invalidate(clientListProvider);
      ref.read(selectedClientProvider.notifier).state = created;
      ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack('Failed to create player: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final sportsAsync = ref.watch(orgSportsProvider);
    final sports = sportsAsync.valueOrNull ?? const <OrgSport>[];
    final sport = _effectiveSport(sports);
    final positions = sport?.positions ?? const <Position>[];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Add player',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 12),
            _label(p, 'Name'),
            _input(p, _name, hint: 'e.g., Jordan Reyes'),
            const SizedBox(height: 13),
            _label(p, 'Nickname (optional)'),
            _input(p, _nickname, hint: 'e.g., JR'),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(p, 'Sport'),
                      _sportDropdown(p, sportsAsync, sports, sport),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(p, 'Jersey # (optional)'),
                      _input(
                        p,
                        _jersey,
                        hint: '00',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _label(p, 'Position(s): tap all that apply'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Placements combine across every position selected.',
                style: TextStyle(fontSize: 12, color: p.ink3, height: 1.4),
              ),
            ),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final pos in positions)
                  _PosChip(
                    palette: p,
                    label: pos.name,
                    selected: _positionIds.contains(pos.id),
                    onTap: () => setState(() {
                      if (!_positionIds.remove(pos.id)) _positionIds.add(pos.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(p, 'Age'),
                      _input(
                        p,
                        _age,
                        hint: 'e.g., 22',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(p, 'Gender (optional)'),
                      _genderDropdown(p),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _label(p, 'Height'),
            Row(
              children: [
                Expanded(
                  child: _input(p, _feet,
                      hint: '0',
                      suffix: 'ft',
                      keyboardType: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _input(p, _inches,
                      hint: '0',
                      suffix: 'in',
                      keyboardType: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly]),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _label(p, 'Weight'),
            _input(p, _pounds,
                hint: 'e.g., 165',
                suffix: 'lbs',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 18),
            Material(
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _saving ? null : _submit,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.sunGrad,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA87B5C).withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Color(0xFF2B1D12)),
                          ),
                        )
                      : const Text(
                          'Add to roster',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.15,
                            color: Color(0xFF2B1D12),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(RefPalette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: p.ink2,
          ),
        ),
      );

  Widget _input(
    RefPalette p,
    TextEditingController controller, {
    String? hint,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: TextStyle(color: p.ink, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: p.ink3),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  suffix,
                  style: TextStyle(
                    color: p.ink2,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: p.card2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _inputBorder(p.line),
        enabledBorder: _inputBorder(p.line),
        focusedBorder: _inputBorder(p.copper),
      ),
    );
  }

  OutlineInputBorder _inputBorder(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: c, width: 1.5),
      );

  Widget _genderDropdown(RefPalette p) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.line, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gender,
          isExpanded: true,
          isDense: true,
          hint: Text('Select', style: TextStyle(color: p.ink3, fontSize: 14)),
          dropdownColor: p.card,
          icon: Icon(Icons.expand_more_rounded, color: p.ink2),
          style: TextStyle(color: p.ink, fontSize: 14),
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
      ),
    );
  }

  Widget _sportDropdown(
    RefPalette p,
    AsyncValue<List<OrgSport>> sportsAsync,
    List<OrgSport> sports,
    OrgSport? selected,
  ) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.line, width: 1.5),
      ),
      child: sportsAsync.when(
        loading: () => Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.copper),
            ),
            const SizedBox(width: 10),
            Text('Loading sports…',
                style: TextStyle(color: p.ink3, fontSize: 14)),
          ],
        ),
        error: (e, _) => Text('Failed to load sports',
            style: TextStyle(color: p.ink3, fontSize: 13)),
        data: (_) {
          if (sports.isEmpty) {
            return Text('No sports configured',
                style: TextStyle(color: p.ink3, fontSize: 14));
          }
          return DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected?.sportId,
              isExpanded: true,
              isDense: true,
              dropdownColor: p.card,
              icon: Icon(Icons.expand_more_rounded, color: p.ink2),
              style: TextStyle(color: p.ink, fontSize: 14),
              items: [
                for (final s in sports)
                  DropdownMenuItem(value: s.sportId, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() {
                _sport = sports.firstWhere((s) => s.sportId == v,
                    orElse: () => sports.first);
                _positionIds.clear();
              }),
            ),
          );
        },
      ),
    );
  }
}

/// `.chip` / `.chip.hot` — selectable position chip.
class _PosChip extends StatelessWidget {
  final RefPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PosChip({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: selected ? p.tanSoft : p.chipBg,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? p.copper : p.line,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? p.copperInk : p.ink,
            ),
          ),
        ),
      ),
    );
  }
}
