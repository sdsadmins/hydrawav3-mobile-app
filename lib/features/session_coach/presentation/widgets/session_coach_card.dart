import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../data/coach_plan_store.dart';
import '../../data/session_coach_repository.dart';
import '../../domain/session_coach_models.dart';
import 'coach_body_view.dart';

/// A unit on the Session Plan the coach can assign a set to.
class CoachUnit {
  final String id;
  final String name;
  final String? macAddress;
  final Map<String, dynamic>? advancedSettings;

  /// BLE-connected: Locate is offered (same rule as the unit card).
  final bool canLocate;

  const CoachUnit({
    required this.id,
    required this.name,
    this.macAddress,
    this.advancedSettings,
    this.canLocate = false,
  });
}

/// Which units the coach has planned this visit: deviceId → "Knee · Set 1".
final sessionCoachPlannedProvider =
    StateProvider<Map<String, String>>((ref) => const {});

/// The v6 Session Coach (prototype `35-coach` + `B0-coach`) on Session Plan:
///   1 Body  — "What are we working on?" (every body part)
///   2 Goal  — Support activation / Support recovery (what the coach has)
///   3 Sets  — the admin's 3D pads per set, a device and a protocol per set,
///             Locate, the start delay between two sets (B0-coach
///             `jointHTML`) with Swap, and "Use this set".
/// "Use this set" puts the protocol on the chosen unit through the screen's
/// own protocol-apply path ([onApply]), then that set's start time on the
/// same unit's Start Delay ([onSetDelay]).
class SessionCoachCard extends ConsumerStatefulWidget {
  final List<CoachUnit> units;
  final Future<bool> Function(String deviceId, String protocolId) onApply;
  final void Function(String deviceId, Map<String, dynamic> settings)?
      onApplyAdvancedSettings;
  final Map<String, dynamic>? Function(String deviceId)?
      advancedSettingsForDevice;
  final void Function(String deviceId) onLocate;

  /// Sets a unit's Start Delay, in seconds from Start (the unit card's Delay).
  final void Function(String deviceId, int seconds)? onSetDelay;

  /// Test seam: the 3D body is a WebView, which widget tests can't host.
  final Widget Function(List<Map<String, dynamic>> markers)? bodyBuilder;

  const SessionCoachCard({
    super.key,
    required this.units,
    required this.onApply,
    this.onApplyAdvancedSettings,
    this.advancedSettingsForDevice,
    required this.onLocate,
    this.onSetDelay,
    this.bodyBuilder,
  });

  @override
  ConsumerState<SessionCoachCard> createState() => _SessionCoachCardState();
}

class _SessionCoachCardState extends ConsumerState<SessionCoachCard> {
  bool _open = false;
  int _step = 0;

  /// The unit tab ("for Unit 1"): the first set's default device in step 3.
  String? _unitId;

  String? get _tabUnit {
    final ids = widget.units.map((u) => u.id).toList();
    if (ids.isEmpty) return null;
    if (_unitId != null && ids.contains(_unitId)) return _unitId;
    final planned = ref.read(sessionCoachPlannedProvider);
    return ids.firstWhere((id) => !planned.containsKey(id),
        orElse: () => ids.first);
  }

  CoachBodyPart? _body;
  String? _goal;
  int _setIndex = 0;
  final GlobalKey _selectedBodyPartKey = GlobalKey();
  final Map<int, String> _deviceBySet = {};
  final Map<int, String> _protocolBySet = {};

  /// Delay before set i starts, after the set before it (set 0 starts at
  /// Start). A set's start time is the sum up to it, so changing one delay
  /// moves every later set with it, as in the prototype.
  final Map<int, int> _gapBySet = {};

  /// The unit each set ran on last time (from the client's saved plan). Only
  /// a suggestion until "Use this set" puts it on.
  final Map<int, String> _unitHintBySet = {};
  final Map<int, Map<String, dynamic>> _advancedSettingsBySet = {};
  CoachPlanRecord? _loadedPlan;
  int _clientLoadGeneration = 0;

  /// The coach step 3 is showing, for saving from a delay change.
  SessionCoach? _shownCoach;

  /// Sets "Use this set" has put on a unit (protocol + start delay).
  final Set<int> _appliedSets = {};
  bool _applying = false;
  List<GlobalKey> _setKeys = const [];

  void _reset() {
    setState(() {
      _step = 0;
      _body = null;
      _goal = null;
      _loadedPlan = null;
      _setIndex = 0;
      _deviceBySet.clear();
      _protocolBySet.clear();
      _gapBySet.clear();
      _unitHintBySet.clear();
      _advancedSettingsBySet.clear();
      _loadedPlan = null;
      _appliedSets.clear();
    });
    ref.read(sessionCoachRunProvider.notifier).state = null;
  }

  void _back() {
    _clientLoadGeneration++;
    setState(() {
      _step = (_step - 1).clamp(0, 2);
    });
  }

  static String _goalShort(String g) =>
      g == kSupportActivation ? 'Support activation' : 'Support recovery';

  // ── the client's own plan (saved on the phone; see CoachPlanStore) ─────────
  /// The client this plan belongs to, or null for a guest (nothing to file
  /// it under).
  String? get _clientId {
    if (ref.read(sessionClientModeProvider) == ClientMode.guest) return null;
    return ref.read(selectedClientProvider)?.id;
  }

  String get _orgId => ref.read(authStateProvider).selectedOrgId ?? 'org';

  bool _isBodySelected(CoachBodyPart part) {
    final selected = _body;
    if (selected == null) return false;
    if (selected.id.trim().toLowerCase() == part.id.trim().toLowerCase()) {
      return true;
    }
    String normalizeName(String name) =>
        name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalizeName(selected.name) == normalizeName(part.name);
  }

  CoachPlanRecord? _savedPlan() {
    final client = _clientId;
    if (client == null) return null;
    return _savedPlanFor(client);
  }

  CoachPlanRecord? _savedPlanFor(String clientId) =>
      ref.read(coachPlanStoreProvider).load(_orgId, clientId);

