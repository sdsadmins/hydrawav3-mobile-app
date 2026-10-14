import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../data/session_coach_repository.dart';
import '../../domain/session_coach_models.dart';
import 'coach_body_view.dart';

/// A unit on the Session Plan the coach can assign a set to.
class CoachUnit {
  final String id;
  final String name;

  /// BLE-connected: Locate is offered (same rule as the unit card).
  final bool canLocate;

  const CoachUnit({required this.id, required this.name, this.canLocate = false});
}

/// Which units the coach has planned this visit: deviceId → "Knee · Set 1".
final sessionCoachPlannedProvider =
    StateProvider<Map<String, String>>((ref) => const {});

/// The v6 Session Coach (prototype `35-coach` + `B0-coach`) on Session Plan:
///   1 Body  — "What are we working on?" (every body part)
///   2 Goal  — Support activation / Support recovery (what the coach has)
///   3 Sets  — the admin's 3D pads per set, a device and a protocol per set,
///             Locate, and "Use this set".
/// "Use this set" only puts the protocol on the chosen unit, through the
/// screen's own protocol-apply path ([onApply]); nothing else changes.
class SessionCoachCard extends ConsumerStatefulWidget {
  final List<CoachUnit> units;
  final Future<bool> Function(String deviceId, String protocolId) onApply;
  final void Function(String deviceId) onLocate;

  /// Test seam: the 3D body is a WebView, which widget tests can't host.
  final Widget Function(List<Map<String, dynamic>> markers)? bodyBuilder;

  const SessionCoachCard({
    super.key,
    required this.units,
    required this.onApply,
    required this.onLocate,
    this.bodyBuilder,
  });

  @override
  ConsumerState<SessionCoachCard> createState() => _SessionCoachCardState();
}

class _SessionCoachCardState extends ConsumerState<SessionCoachCard> {
  bool _open = false;
  int _step = 0;
  CoachBodyPart? _body;
  String? _goal;
  int _setIndex = 0;
  final Map<int, String> _deviceBySet = {};
  final Map<int, String> _protocolBySet = {};
  bool _applying = false;

  void _reset() {
    setState(() {
      _step = 0;
      _body = null;
      _goal = null;
      _setIndex = 0;
      _deviceBySet.clear();
      _protocolBySet.clear();
    });
  }

  void _back() => setState(() {
        if (_step == 2) {
          _goal = null;
          _setIndex = 0;
          _deviceBySet.clear();
          _protocolBySet.clear();
        } else if (_step == 1) {
          _body = null;
        }
        _step = (_step - 1).clamp(0, 2);
      });

  static String _goalShort(String g) =>
      g == kSupportActivation ? 'Support activation' : 'Support recovery';

