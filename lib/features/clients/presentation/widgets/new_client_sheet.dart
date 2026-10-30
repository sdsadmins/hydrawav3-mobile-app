import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/extensions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../devices/presentation/providers/players_provider.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../../devices/presentation/widgets/session_plan_widgets.dart';
import '../../../intake/presentation/widgets/option_picker.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';

/// The one "Add client / athlete" sheet (v6 `55-intake`, "New client · athlete
/// intake"): name, nickname, age + gender, height, weight, then a "Sports
/// athlete" switch that opens sport, jersey and positions.
///
/// Off, it creates a clinic client (`POST /clients`; the server names it when
/// no name is given). On, it creates a player (memberType Player, sport,
/// positions). Age, height and weight are required either way — the backend
/// needs them. On success the new person is selected for the session and
/// returned.
Future<Client?> showAddClientAthleteSheet(
  BuildContext context,
  WidgetRef ref, {
  bool athlete = false,
}) {
  return showPlanSheet<Client>(
    context,
    title: 'New client · athlete intake',
    subtitle: 'Age, height and weight are required',
    builder: (_) => _ClientAthleteForm(startAsAthlete: athlete),
  );
}

/// Clinic entry points: the same sheet, athlete switch off.
Future<Client?> showNewClientSheet(BuildContext context, WidgetRef ref) =>
    showAddClientAthleteSheet(context, ref);

class _ClientAthleteForm extends ConsumerStatefulWidget {
  final bool startAsAthlete;
  const _ClientAthleteForm({required this.startAsAthlete});

  @override
  ConsumerState<_ClientAthleteForm> createState() => _ClientAthleteFormState();
}