  Future<void> _loadLatestForSelectedClient(String clientId) async {
    final generation = ++_clientLoadGeneration;
    if (ref.read(sessionClientModeProvider) != ClientMode.client ||
        ref.read(selectedClientProvider)?.id != clientId) {
      return;
    }

    final localPlan = _savedPlanFor(clientId);
    if (localPlan != null) {
      _restorePlan(localPlan, showMessage: false, applyToDevices: false);
    }

    try {
      final remotePlan =
          await ref.read(sessionCoachRepositoryProvider).recentPlan(clientId);
      if (!mounted ||
          generation != _clientLoadGeneration ||
          ref.read(selectedClientProvider)?.id != clientId) {
        return;
      }
      if (remotePlan != null) {
        _restorePlan(remotePlan, showMessage: false, applyToDevices: false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Latest session loaded — review it or repeat it.'),
          duration: Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (!mounted ||
          generation != _clientLoadGeneration ||
          ref.read(selectedClientProvider)?.id != clientId) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(localPlan == null
            ? 'Couldn’t load their latest Session Coach setup: $e'
            : 'Couldn’t refresh their latest setup. Using this device’s copy.'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Puts a saved plan's protocols, units and start delays back on the sets.
  /// Units stay suggestions until "Use this set".
  void _fillFrom(CoachPlanRecord plan) {
    _protocolBySet.clear();
    _gapBySet.clear();
    _unitHintBySet.clear();
    _advancedSettingsBySet.clear();
    _appliedSets.clear();
    _loadedPlan = plan;
    final sets = [...plan.sets]..sort((a, b) => a.index.compareTo(b.index));
    var prev = 0;
    for (final set in sets) {
      if (set.protocolId != null) _protocolBySet[set.index] = set.protocolId!;
      if (set.unitId != null) _unitHintBySet[set.index] = set.unitId!;
      if (set.advancedSettings != null) {
        _advancedSettingsBySet[set.index] = set.advancedSettings!;
      }
      if (set.index > 0) {
        final gap = set.startAt - prev;
        if (gap > 0) _gapBySet[set.index] = gap;
      }
      prev = set.startAt;
    }
    _setIndex = sets.first.index;
  }

  /// Same client, same body part and goal as last time: their own numbers
  /// come back instead of a blank plan.
  void _prefillSaved() {
    if (_loadedPlan?.bodyPartId == _body?.id && _loadedPlan?.goal == _goal) {
      return;
    }
    final plan = _savedPlan();
    if (plan == null || plan.bodyPartId != _body?.id || plan.goal != _goal) {
      return;
    }
    _fillFrom(plan);
  }

  /// Game Prep START: reopen this client's last plan at placement.
  Future<void> _restoreRequested(String clientId) async {
    ref.read(coachRestoreRequestProvider.notifier).state = null;
    if (clientId != _clientId) return;
    final localPlan = _savedPlan();
    if (localPlan != null) {
      _restorePlan(localPlan, applyToDevices: false);
    }
    try {
      final remotePlan =
          await ref.read(sessionCoachRepositoryProvider).recentPlan(clientId);
      if (remotePlan != null && mounted) {
        _restorePlan(remotePlan, showMessage: localPlan == null);
      } else if (localPlan != null && mounted) {
        unawaited(_applyRestoredPlan(localPlan));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(localPlan == null
            ? 'Couldn’t load their saved Session Coach setup: $e'
            : 'Couldn’t refresh their saved setup. Using this device’s copy.'),
        duration: const Duration(seconds: 4),
      ));
      if (localPlan != null) unawaited(_applyRestoredPlan(localPlan));
      if (localPlan == null) return;
    }
    if (localPlan == null && !mounted) return;
  }

  void _restorePlan(
    CoachPlanRecord plan, {
    bool showMessage = true,
    bool applyToDevices = true,
  }) {
    if (!mounted) return;
    setState(() {
      _deviceBySet.clear();
      _loadedPlan = plan;
      _open = true;
      _body = CoachBodyPart(id: plan.bodyPartId, name: plan.bodyPartName);
      _goal = plan.goal;
      _step = 2;
      _fillFrom(plan);
    });
    if (applyToDevices) unawaited(_applyRestoredPlan(plan));
    if (showMessage) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Loaded their last setup — change anything'),
          duration: Duration(seconds: 3)));
    }
  }

  Future<void> _applyRestoredPlan(CoachPlanRecord plan) async {
    final appliedIndexes = <int>{};
    for (final set in [...plan.sets]
      ..sort((a, b) => a.index.compareTo(b.index))) {
      final savedUnitId = set.unitId;
      final protocolId = set.protocolId;
      if (savedUnitId == null || protocolId == null) continue;
      final normalizedId = savedUnitId.trim().toUpperCase();
      final unit = widget.units
          .where((u) =>
              u.id == savedUnitId ||
              u.macAddress?.trim().toUpperCase() == normalizedId)
          .firstOrNull;
      if (unit == null) continue;

      final applied = await widget.onApply(unit.id, protocolId);
      if (!mounted) return;
      if (!applied) continue;
      final settings = set.advancedSettings;
      if (settings != null) {
        widget.onApplyAdvancedSettings?.call(unit.id, settings);
      }
      widget.onSetDelay?.call(unit.id, set.startAt);
      setState(() {
        _deviceBySet[set.index] = unit.id;
        _appliedSets.add(set.index);
      });
      appliedIndexes.add(set.index);
      ref.read(sessionCoachPlannedProvider.notifier).update(
            (m) => {
              ...m,
              unit.id: '${plan.bodyPartName} · Set ${set.index + 1}',
            },
          );
    }
    if (plan.run != null && appliedIndexes.isNotEmpty) {
      final appliedRun = appliedIndexes.length == plan.run!.sets.length
          ? plan.run!
          : plan.run!.copyWith(
              sets: plan.run!.sets
                  .where((set) => appliedIndexes.contains(set.index))
                  .toList(),
            );
      ref.read(sessionCoachRunProvider.notifier).state =
          appliedRun.isValid ? appliedRun : null;
    }
  }

  Future<void> _repeatLoadedPlan() async {
    final plan = _loadedPlan;
    if (plan == null || _applying) return;
    final alreadyApplied = _appliedSets.length;
    setState(() => _applying = true);
    try {
      await _applyRestoredPlan(plan);
      if (!mounted) return;
      final appliedNow = _appliedSets.length - alreadyApplied;
      final available = plan.sets.where((set) {
        final savedUnitId = set.unitId?.trim().toUpperCase();
        return savedUnitId != null &&
            widget.units.any((unit) =>
                unit.id == set.unitId ||
                unit.macAddress?.trim().toUpperCase() == savedUnitId);
      }).length;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(appliedNow > 0
            ? 'Last session applied to $appliedNow of $available '
                '${available == 1 ? 'set' : 'sets'}. Ready to start.'
            : available == 0
                ? 'Connect the devices from their last session to repeat it.'
                : 'Couldn’t apply the last session to connected devices. '
                    'Check the connection and try again.'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Couldn’t repeat the last session: $e')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _restoreHistoryPlan() {
    final plan = ref.read(coachHistoryRestoreRequestProvider);
    ref.read(coachHistoryRestoreRequestProvider.notifier).state = null;
    if (plan == null) return;
    _restorePlan(plan);
  }

  SessionCoachRun? _sessionCoachRun(SessionCoach coach) {
    final body = _body;
    final goal = _goal;
    if (body == null || goal == null) return null;
    final sets = coach.setsFor(goal);
    final runSets = <SessionCoachRunSet>[];
    for (final i in _appliedSets.toList()..sort()) {
      if (i < 0 || i >= sets.length) continue;
      final protocolId = _protocolFor(i, coach);
      final unitId = _deviceBySet[i];
      final unit = widget.units.where((u) => u.id == unitId).firstOrNull;
      final suppliedMacAddress = unit?.macAddress?.trim();
      final macAddress =
          suppliedMacAddress == null || suppliedMacAddress.isEmpty
              ? unitId
              : suppliedMacAddress;
      if (protocolId == null ||
          unitId == null ||
          macAddress == null ||
          macAddress.isEmpty) {
        continue;
      }
      final protocolRef =
          coach.protocolsFor(goal).where((p) => p.id == protocolId).firstOrNull;
      final protocolName = protocolRef?.name.isNotEmpty == true
          ? protocolRef!.name
          : ref
                  .read(protocolDetailProvider(protocolId))
                  .valueOrNull
                  ?.templateName ??
              '';
      runSets.add(SessionCoachRunSet(
        index: i,
        setId: sets[i].id,
        name: sets[i].name,
        protocolId: protocolId,
        protocolName: protocolName,
        macAddress: macAddress,
        startDelay: _startOf(i),
      ));
    }
    final run = SessionCoachRun(
      sessionCoachId: coach.id,
      bodyPartId: body.id,
      bodyPartName: body.name,
      supportType: goal,
      sets: runSets,
    );
    return run.isValid ? run : null;
  }

  /// Saves what is on the units now as this client's plan.
  Future<void> _savePlan(SessionCoach coach) async {
    final body = _body;
    final goal = _goal;
    if (body == null || goal == null || _appliedSets.isEmpty) return;
    final run = _sessionCoachRun(coach);
    ref.read(sessionCoachRunProvider.notifier).state = run;
    final client = _clientId;
    if (client == null || run == null) return;
    final sets = coach.setsFor(goal);
    await ref.read(coachPlanStoreProvider).save(
          _orgId,
          client,
          CoachPlanRecord(
            bodyPartId: body.id,
            bodyPartName: body.name,
            goal: goal,
            savedAt: DateTime.now(),
            sets: [
              for (var i = 0; i < sets.length; i++)
                CoachPlanSet(
                  index: i,
                  setId: sets[i].id,
                  name: sets[i].name,
                  protocolId: _protocolFor(i, coach),
                  protocolName: coach
                      .protocolsFor(goal)
                      .where((p) => p.id == _protocolFor(i, coach))
                      .map((p) => p.name)
                      .firstOrNull,
                  unitId: widget.units
                          .where((unit) => unit.id == _deviceBySet[i])
                          .firstOrNull
                          ?.macAddress ??
                      _deviceBySet[i],
                  advancedSettings: _deviceBySet[i] == null
                      ? _advancedSettingsBySet[i]
                      : widget.advancedSettingsForDevice
                              ?.call(_deviceBySet[i]!) ??
                          _advancedSettingsBySet[i],
                  startAt: _startOf(i),
                ),
            ],
            run: run,
          ),
        );
  }

  /// The set's protocol: the one chosen (if this coach still offers it),
  /// else the coach's default.
  String? _protocolFor(int idx, SessionCoach coach) {
    final chosen = _protocolBySet[idx];
    final protocols = coach.protocolsFor(_goal);
    if (chosen != null && protocols.any((p) => p.id == chosen)) return chosen;
    final savedProtocol = _loadedPlan?.sets
        .where((set) => set.index == idx && set.protocolId != null)
        .firstOrNull
        ?.protocolId;
    if (savedProtocol != null) return savedProtocol;
    return protocols.isNotEmpty ? protocols.first.id : null;
  }

  @override
  void initState() {
    super.initState();
    // A START that landed before this card was built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(coachRestoreRequestProvider);
      final historyPlan = ref.read(coachHistoryRestoreRequestProvider);
      if (pending != null) unawaited(_restoreRequested(pending));
      _restoreHistoryPlan();
      final client = ref.read(selectedClientProvider);
      if (pending == null &&
          historyPlan == null &&
          client != null &&
          ref.read(sessionClientModeProvider) == ClientMode.client) {
        unawaited(_loadLatestForSelectedClient(client.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Another client picked: their plan is theirs, so start over rather than
    // carry this client's units and delays across. Load their latest setup.
    ref.listen(selectedClientProvider, (prev, next) {
      if (prev?.id != next?.id) {
        _clientLoadGeneration++;
        _reset();
        if (next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_loadLatestForSelectedClient(next.id));
          });
        }
      }
    });
    ref.listen<String?>(coachRestoreRequestProvider, (_, next) {
      if (next != null) unawaited(_restoreRequested(next));
    });
    ref.listen<CoachPlanRecord?>(coachHistoryRestoreRequestProvider, (_, next) {
      if (next != null) _restoreHistoryPlan();
    });
    final p = RefPalette.of(context);
    final planned = ref.watch(sessionCoachPlannedProvider);
    final unitIds = widget.units.map((u) => u.id).toSet();
    final plannedHere = planned.keys.where(unitIds.contains).length;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.cardline),
        boxShadow: p.shadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── header ──────────────────────────────────────────────────────
          // Closed: the prototype's coach capsule (`.v5c-call`). Open: the
          // same face + title with a collapse button.
          if (!_open)
            _ClosedCall(
              planned: plannedHere,
              units: widget.units.length,
              onTap: () => setState(() => _open = true),
            )
          else
            Semantics(
              button: true,
              label: 'Collapse session coach',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _open = false),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.card,
                        border: Border.all(color: p.cardline),
                      ),
                      child: const CoachMascot(size: 34),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Session coach',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: p.ink)),
                          Text(
                            widget.units.isEmpty
                                ? 'Connect a unit to plan it'
                                : '$plannedHere of ${widget.units.length} planned',
                            style: TextStyle(fontSize: 12.5, color: p.ink3),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p.cardline),
                      ),
                      child:
                          Icon(Icons.keyboard_arrow_up_rounded, color: p.ink2),
                    ),
                  ],
                ),
              ),
            ),
          if (_open) ...[
            if (widget.units.isNotEmpty) ...[
              const SizedBox(height: 12),
              _UnitTabs(
                units: widget.units,
                selected: _tabUnit,
                planned: ref.watch(sessionCoachPlannedProvider),
                onPick: (id) {
                  setState(() {
                    _unitId = id;
                    // a new unit starts its own plan on step 1
                    _step = 0;
                    _body = null;
                    _goal = null;
                    _loadedPlan = null;
                    _setIndex = 0;
                    _deviceBySet.clear();
                    _protocolBySet.clear();
                  });
                  ref.read(sessionCoachRunProvider.notifier).state = null;
                },
              ),
            ],
            const SizedBox(height: 12),
            _StepBar(
              step: _step,
              onBack: _step > 0 ? _back : null,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              // Steps line up with the step row (the default centres them).
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, if (current != null) current],
              ),
              child: KeyedSubtree(
                key: ValueKey('step$_step${_body?.id}$_goal'),
                child: switch (_step) {
                  0 => _bodyStep(p),
                  1 => _goalStep(p),
                  _ => _setsStep(p),
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── step 1 · body ─────────────────────────────────────────────────────────
  Widget _bodyStep(RefPalette p) {
    final parts = ref.watch(coachBodyPartsProvider);
    final unitName =
        widget.units.where((u) => u.id == _tabUnit).firstOrNull?.name;
    final ask =
        TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        unitName == null
            ? Text('What are we working on?', style: ask)
            : Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'What are we working on for '),
                  TextSpan(
                      text: unitName, style: TextStyle(color: p.copperInk)),
                  const TextSpan(text: '?'),
                ]),
                style: ask,
              ),
        const SizedBox(height: 12),
        parts.when(
          loading: () => _loading(p),
          error: (e, _) => _message(p, 'Couldn’t load body parts.',
              retry: () => ref.invalidate(coachBodyPartsProvider)),
          // The prototype's chips: rounded pills sized to their names. The
          // box has a fixed most-height; the rest
          // scroll inside it.
          data: (list) => list.isEmpty
              ? _message(p, 'No body parts yet.')
              : _BodyChipBox(
                  // phone: about 4½ rows, so the next row peeks and says "scroll"
                  maxHeight: HwTablet.of(context) ? 104 : 225,
                  selectedKey:
                      list.any(_isBodySelected) || _body != null
                          ? _selectedBodyPartKey
                          : null,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      if (_body != null && !list.any(_isBodySelected))
                        _BodyChip(
                          key: _selectedBodyPartKey,
                          label: _body!.name,
                          on: true,
                        ),
                      for (final b in list)
                        _BodyChip(
                          key: _isBodySelected(b) ? _selectedBodyPartKey : null,
                          label: b.name,
                          on: _isBodySelected(b),
                          onTap: () {
                            _clientLoadGeneration++;
                            if (_body?.id != b.id) {
                              setState(() {
                                _body = b;
                                _goal = null;
                                _setIndex = 0;
                                _deviceBySet.clear();
                                _protocolBySet.clear();
                                _gapBySet.clear();
                                _unitHintBySet.clear();
                                _advancedSettingsBySet.clear();
                                _appliedSets.clear();
                                _loadedPlan = null;
                              });
                              ref.read(sessionCoachRunProvider.notifier).state =
                                  null;
                            }
                            setState(() => _step = 1);
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── step 2 · goal ─────────────────────────────────────────────────────────
  SessionCoach? _coachFor(List<SessionCoach> list, [String? goal]) {
    final savedCoachId = _loadedPlan?.run?.sessionCoachId;
    if (savedCoachId != null) {
      for (final coach in list) {
        if (coach.id == savedCoachId &&
            (goal == null || coach.setsFor(goal).isNotEmpty)) {
          return coach;
        }
      }
    }
    for (final c in list) {
      if (goal == null || c.setsFor(goal).isNotEmpty) return c;
    }
    return null;
  }

  Widget _goalStep(RefPalette p) {
    final body = _body!;
    final coaches = ref.watch(sessionCoachesByBodyPartProvider(body.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: body.name, style: TextStyle(color: p.copperInk)),
            const TextSpan(text: ': what should this session support?'),
          ]),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
        ),
        const SizedBox(height: 10),
        coaches.when(
          loading: () => _loading(p),
          error: (e, _) => _message(p, 'Couldn’t load the coach plan.',
              retry: () =>
                  ref.invalidate(sessionCoachesByBodyPartProvider(body.id))),
          data: (list) {
            final act = _coachFor(list, kSupportActivation);
            final rec = _coachFor(list, kSupportRecovery);
            if (act == null && rec == null) {
              return _message(p,
                  'No coach plan for ${body.name} yet. Pick another body part.');
            }
            final cards = [
              _GoalCard(
                sun: true,
                title: 'Support activation',
                note: 'Wake the area up before activity',
                protocol: act?.defaultProtocolFor(kSupportActivation),
                enabled: act != null,
                selected: _goal == kSupportActivation,
                onTap: () {
                  _clientLoadGeneration++;
                  final changed = _goal != kSupportActivation;
                  setState(() {
                    if (changed) {
                      _deviceBySet.clear();
                      _protocolBySet.clear();
                      _gapBySet.clear();
                      _unitHintBySet.clear();
                      _advancedSettingsBySet.clear();
                      _appliedSets.clear();
                      _loadedPlan = null;
                    }
                    _goal = kSupportActivation;
                    _step = 2;
                    _prefillSaved();
                  });
                  if (changed) {
                    ref.read(sessionCoachRunProvider.notifier).state = null;
                  }
                },
              ),
              _GoalCard(
                sun: false,
                title: 'Support recovery',
                note: 'Help it settle after load or activity',
                protocol: rec?.defaultProtocolFor(kSupportRecovery),
                enabled: rec != null,
                selected: _goal == kSupportRecovery,
                onTap: () {
                  _clientLoadGeneration++;
                  final changed = _goal != kSupportRecovery;
                  setState(() {
                    if (changed) {
                      _deviceBySet.clear();
                      _protocolBySet.clear();
                      _gapBySet.clear();
                      _unitHintBySet.clear();
                      _advancedSettingsBySet.clear();
                      _appliedSets.clear();
                      _loadedPlan = null;
                    }
                    _goal = kSupportRecovery;
                    _step = 2;
                    _prefillSaved();
                  });
                  if (changed) {
                    ref.read(sessionCoachRunProvider.notifier).state = null;
                  }
                },
              ),
            ];
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── step 3 · sets ─────────────────────────────────────────────────────────
  Widget _setsStep(RefPalette p) {
    final body = _body!;
    final goal = _goal!;
    final coaches = ref.watch(sessionCoachesByBodyPartProvider(body.id));
    final coach = _coachFor(coaches.valueOrNull ?? const [], goal);
    if (coach == null) return _loading(p);
    _shownCoach = coach;
    final sets = coach.setsFor(goal);
    final idx = _setIndex.clamp(0, sets.length - 1);
    final set = sets[idx];
    final tablet = HwTablet.of(context);

    final viewer = SizedBox(
      height: tablet ? 420 : 300,
      child: Stack(
        children: [
          Positioned.fill(
              child: widget.bodyBuilder?.call(set.markers) ??
                  Container(
                    // `.v6pg-3d`: 18 radius, 1px line border over the stage
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.line),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: CoachBodyView(
                        markers: set.markers,
                        muscleHighlights: set.muscleHighlights,
                        lightStage: true,
                        showViewSwitch: false,
                        onAction: () => CoachBodyFullScreen.open(
                          context,
                          title: '${body.name} · ${_goalShort(goal)}',
                          sets: _fullSets(coach, sets),
                          initialIndex: idx,
                        ),
                      ),
                    ),
                  )),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: IgnorePointer(
              // `.v6pg-3d .cap`
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(26, 26, 26, .74),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Set ${idx + 1} · ${set.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                    if ({...set.sunMuscles, ...set.moonMuscles}.isNotEmpty)
                      Text(
                        {...set.sunMuscles, ...set.moonMuscles}.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final assigned = _deviceBySet.length;
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.v6pg-h`
        Row(
          children: [
            Text('SETS',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: p.ink3)),
            const SizedBox(width: 8),
            // shrinks before Reset delays does, on a narrow phone
            Expanded(
              child: Text(
                '${sets.length} ${sets.length == 1 ? 'SET' : 'SETS'} \u00b7 $assigned ASSIGNED',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                    color: p.copper),
              ),
            ),
            if (_timed) ...[
              const SizedBox(width: 8),
              _ResetDelays(onTap: () {
                for (var j = 1; j < sets.length; j++) {
                  _setGap(j, 0, sets.length);
                }
              }),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // `.v6pg-sets`: the set cards in a row you swipe; the next one peeks.
        LayoutBuilder(builder: (context, c) {
          final w = sets.length == 1
              ? c.maxWidth
              : (c.maxWidth * .86).clamp(0.0, 290.0).toDouble();
          if (_setKeys.length != sets.length) {
            _setKeys = List.generate(sets.length, (_) => GlobalKey());
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // the next card peeks, cut at the panel's edge
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sets.length; i++) ...[
                    // `.v6jt`: the delay before this set, and Swap
                    if (i > 0)
                      _DelayJoint(
                        gap: _gapBySet[i] ?? 0,
                        onLess: () =>
                            _setGap(i, (_gapBySet[i] ?? 0) - 1, sets.length),
                        onMore: () =>
                            _setGap(i, (_gapBySet[i] ?? 0) + 1, sets.length),
                        onSwap: () => _swap(i - 1, i, coach),
                      ),
                    SizedBox(
                      key: _setKeys[i],
                      width: w,
                      child: _setCard(p, coach, sets[i], i, selected: i == idx),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Text('${body.name} \u00b7 ${_goalShort(goal)}',
            style: TextStyle(fontSize: 12.5, color: p.ink3)),
        const SizedBox(height: 10),
        if (_loadedPlan?.bodyPartId == body.id &&
            _loadedPlan?.goal == goal) ...[
          _PrimaryButton(
            label: _applying ? 'Applying\u2026' : 'Repeat last session',
            onTap: _applying ? null : _repeatLoadedPlan,
          ),
          const SizedBox(height: 8),
        ],
        _PrimaryButton(
          label: _applying ? 'Applying\u2026' : 'Use this set',
          onTap: _applying ? null : () => _apply(body, idx, set, coach),
        ),
        const SizedBox(height: 8),
        _OutlineButton(
          label: 'Plan a different body part',
          onTap: _reset,
        ),
      ],
    );

    if (tablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 11, child: viewer),
          const SizedBox(width: 14),
          Expanded(flex: 10, child: panel),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [viewer, const SizedBox(height: 12), panel],
    );
  }

  // ── start delay ───────────────────────────────────────────────────────────
  /// The longest Start Delay a unit takes (the unit card's Delay stepper).
  static const maxStartDelay = 60;

  /// Seconds from Start until set [i] begins.
  int _startOf(int i) {
    var t = 0;
    for (var j = 1; j <= i; j++) {
      t += _gapBySet[j] ?? 0;
    }
    return t;
  }

  bool get _timed => _gapBySet.values.any((g) => g > 0);

  /// Room left for the delay before set [i]: the last set must still start
  /// within [maxStartDelay].
  int _roomFor(int i, int setCount) {
    final room = maxStartDelay - _startOf(setCount - 1) + (_gapBySet[i] ?? 0);
    return room < 0 ? 0 : room;
  }

  /// Sets the delay before set [i] to [gap] — later sets move with it. Units
  /// already given a set get their new start time straight away.
  void _setGap(int i, int gap, int setCount) {
    final current = _gapBySet[i] ?? 0;
    final next = gap.clamp(0, _roomFor(i, setCount));
    if (next == current) return;
    _clientLoadGeneration++;
    setState(() {
      _gapBySet[i] = next;
      _loadedPlan = null;
    });
    final onSetDelay = widget.onSetDelay;
    if (onSetDelay == null) return;
    for (var j = i; j < setCount; j++) {
      final unit = _deviceBySet[j];
      if (unit != null && _appliedSets.contains(j)) {
        onSetDelay(unit, _startOf(j));
      }
    }
    final coach = _shownCoach;
    if (coach != null) _savePlan(coach);
  }

  static String _clock(int sec) =>
      '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  static String _ord(int i) =>
      const ['1st', '2nd', '3rd', '4th', '5th', '6th'].elementAtOrNull(i) ??
      '${i + 1}th';

  /// `.v6jt .sw2`: trade the units of two neighbouring sets. Sets already on
  /// a unit are put on again on their new unit, protocol and start delay.
  Future<void> _swap(int a, int b, SessionCoach coach) async {
    final setCount = coach.setsFor(_goal!).length;
    final ua = _suggestedUnit(a, setCount);
    final ub = _suggestedUnit(b, setCount);
    if (ua == null || ub == null || ua == ub) return;
    _clientLoadGeneration++;
    setState(() {
      _deviceBySet[a] = ub;
      _deviceBySet[b] = ua;
      _unitHintBySet.remove(a);
      _unitHintBySet.remove(b);
      _loadedPlan = null;
    });
    for (final i in [a, b]) {
      if (!_appliedSets.contains(i)) continue;
      final protocolId = _protocolFor(i, coach);
      final unit = _deviceBySet[i]!;
      if (protocolId == null) continue;
      if (await widget.onApply(unit, protocolId)) {
        widget.onSetDelay?.call(unit, _startOf(i));
      }
      if (!mounted) return;
    }
    await _savePlan(coach);
    if (!mounted) return;
  }

  /// The unit each set gets by default: its chosen one, else the unit tab
  /// for the first free set, then the next free units in order.
  String? _suggestedUnit(int idx, int setCount) {
    if (_deviceBySet[idx] != null) return _deviceBySet[idx];
    if (widget.units.isEmpty) return null;
    String? hint(int i) {
      final hintId = _unitHintBySet[i];
      if (hintId == null) return null;
      final unit = widget.units
          .where((u) =>
              u.id == hintId ||
              u.macAddress?.trim().toUpperCase() == hintId.trim().toUpperCase())
          .firstOrNull;
      return unit?.id;
    }

    if (hint(idx) != null) return hint(idx);
    final planned = ref.read(sessionCoachPlannedProvider);
    final order = <String>[
      if (_tabUnit != null) _tabUnit!,
      for (final u in widget.units)
        if (u.id != _tabUnit && !planned.containsKey(u.id)) u.id,
      for (final u in widget.units)
        if (u.id != _tabUnit && planned.containsKey(u.id)) u.id,
    ];
    final used = <String>{
      ..._deviceBySet.values,
      for (var i = 0; i < setCount; i++)
        if (hint(i) != null) hint(i)!,
    };
    for (var i = 0; i < setCount; i++) {
      if (_deviceBySet[i] != null || hint(i) != null) continue;
      final pick = order.firstWhere((id) => !used.contains(id),
          orElse: () => order.first);
      used.add(pick);
      if (i == idx) return pick;
    }
    return order.first;
  }

  /// One set (`.v6sc`): Set pill + name, its pads, Device, Protocol, and a
  /// footer with Locate. The selected set (shown on the body) is copper.
  Widget _setCard(RefPalette p, SessionCoach coach, CoachSet set, int idx,
      {required bool selected}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // `.v6sc select` fill, measured from the prototype
    final card2 = dark ? const Color(0xFF212C33) : const Color(0xFFF7F3F0);
    final protocols = [...coach.protocolsFor(_goal)];
    final setCount = coach.setsFor(_goal!).length;
    final savedSet =
        _loadedPlan?.sets.where((saved) => saved.index == idx).firstOrNull;
    final savedProtocolId = savedSet?.protocolId;
    if (savedProtocolId != null &&
        !protocols.any((protocol) => protocol.id == savedProtocolId)) {
      protocols.add(CoachProtocolRef(
        id: savedProtocolId,
        name: savedSet?.protocolName ?? '',
      ));
    }
    final unitId = _suggestedUnit(idx, setCount);
    final protocolId = _protocolFor(idx, coach);
    final unit = widget.units.where((u) => u.id == unitId).firstOrNull;
    final copperLine = const Color.fromRGBO(198, 158, 131, .75);

    void select() {
      if (_setIndex != idx) {
        _clientLoadGeneration++;
        setState(() => _setIndex = idx);
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: select,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(
                  const Color.fromRGBO(198, 158, 131, .07), p.card)
              : p.card,
          borderRadius: BorderRadius.circular(17),
          border:
              Border.all(width: 1.5, color: selected ? copperLine : p.cardline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .hd
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 28,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: selected ? p.copper : card2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: selected ? Colors.transparent : p.line),
                    ),
                    child: Text('Set ${idx + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .3,
                            color:
                                selected ? const Color(0xFF2B1D12) : p.ink3)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(set.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                color: p.ink)),
                        const SizedBox(height: 2),
                        // `.t small`: 1st · starts 0:00, or together
                        Text(
                          setCount < 2
                              ? 'starts at Start'
                              : _timed
                                  ? '${_ord(idx)} \u00b7 starts ${_clock(_startOf(idx))}'
                                  : 'starts with the others',
                          style: TextStyle(fontSize: 12.5, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // .pads — one pad per line
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final pad in set.padLabels)
                    _PadLine(
                      sun: pad.type == 'sun',
                      text: pad.muscleName,
                      color: coachColorFromHex(pad.color),
                    ),
                  if (set.sunMuscles.isEmpty && set.moonMuscles.isEmpty)
                    Text('No pads placed in this set yet.',
                        style: TextStyle(fontSize: 12.5, color: p.ink3)),
                ],
              ),
            ),
            // .ctl
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Label('DEVICE'),
                  const SizedBox(height: 4),
                  widget.units.isEmpty
                      ? Text('Connect a unit below to assign this set.',
                          style: TextStyle(fontSize: 12.5, color: p.ink3))
                      : _Select<String>(
                          value: unit?.id,
                          hint: 'Choose a device',
                          fill: card2,
                          items: [
                            for (final u in widget.units)
                              (
                                u.id,
                                ref.watch(sessionCoachPlannedProvider)[u.id] ==
                                        null
                                    ? u.name
                                    : '${u.name} \u00b7 planned',
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _clientLoadGeneration++;
                            _deviceBySet[idx] = v;
                            _setIndex = idx;
                            _loadedPlan = null;
                          }),
                        ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Label('PROTOCOL'),
                      const Spacer(),
                      if (protocolId != null)
                        Text(_durationForSet(idx, protocolId),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: p.copper,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                    ],
                  ),
                  const SizedBox(height: 4),
                  protocols.isEmpty
                      ? Text('No protocol set for this coach.',
                          style: TextStyle(fontSize: 12.5, color: p.ink3))
                      : _Select<String>(
                          value: protocolId,
                          hint: 'Choose a protocol',
                          fill: card2,
                          items: [
                            for (final pr in protocols)
                              (pr.id, _protocolLabel(pr)),
                          ],
                          onChanged: (v) => setState(() {
                            if (_protocolBySet[idx] != v) {
                              _clientLoadGeneration++;
                              _advancedSettingsBySet.remove(idx);
                              _loadedPlan = null;
                            }
                            _protocolBySet[idx] = v;
                            _setIndex = idx;
                          }),
                        ),
                ],
              ),
            ),
            // .ft — Locate
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: selected
                          ? const Color.fromRGBO(198, 158, 131, .3)
                          : p.cardline),
                ),
              ),
              child: _LocateButton(
                label: unit == null ? 'Locate' : 'Locate ${unit.name}',
                fill: card2,
                onTap: unit != null && unit.canLocate
                    ? () => widget.onLocate(unit.id)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the full-screen body shows for each set: its pads, and the unit and
  /// protocol it's been given here (or "Off" when not assigned yet).
  List<CoachFullSet> _fullSets(SessionCoach coach, List<CoachSet> sets) {
    final protocols = coach.protocolsFor(_goal);
    return [
      for (var i = 0; i < sets.length; i++)
        () {
          final pid = _protocolFor(i, coach);
          final pr = protocols.where((x) => x.id == pid).firstOrNull;
          final unitId = _deviceBySet[i];
          final unit = unitId == null
              ? null
              : widget.units.where((u) => u.id == unitId).firstOrNull;
          return CoachFullSet(
            name: sets[i].name,
            markers: sets[i].markers,
            sunMuscles: sets[i].sunMuscles,
            moonMuscles: sets[i].moonMuscles,
            padLabels: sets[i].padLabels,
            muscleHighlights: sets[i].muscleHighlights,
            unitName: unit?.name,
            protocolName: pr == null
                ? ''
                : (pr.name.isNotEmpty
                    ? pr.name
                    : (ref
                            .read(protocolDetailProvider(pr.id))
                            .valueOrNull
                            ?.templateName ??
                        '')),
            duration: pid == null ? '' : _durationForSet(i, pid, watch: false),
          );
        }(),
    ];
  }

  String _durationOf(String protocolId, {bool watch = true}) {
    final provider = protocolDetailProvider(protocolId);
    final d = (watch ? ref.watch(provider) : ref.read(provider)).valueOrNull;
    if (d == null) return '';
    final s = d.totalDuration.inSeconds;
    if (s <= 0) return '';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _durationForSet(int index, String protocolId, {bool watch = true}) {
    final savedSet = _loadedPlan?.sets
        .where((set) => set.index == index && set.protocolId == protocolId)
        .firstOrNull;
    final seconds = savedSet?.durationSeconds;
    if (seconds != null && seconds > 0) {
      return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return _durationOf(protocolId, watch: watch);
  }

  String _protocolLabel(CoachProtocolRef pr) {
    final d = ref.watch(protocolDetailProvider(pr.id)).valueOrNull;
    final name = pr.name.isNotEmpty ? pr.name : (d?.templateName ?? 'Protocol');
    final t = _durationOf(pr.id);
    return t.isEmpty ? name : '$name · $t';
  }

  Future<void> _apply(
      CoachBodyPart body, int idx, CoachSet set, SessionCoach coach) async {
    final unitId = _suggestedUnit(idx, coach.setsFor(_goal!).length);
    final protocolId = _protocolFor(idx, coach);
    final messenger = ScaffoldMessenger.of(context);
    if (unitId == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Connect a unit first, then use this set.')));
      return;
    }
    if (protocolId == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('This coach has no protocol yet.')));
      return;
    }
    setState(() => _applying = true);
    final ok = await widget.onApply(unitId, protocolId);
    if (!mounted) return;
    // After the protocol: applying a protocol resets the unit's settings,
    // Start Delay included, so the set's start time goes on last.
    if (ok) {
      final settings = _advancedSettingsBySet[idx];
      if (settings != null) {
        widget.onApplyAdvancedSettings?.call(unitId, settings);
      }
      widget.onSetDelay?.call(unitId, _startOf(idx));
    }
    setState(() {
      _applying = false;
      if (ok) {
        _deviceBySet[idx] = unitId;
        _appliedSets.add(idx);
      }
    });
    if (!ok) return;
    _savePlan(coach);
    ref
        .read(sessionCoachPlannedProvider.notifier)
        .update((m) => {...m, unitId: '${body.name} · Set ${idx + 1}'});
    final unitName =
        widget.units.where((u) => u.id == unitId).firstOrNull?.name ?? 'Unit';
    messenger.showSnackBar(SnackBar(
        content: Text('${set.name} is on $unitName.'),
        duration: const Duration(seconds: 2)));
    // Move on to the next set that still needs a unit.
    final sets = coach.setsFor(_goal!);
    for (var i = 0; i < sets.length; i++) {
      if (!_deviceBySet.containsKey(i)) {
        setState(() => _setIndex = i);
        final key = i < _setKeys.length ? _setKeys[i] : null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = key?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300),
                alignmentPolicy:
                    ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          }
        });
        break;
      }
    }
  }

  Widget _loading(RefPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.copper),
          ),
        ),
      );

  Widget _message(RefPalette p, String text, {VoidCallback? retry}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 13.5, color: p.ink2))),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      );
}

// ── pieces ──────────────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final int step;
  final VoidCallback? onBack;
  const _StepBar({required this.step, this.onBack});

  static const _names = ['BODY', 'GOAL', 'PLACEMENT'];

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    // The bar runs to the card's right edge; the label keeps its natural
    // width and only shortens (…) when a very narrow phone runs out of room.
    return LayoutBuilder(builder: (context, c) {
      return Row(
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: 'Back to the previous step',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.cardline),
                  ),
                  child:
                      Icon(Icons.chevron_left_rounded, size: 18, color: p.ink2),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * .62),
            child: Text('STEP ${step + 1} OF 3 · ${_names[step]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: p.ink3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (step + 1) / 3,
                minHeight: 3,
                color: p.copper,
                backgroundColor: p.tanSoft,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _GoalCard extends ConsumerWidget {
  final bool sun;
  final String title;
  final String note;
  final CoachProtocolRef? protocol;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;
  const _GoalCard({
    required this.sun,
    required this.title,
    required this.note,
    required this.protocol,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    String line = '';
    if (!enabled) {
      line = 'Not in this coach plan';
    } else if (protocol != null) {
      final d = ref.watch(protocolDetailProvider(protocol!.id)).valueOrNull;
      final name =
          protocol!.name.isNotEmpty ? protocol!.name : (d?.templateName ?? '');
      final s = d?.totalDuration.inSeconds ?? 0;
      line = s > 0
          ? '$name · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'
          : name;
    }
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: title,
        selected: selected,
        child: Material(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected
                    ? Color.alphaBlend(
                        const Color.fromRGBO(198, 158, 131, .08), p.card)
                    : null,
                border: Border.all(
                  color: selected ? p.copper : p.cardline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: sun
                            ? const Color(0xFFFDE9E2)
                            : const Color(0xFFE3ECFB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        sun ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                        size: 18,
                        color: sun
                            ? const Color(0xFFE2603F)
                            : const Color(0xFF4A78C8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(title,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: p.ink)),
                    const SizedBox(height: 2),
                    Text(note, style: TextStyle(fontSize: 12.5, color: p.ink3)),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(line,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: enabled ? p.copperInk : p.ink3)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One pad line (`.v6sc .pp`): the rising-sun or crescent glyph in ink,
/// then the muscle names.
class _PadLine extends StatelessWidget {
  final bool sun;
  final String text;
  final Color color;
  const _PadLine({
    required this.sun,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 19,
            height: 17,
            child: CustomPaint(
                painter: sun ? _RisingSun(color) : _Crescent(color)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.ink2)),
          ),
        ],
      ),
    );
  }
}

/// The prototype's `--sun-m` mask: a half sun on a horizon with rays.
class _RisingSun extends CustomPainter {
  final Color color;
  _RisingSun(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox "0 6.2 24 12.4", fitted (contain) into the box
    final k = (size.width / 24).clamp(0.0, size.height / 12.4);
    canvas.translate((size.width - 24 * k) / 2, (size.height - 12.4 * k) / 2);
    canvas.scale(k);
    canvas.translate(0, -6.2);
    final fill = Paint()..color = color;
    canvas.drawArc(Rect.fromCircle(center: const Offset(12, 17), radius: 4.6),
        3.14159, 3.14159, true, fill);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(1.6, 17), const Offset(22.4, 17), line);
    for (final r in const [
      [12.0, 10.4, 12.0, 7.7],
      [14.9, 11.1, 16.1, 8.6],
      [9.1, 11.1, 7.9, 8.6],
      [17.2, 12.9, 19.3, 11.2],
      [6.8, 12.9, 4.7, 11.2],
      [18.5, 15.6, 21.1, 15.0],
      [5.5, 15.6, 2.9, 15.0],
    ]) {
      canvas.drawLine(Offset(r[0], r[1]), Offset(r[2], r[3]), line);
    }
  }

  @override
  bool shouldRepaint(_RisingSun old) => old.color != color;
}

/// The prototype's `--moon-m` mask: a crescent.
class _Crescent extends CustomPainter {
  final Color color;
  _Crescent(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = (size.width / 24).clamp(0.0, size.height / 24);
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    // M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z
    final path = Path()
      ..moveTo(21, 12.79)
      ..arcToPoint(const Offset(11.21, 3),
          radius: const Radius.circular(9), largeArc: true, clockwise: true)
      ..arcToPoint(const Offset(21, 12.79),
          radius: const Radius.circular(7), clockwise: false)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Crescent old) => old.color != color;
}

/// Field label (`.v6sc .ctl label span`), prototype grey #9A918A.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Theme.of(context).brightness == Brightness.dark
              ? RefPalette.of(context).ink3
              : const Color(0xFF9A918A)));
}

/// `.v6sc select`: card2 behind it, a 1.5px cardline border, 13 radius,
/// 44 tall, 14/600 text.
class _Select<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final Color? fill;
  const _Select({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: fill ?? p.card,
        borderRadius: BorderRadius.circular(13),
        // a thin neutral line, as in the prototype (not copper-tinted)
        border: Border.all(color: p.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((i) => i.$1 == value) ? value : null,
          isExpanded: true,
          hint: Text(hint,
              style: TextStyle(
                  color: p.ink3, fontSize: 14, fontWeight: FontWeight.w600)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: Color(0xFF998F86)),
          dropdownColor: p.card,
          borderRadius: BorderRadius.circular(13),
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? p.ink
                  : const Color(0xFF1A1A1A),
              fontSize: 14,
              fontWeight: FontWeight.w600),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Text(i.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// `.v6sc .ft .lc`: Locate, with the copper pin (ring + dot). Faded when the
/// set's unit can't be located.
class _LocateButton extends StatelessWidget {
  final String label;
  final Color fill;
  final VoidCallback? onTap;
  const _LocateButton(
      {required this.label, required this.fill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final pin = onTap == null ? p.ink3 : p.copper;
    return Opacity(
      opacity: onTap == null ? .45 : 1,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 13,
                  height: 13,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: pin, width: 2),
                  ),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: pin),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.ink2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Opacity(
      opacity: onTap == null ? .6 : 1,
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: p.sunGrad),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child: Center(
                child: Text('$label  →',
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A1A12))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.cardline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The closed coach (prototype `.v5c-call`): a copper capsule with the coach
/// face, a status line, "planned / units" and a chevron.
class _ClosedCall extends StatelessWidget {
  final int planned;
  final int units;
  final VoidCallback onTap;
  const _ClosedCall(
      {required this.planned, required this.units, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final allDone = units > 0 && planned >= units;
    final line = units == 0
        ? 'Turn on a unit and I\u2019ll guide the setup'
        : allDone
            ? 'Every unit is planned \u2014 tap to review or change'
            : planned > 0
                ? '$planned of $units planned \u00b7 tap to keep going'
                : 'Body area, protocol and pad placement \u2014 one unit at a time';
    return Semantics(
      button: true,
      label: 'Open session coach. $line',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              width: 1.5,
              color: allDone
                  ? const Color.fromRGBO(63, 142, 110, .45)
                  : Color.fromRGBO(198, 158, 131, dark ? .35 : .55),
            ),
            // The tan tint mixed onto the card colour so it's opaque — the
            // soft shadow below must not show through it.
            gradient: dark
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                          const Color.fromRGBO(201, 167, 136, .16), p.card),
                      Color.alphaBlend(
                          const Color.fromRGBO(169, 130, 95, .06), p.card),
                    ],
                  ),
            color: dark
                ? Color.alphaBlend(
                    const Color.fromRGBO(198, 158, 131, .1), p.card)
                : null,
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(169, 130, 95, .9),
                blurRadius: 18,
                spreadRadius: -12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                const CoachMascot(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session coach',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: p.ink)),
                      const SizedBox(height: 2),
                      Text(line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.ink3)),
                    ],
                  ),
                ),
                if (units > 0) ...[
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '$planned',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFA87B5C))),
                      TextSpan(
                          text: '/$units',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: p.ink3)),
                    ]),
                  ),
                ],
                const SizedBox(width: 12),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dark ? const Color(0xFF15171C) : p.card,
                    border: Border.all(color: p.cardline),
                  ),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: dark
                          ? const Color(0xFFDDCABF)
                          : const Color(0xFF8A5F42)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach's smiling face (prototype `mascotSVG`) with two soft rings
/// drifting out of it (`v5cRing`, 3.4s, the second half a beat behind).
class CoachMascot extends StatefulWidget {
  final double size;
  const CoachMascot({super.key, this.size = 42});

  @override
  State<CoachMascot> createState() => _CoachMascotState();
}

class _CoachMascotState extends State<CoachMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _MascotPainter(t: _c.value, dark: dark),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  final double t;
  final bool dark;
  _MascotPainter({required this.t, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // the two rings
    for (final shift in const [0.0, .5]) {
      final k = (t + shift) % 1;
      final scale = .85 + .75 * k;
      final opacity = .7 * (1 - k);
      if (opacity <= .01) continue;
      canvas.drawCircle(
        c,
        r * scale - .75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.fromRGBO(198, 158, 131, .6 * opacity / .7),
      );
    }
    // the face, drawn in the SVG's 48x48 box
    canvas.save();
    canvas.translate(c.dx - r, c.dy - r);
    canvas.scale(size.shortestSide / 48);
    canvas.drawCircle(
        const Offset(24, 24),
        17,
        Paint()
          ..color = dark ? const Color(0xFFC69E83) : const Color(0xFFB98E71));
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(18.5, 21.5), 2.4, white);
    canvas.drawCircle(const Offset(29.5, 21.5), 2.4, white);
    final smile = Path()
      ..moveTo(17.5, 29.5)
      ..cubicTo(19.5, 31.9, 21.7, 33, 24, 33)
      ..cubicTo(26.3, 33, 28.5, 31.9, 30.5, 29.5);
    canvas.drawPath(
        smile,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
    final spark = Path()
      ..moveTo(36, 10.5)
      ..lineTo(37.1, 13.9)
      ..lineTo(40.5, 15)
      ..lineTo(37.1, 16.1)
      ..lineTo(36, 19.5)
      ..lineTo(34.9, 16.1)
      ..lineTo(31.5, 15)
      ..lineTo(34.9, 13.9)
      ..close();
    canvas.drawPath(spark, Paint()..color = const Color(0xFFE7C9A9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) => old.t != t || old.dark != dark;
}

/// "Unit 1 · Unit 2 · …" (prototype `.v5c-tabs`): which unit is being
/// planned; a planned unit carries a tick.
class _UnitTabs extends StatelessWidget {
  final List<CoachUnit> units;
  final String? selected;
  final Map<String, String> planned;
  final ValueChanged<String> onPick;
  const _UnitTabs({
    required this.units,
    required this.selected,
    required this.planned,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final u in units) ...[
            Semantics(
              button: true,
              selected: u.id == selected,
              child: GestureDetector(
                onTap: () => onPick(u.id),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 96),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: u.id == selected ? p.sunGrad : null,
                    color: u.id == selected ? null : p.tanSoft,
                    border: Border.all(
                        color:
                            u.id == selected ? Colors.transparent : p.cardline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (planned.containsKey(u.id)) ...[
                        Icon(Icons.check_rounded,
                            size: 15,
                            color: u.id == selected
                                ? const Color(0xFF2A1A12)
                                : p.good),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        u.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: u.id == selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: u.id == selected
                              ? const Color(0xFF2A1A12)
                              : p.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// The body-part chips at a fixed most-height, scrolling inside it (with a
/// visible scrollbar) once there are more parts than fit.
class _BodyChipBox extends StatefulWidget {
  final double maxHeight;
  final Widget child;
  final GlobalKey? selectedKey;
  const _BodyChipBox({
    required this.maxHeight,
    required this.child,
    this.selectedKey,
  });

  @override
  State<_BodyChipBox> createState() => _BodyChipBoxState();
}

class _BodyChipBoxState extends State<_BodyChipBox> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(_BodyChipBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedKey != widget.selectedKey) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = widget.selectedKey?.currentContext;
      final selectedRenderObject = selectedContext?.findRenderObject();
      if (!_scroll.hasClients || selectedRenderObject == null) return;
      final viewport = RenderAbstractViewport.maybeOf(selectedRenderObject);
      if (viewport == null) return;
      final targetOffset =
          viewport.getOffsetToReveal(selectedRenderObject, .5).offset;
      final position = _scroll.position;
      final target = targetOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() > 0.5) position.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      // copper thumb on a soft tan track, in the app's palette
      child: RawScrollbar(
        controller: _scroll,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 4,
        radius: const Radius.circular(99),
        trackRadius: const Radius.circular(99),
        thumbColor: p.copper,
        trackColor: p.tanSoft,
        trackBorderColor: Colors.transparent,
        child: SingleChildScrollView(
          controller: _scroll,
          // room for the scrollbar beside the chips
          padding: const EdgeInsets.only(right: 10),
          child: SizedBox(width: double.infinity, child: widget.child),
        ),
      ),
    );
  }
}

/// A body-part chip (prototype `.v5c-chips button`): a white rounded pill
/// sized to its name; copper when picked.
class _BodyChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const _BodyChip({
    super.key,
    required this.label,
    required this.on,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: onTap != null,
      label: label,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: on ? p.sunGrad : null,
            color: on ? null : p.card,
            border: Border.all(
                color: on ? p.copper : p.cardline, width: on ? 2 : 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[
                const Icon(Icons.check_circle_rounded,
                    key: ValueKey('selected-body-part'),
                    size: 17,
                    color: Color(0xFF2A1A12)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? const Color(0xFF2A1A12) : p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.v6jt`: between two set cards — a line, the delay pill (− +8s +), Swap,
/// a line. Dashed and grey at 0; copper once a delay is set. Holding − or +
/// keeps stepping.
class _DelayJoint extends StatelessWidget {
  final int gap;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final VoidCallback onSwap;

  const _DelayJoint({
    required this.gap,
    required this.onLess,
    required this.onMore,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final set = gap > 0;
    final copper = p.copper;
    final tint = set ? copper : p.ink3;
    Widget line() => Container(
          width: 2,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: set ? copper.withValues(alpha: .55) : p.line,
          ),
        );
    // 92 wide as in the prototype, wider only if a long value needs it
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line(),
            const SizedBox(height: 5),
            CustomPaint(
              foregroundPainter:
                  set ? null : _DashedRRect(color: p.line, radius: 12),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: set ? copper.withValues(alpha: .14) : p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: set
                      ? Border.all(color: copper.withValues(alpha: .7))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HoldStep(
                        label: '−',
                        semantics: 'One second less',
                        color: tint,
                        onStep: onLess),
                    Container(
                      constraints: const BoxConstraints(minWidth: 30),
                      alignment: Alignment.center,
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: set ? '+$gap' : '0',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
                          const TextSpan(
                              text: 's',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                        style: TextStyle(color: tint),
                      ),
                    ),
                    _HoldStep(
                        label: '+',
                        semantics: 'One second more',
                        color: tint,
                        onStep: onMore),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            // `.sw2`
            Semantics(
              button: true,
              label: 'Swap the devices on these two sets',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSwap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 14, color: p.ink3),
                      const SizedBox(width: 4),
                      Text('Swap',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: p.ink3)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            line(),
          ],
        ),
      ),
    );
  }
}

/// `.v6jt .pm`: one second per tap; holding it keeps stepping (`v6.hold`).
class _HoldStep extends StatefulWidget {
  final String label;
  final String semantics;
  final Color color;
  final VoidCallback onStep;

  const _HoldStep({
    required this.label,
    required this.semantics,
    required this.color,
    required this.onStep,
  });

  @override
  State<_HoldStep> createState() => _HoldStepState();
}

class _HoldStepState extends State<_HoldStep> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onStep,
        onLongPressStart: (_) {
          widget.onStep();
          _repeat = Timer.periodic(
              const Duration(milliseconds: 120), (_) => widget.onStep());
        },
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: SizedBox(
          width: 26,
          height: 30,
          child: Center(
            child: Text(widget.label,
                style: TextStyle(fontSize: 15, height: 1, color: widget.color)),
          ),
        ),
      ),
    );
  }
}

/// `.v6pg-h .rs`
class _ResetDelays extends StatelessWidget {
  final VoidCallback onTap;
  const _ResetDelays({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.line),
          ),
          child: Text('Reset delays',
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink2)),
        ),
      ),
    );
  }
}

/// A dashed rounded outline (`border:1px dashed`), for a delay of 0.
class _DashedRRect extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRect({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(.5), Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}