  @override
  Widget build(BuildContext context) {
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
          Semantics(
            button: true,
            label: _open ? 'Collapse session coach' : 'Open session coach',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: p.sunGrad,
                    ),
                    child: const Icon(Icons.self_improvement_rounded,
                        color: Colors.white, size: 20),
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
                    child: Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: p.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            _StepBar(
              step: _step,
              onBack: _step > 0 ? _back : null,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What are we working on?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 10),
        parts.when(
          loading: () => _loading(p),
          error: (e, _) => _message(p, 'Couldn’t load body parts.',
              retry: () => ref.invalidate(coachBodyPartsProvider)),
          // An even grid that fills the row (2 across on phone, 3 on wide
          // phones, 4 on tablet) instead of ragged chips.
          data: (list) => list.isEmpty
              ? _message(p, 'No body parts yet.')
              : LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 640
                      ? 4
                      : c.maxWidth >= 400
                          ? 3
                          : 2;
                  const gap = 8.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final b in list)
                        SizedBox(
                          width: w,
                          child: _Chip(
                            label: b.name,
                            on: _body?.id == b.id,
                            fill: true,
                            onTap: () => setState(() {
                              _body = b;
                              _step = 1;
                            }),
                          ),
                        ),
                    ],
                  );
                }),
        ),
      ],
    );
  }

  // ── step 2 · goal ─────────────────────────────────────────────────────────
  SessionCoach? _coachFor(List<SessionCoach> list, [String? goal]) {
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
                protocol: act?.defaultProtocol,
                enabled: act != null,
                onTap: () => setState(() {
                  _goal = kSupportActivation;
                  _step = 2;
                }),
              ),
              _GoalCard(
                sun: false,
                title: 'Support recovery',
                note: 'Help it settle after load or activity',
                protocol: rec?.defaultProtocol,
                enabled: rec != null,
                onTap: () => setState(() {
                  _goal = kSupportRecovery;
                  _step = 2;
                }),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CoachBodyView(
                    markers: set.markers,
                    background: '#F4EEE8',
                    showViewSwitch: false,
                    onAction: () => CoachBodyFullScreen.open(
                      context,
                      title: '${body.name} · ${_goalShort(goal)}',
                      sets: _fullSets(coach, sets),
                      initialIndex: idx,
                    ),
                  ),
                ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xD9504A46),
                  borderRadius: BorderRadius.circular(14),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5),
                    ),
                    if ({...set.sunMuscles, ...set.moonMuscles}.isNotEmpty)
                      Text(
                        {...set.sunMuscles, ...set.moonMuscles}.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFE6DED7), fontSize: 12.5),
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
        Row(
          children: [
            Text('SETS',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: p.ink3)),
            const Spacer(),
            Text(
              '${sets.length} ${sets.length == 1 ? 'SET' : 'SETS'} · $assigned ASSIGNED',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: p.copperInk),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sets.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < sets.length; i++)
                _Chip(
                  label: 'Set ${i + 1} · ${sets[i].name}',
                  on: i == idx,
                  done: _deviceBySet.containsKey(i),
                  onTap: () => setState(() => _setIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _setCard(p, coach, set, idx),
        const SizedBox(height: 8),
        Text('${body.name} · ${_goalShort(goal)}',
            style: TextStyle(fontSize: 12.5, color: p.ink3)),
        const SizedBox(height: 10),
        _PrimaryButton(
          label: _applying ? 'Applying…' : 'Use this set',
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

  Widget _setCard(RefPalette p, SessionCoach coach, CoachSet set, int idx) {
    final protocols = coach.protocols;
    final unitId = _deviceBySet[idx] ??
        _defaultUnit(ref.read(sessionCoachPlannedProvider));
    final protocolId = _protocolBySet[idx] ??
        (protocols.isNotEmpty ? protocols.first.id : null);
    final unit = widget.units.where((u) => u.id == unitId).firstOrNull;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: p.sunGrad,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Set ${idx + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(set.name,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: p.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (set.sunMuscles.isNotEmpty)
            _PadLine(sun: true, text: set.sunMuscles.join(', ')),
          if (set.moonMuscles.isNotEmpty)
            _PadLine(sun: false, text: set.moonMuscles.join(', ')),
          if (set.sunMuscles.isEmpty && set.moonMuscles.isEmpty)
            Text('No pads placed in this set yet.',
                style: TextStyle(fontSize: 13, color: p.ink3)),
          const SizedBox(height: 12),
          _Label('DEVICE'),
          const SizedBox(height: 6),
          widget.units.isEmpty
              ? Text('Connect a unit below to assign this set.',
                  style: TextStyle(fontSize: 13, color: p.ink3))
              : _Select<String>(
                  value: unit?.id,
                  hint: 'Choose a device',
                  items: [
                    for (final u in widget.units)
                      (
                        u.id,
                        ref.watch(sessionCoachPlannedProvider)[u.id] == null
                            ? u.name
                            : '${u.name} · planned',
                      ),
                  ],
                  onChanged: (v) => setState(() => _deviceBySet[idx] = v),
                ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Label('PROTOCOL'),
              const Spacer(),
              if (protocolId != null)
                Text(_durationOf(protocolId),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: p.copperInk)),
            ],
          ),
          const SizedBox(height: 6),
          protocols.isEmpty
              ? Text('No protocol set for this coach.',
                  style: TextStyle(fontSize: 13, color: p.ink3))
              : _Select<String>(
                  value: protocolId,
                  hint: 'Choose a protocol',
                  items: [
                    for (final pr in protocols)
                      (pr.id, _protocolLabel(pr)),
                  ],
                  onChanged: (v) => setState(() => _protocolBySet[idx] = v),
                ),
          if (unit != null && unit.canLocate) ...[
            const SizedBox(height: 10),
            _OutlineButton(
              label: 'Locate ${unit.name}',
              icon: Icons.my_location_rounded,
              onTap: () => widget.onLocate(unit.id),
            ),
          ],
        ],
      ),
    );
  }

  /// What the full-screen body shows for each set: its pads, and the unit and
  /// protocol it's been given here (or "Off" when not assigned yet).
  List<CoachFullSet> _fullSets(SessionCoach coach, List<CoachSet> sets) {
    final protocols = coach.protocols;
    return [
      for (var i = 0; i < sets.length; i++)
        () {
          final pid = _protocolBySet[i] ??
              (protocols.isNotEmpty ? protocols.first.id : null);
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
            unitName: unit?.name,
            protocolName: pr == null
                ? ''
                : (pr.name.isNotEmpty
                    ? pr.name
                    : (ref.read(protocolDetailProvider(pr.id)).valueOrNull
                            ?.templateName ??
                        '')),
            duration: pid == null ? '' : _durationOf(pid, watch: false),
          );
        }(),
    ];
  }

  String? _defaultUnit(Map<String, String> planned) {
    if (widget.units.isEmpty) return null;
    final taken = _deviceBySet.values.toSet();
    for (final u in widget.units) {
      if (!planned.containsKey(u.id) && !taken.contains(u.id)) return u.id;
    }
    return widget.units.first.id;
  }

  String _durationOf(String protocolId, {bool watch = true}) {
    final provider = protocolDetailProvider(protocolId);
    final d = (watch ? ref.watch(provider) : ref.read(provider)).valueOrNull;
    if (d == null) return '';
    final s = d.totalDuration.inSeconds;
    if (s <= 0) return '';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _protocolLabel(CoachProtocolRef pr) {
    final d = ref.watch(protocolDetailProvider(pr.id)).valueOrNull;
    final name = pr.name.isNotEmpty ? pr.name : (d?.templateName ?? 'Protocol');
    final t = _durationOf(pr.id);
    return t.isEmpty ? name : '$name · $t';
  }

  Future<void> _apply(
      CoachBodyPart body, int idx, CoachSet set, SessionCoach coach) async {
    final planned = ref.read(sessionCoachPlannedProvider);
    final unitId = _deviceBySet[idx] ?? _defaultUnit(planned);
    final protocolId = _protocolBySet[idx] ??
        (coach.protocols.isNotEmpty ? coach.protocols.first.id : null);
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
    setState(() {
      _applying = false;
      if (ok) _deviceBySet[idx] = unitId;
    });
    if (!ok) return;
    ref.read(sessionCoachPlannedProvider.notifier).update(
        (m) => {...m, unitId: '${body.name} · Set ${idx + 1}'});
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
                  child: Icon(Icons.chevron_left_rounded,
                      size: 18, color: p.ink2),
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

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final bool done;

  /// Stretch to the given width with the label centred (step 1 grid).
  final bool fill;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.on,
      required this.onTap,
      this.done = false,
      this.fill = false});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? p.copper : p.card,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: fill ? 54 : null,
            padding: EdgeInsets.symmetric(
                horizontal: fill ? 10 : 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(fill ? 16 : 999),
              border: Border.all(color: on ? p.copper : p.cardline),
            ),
            child: Row(
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (done) ...[
                  Icon(Icons.check_rounded,
                      size: 15, color: on ? Colors.white : p.good),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      maxLines: fill ? 2 : null,
                      overflow: fill ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : p.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  final bool sun;
  final String title;
  final String note;
  final CoachProtocolRef? protocol;
  final bool enabled;
  final VoidCallback onTap;
  const _GoalCard({
    required this.sun,
    required this.title,
    required this.note,
    required this.protocol,
    required this.enabled,
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
                border: Border.all(color: p.cardline),
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
                    Text(note,
                        style: TextStyle(fontSize: 12.5, color: p.ink3)),
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

class _PadLine extends StatelessWidget {
  final bool sun;
  final String text;
  const _PadLine({required this.sun, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(sun ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
              size: 16, color: p.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${sun ? 'Sun' : 'Moon'}: $text',
              style: TextStyle(fontSize: 13.5, color: p.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: RefPalette.of(context).ink3));
}

class _Select<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  const _Select({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.cardline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((i) => i.$1 == value) ? value : null,
          isExpanded: true,
          hint: Text(hint, style: TextStyle(color: p.ink3, fontSize: 14)),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.ink2),
          dropdownColor: p.card,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(color: p.ink, fontSize: 14),
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
  final IconData? icon;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap, this.icon});

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
              if (icon != null) ...[
                Icon(icon, size: 16, color: p.ink2),
                const SizedBox(width: 6),
              ],
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