class _ClientAthleteFormState extends ConsumerState<_ClientAthleteForm> {
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _age = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _pounds = TextEditingController();
  final _jersey = TextEditingController();
  String? _gender;
  late bool _athlete = widget.startAsAthlete;
  OrgSport? _sport; // null → the first fetched sport
  final Set<String> _positionIds = {}; // Position ObjectIds
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _nickname, _age, _feet, _inches, _pounds, _jersey]) {
      c.dispose();
    }
    super.dispose();
  }

  OrgSport? _effectiveSport(List<OrgSport> sports) =>
      _sport ?? (sports.isNotEmpty ? sports.first : null);

  void _snack(String msg) => context.showSnackBar(msg, isError: true);

  Future<void> _submit() async {
    final name = _name.text.trim();
    final nickname = _nickname.text.trim();
    final age = int.tryParse(_age.text.trim());
    final feet = int.tryParse(_feet.text.trim()) ?? 0;
    final inches = int.tryParse(_inches.text.trim()) ?? 0;
    final pounds = double.tryParse(_pounds.text.trim());
    // Feet/inches → cm and pounds → kg: the backend is metric (web parity).
    final height = (feet * 12 + inches) * 2.54;
    final weight = (pounds ?? 0) * 0.453592;

    if (_athlete && name.isEmpty) return _snack('Name required');
    if (age == null || age <= 0) return _snack('Enter a valid age');
    if (height <= 0) return _snack('Enter a valid height');
    if (pounds == null || pounds <= 0) {
      return _snack('Enter a valid weight (lbs)');
    }

    final auth = ref.read(authStateProvider);
    final orgId = int.tryParse(auth.selectedOrgId ?? '');
    if (orgId == null) return _snack('Select an organization first');

    final CreateClientRequest request;
    if (_athlete) {
      final sports =
          ref.read(orgSportsProvider).valueOrNull ?? const <OrgSport>[];
      final sport = _effectiveSport(sports);
      if (sport == null) {
        return _snack('No sports available for this organization');
      }
      // Positions default to the first if none chosen; sent as ObjectIds.
      final positionIds = _positionIds.isNotEmpty
          ? _positionIds.toList()
          : (sport.positions.isNotEmpty
              ? [sport.positions.first.id]
              : <String>[]);
      request = CreateClientRequest.player(
        clientName: name,
        organizationId: orgId,
        age: age,
        height: height,
        weight: weight,
        sport: sport.name,
        gender: _gender,
        nickname: nickname.isEmpty ? null : nickname,
        jerseyNumber: int.tryParse(_jersey.text.trim()),
        positions: positionIds,
      );
    } else {
      request = CreateClientRequest(
        age: age,
        height: height,
        weight: weight,
        organizationId: orgId,
        organizationName: auth.selectedOrgName ?? '',
        // optional for a client: the server names it when left empty
        clientName: name.isEmpty ? null : name,
        nickname: nickname.isEmpty ? null : nickname,
        gender: _gender,
      );
    }

    setState(() => _saving = true);
    try {
      final created = await ref.read(clientRepositoryProvider).create(request);
      ref.read(selectedClientProvider.notifier).state = created;
      ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
      ref.invalidate(clientListProvider);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        _snack('Failed to create ${_athlete ? 'athlete' : 'client'}: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sportsAsync = ref.watch(orgSportsProvider);
    final sports = sportsAsync.valueOrNull ?? const <OrgSport>[];
    // the athlete switch needs sports to pick from
    final canAthlete = sports.isNotEmpty || widget.startAsAthlete;
    final athlete = _athlete && canAthlete;
    final sport = _effectiveSport(sports);
    final digits = [FilteringTextInputFormatter.digitsOnly];

    Widget half(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
    Widget field(Widget label, Widget input) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [label, input],
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanFieldLabel('Name', tag: athlete ? null : 'optional'),
          PlanTextField(controller: _name, hint: 'e.g. Jordan Reyes'),
          const SizedBox(height: 12),
          const PlanFieldLabel('Nickname', tag: 'optional'),
          PlanTextField(controller: _nickname, hint: 'What you call them'),
          const SizedBox(height: 12),
          half(
            field(
              const PlanFieldLabel('Age'),
              PlanTextField(
                controller: _age,
                hint: 'Enter age',
                keyboardType: TextInputType.number,
                inputFormatters: digits,
              ),
            ),
            field(
              const PlanFieldLabel('Gender', tag: 'optional'),
              _SelectField(
                value: _gender,
                onTap: () async {
                  final picked = await showOptionPicker<String>(
                    context,
                    title: 'Gender',
                    options: const ['Male', 'Female', 'Other'],
                    labelOf: (v) => v,
                    selected: _gender,
                  );
                  if (picked != null) setState(() => _gender = picked);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          const PlanFieldLabel('Height'),
          half(
            PlanTextField(
              controller: _feet,
              hint: '0',
              unit: 'ft',
              keyboardType: TextInputType.number,
              inputFormatters: digits,
            ),
            PlanTextField(
              controller: _inches,
              hint: '0',
              unit: 'in',
              keyboardType: TextInputType.number,
              inputFormatters: digits,
            ),
          ),
          const SizedBox(height: 12),
          const PlanFieldLabel('Weight'),
          PlanTextField(
            controller: _pounds,
            hint: 'Enter weight',
            unit: 'lbs',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (canAthlete) ...[
            const SizedBox(height: 14),
            _AthleteToggle(
              on: athlete,
              onChanged: (v) => setState(() => _athlete = v),
            ),
            // `.v5i-sport`: sport, jersey and positions, opening under the
            // switch
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !athlete
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          half(
                            field(
                              const PlanFieldLabel('Sport'),
                              _sportField(sportsAsync, sports, sport),
                            ),
                            field(
                              const PlanFieldLabel('Jersey', tag: 'optional'),
                              PlanTextField(
                                controller: _jersey,
                                hint: '00',
                                keyboardType: TextInputType.number,
                                inputFormatters: digits,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const PlanFieldLabel('Positions',
                              tag: 'tap all that apply'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final pos in sport?.positions ??
                                  const <Position>[])
                                _PositionChip(
                                  label: pos.name,
                                  selected: _positionIds.contains(pos.id),
                                  onTap: () => setState(() {
                                    if (!_positionIds.remove(pos.id)) {
                                      _positionIds.add(pos.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 18),
          PlanPrimaryButton(
            label: athlete ? 'Create athlete' : 'Create client',
            busy: _saving,
            onTap: _submit,
          ),
        ],
      ),
    );
  }

  Widget _sportField(
    AsyncValue<List<OrgSport>> sportsAsync,
    List<OrgSport> sports,
    OrgSport? selected,
  ) {
    final sub = PlanTones.sub(context);
    if (sportsAsync.isLoading) {
      return PlanSelectBox(
        child: Text('Loading sports…', style: TextStyle(color: sub)),
      );
    }
    if (sports.isEmpty) {
      return PlanSelectBox(
        child: Text('No sports configured', style: TextStyle(color: sub)),
      );
    }
    return _SelectField(
      value: selected?.name,
      onTap: () async {
        final picked = await showOptionPicker<OrgSport>(
          context,
          title: 'Sport',
          options: sports,
          labelOf: (s) => s.name,
          selected: selected,
        );
        if (picked != null && picked.sportId != selected?.sportId) {
          setState(() {
            _sport = picked;
            _positionIds.clear();
          });
        }
      },
    );
  }
}

/// A tap-to-pick field in the intake's input style.
class _SelectField extends StatelessWidget {
  final String? value;
  final VoidCallback onTap;
  const _SelectField({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return PlanPress(
      onTap: onTap,
      child: PlanSelectBox(
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? 'Select',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: value == null
                      ? PlanTones.sub(context)
                      : (dark
                          ? const Color(0xFFF1E4D6)
                          : const Color(0xFF1A1A1A)),
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded,
                size: 20, color: PlanTones.sub(context)),
          ],
        ),
      ),
    );
  }
}

/// `.v5i-tog`: "Sports athlete" with its switch — copper-tinted when on.
class _AthleteToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _AthleteToggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Semantics(
      toggled: on,
      label: 'Sports athlete',
      child: PlanPress(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: on
                ? const Color.fromRGBO(198, 158, 131, .1)
                : (dark ? const Color(0xFF15171C) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: on
                  ? const Color(0xFFC69E83)
                  : (dark
                      ? const Color.fromRGBO(192, 157, 132, .28)
                      : const Color.fromRGBO(198, 158, 131, .55)),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sports athlete',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? const Color(0xFFF1E4D6)
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add a sport, jersey number and positions',
                      style: TextStyle(
                          fontSize: 12, color: PlanTones.sub(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // `.sw`: 46×28, the v6 copper gradient when on
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 46,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: on ? null : const Color(0xFFCBD5E1),
                  gradient: on
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                        )
                      : null,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 260),
                  curve: const Cubic(.34, 1.56, .64, 1),
                  alignment:
                      on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, .18),
                            blurRadius: 3,
                            offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.v5i-chip`: a position pill — solid copper when picked.
class _PositionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PositionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Semantics(
      button: true,
      selected: selected,
      child: PlanPress(
        onTap: onTap,
        scale: .94,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFB27D5C)
                : (dark ? const Color(0xFF15171C) : Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFFB27D5C)
                  : (dark
                      ? const Color.fromRGBO(192, 157, 132, .28)
                      : const Color.fromRGBO(198, 158, 131, .55)),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFF2B1D12)
                  : (dark ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A)),
            ),
          ),
        ),
      ),
    );
  }
}
