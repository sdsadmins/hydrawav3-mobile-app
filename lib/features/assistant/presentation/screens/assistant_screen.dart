import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../clients/presentation/widgets/new_client_sheet.dart';
import '../../../devices/presentation/widgets/players_section.dart';
import '../../../devices/presentation/widgets/ref_palette.dart';
import '../../../intake/domain/intake_enums.dart';
import '../../../intake/domain/intake_models.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../../intake/presentation/widgets/body_map.dart';
import '../../../pad_placement/data/pad_placement_remote_source.dart';
import '../../../pad_placement/presentation/screens/pad_placement_3d_screen.dart';

/// The "Assistant" page — a port of the cowork-os handoff `scr-chat` chat.
/// Suggestion-led: AI / user bubbles + tappable chips. `intent == "pads"` (from
/// Find Pad Placements) opens the pad-placement flow → Performance (pick a user)
/// / Recovery (pick a discomfort area from the org's body-part list).
class AssistantScreen extends ConsumerStatefulWidget {
  final String? intent;
  const AssistantScreen({super.key, this.intent});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _Msg {
  final bool isMe;
  final String text;
  final List<InlineSpan>? rich;
  const _Msg(this.isMe, this.text, {this.rich});
}

/// A range-of-motion movement test (parity with the guided-assessment
/// `_romTests`): a test name + the body region it targets.
class _RomTest {
  final String name;
  final String target;
  const _RomTest(this.name, this.target);
}

const _kRomTests = <_RomTest>[
  _RomTest('Forward Bend', 'Lower back / Pelvis'),
  _RomTest('Squat', 'Knees'),
  _RomTest('Trunk Rotation', 'Mid-back / Thoracic Spine'),
  _RomTest('Ankle Dorsiflexion', 'Ankles / lower leg'),
  _RomTest('Shoulder Flexion', 'Shoulders'),
  _RomTest('Neck Flexion', 'Neck / Cervical Spine'),
  _RomTest('Neck Rotation', 'Neck / Cervical Spine'),
];

/// One guided-assessment question rendered as a chat step (single-select).
class _Step {
  final String key;
  final String prompt;
  final List<String> options;
  final IconData icon;
  const _Step(this.key, this.prompt, this.options, this.icon);
}

// Option lists copied from the guided-assessment panel (intake) so the chat
// mirrors that flow. Kept local to the assistant.
const _kSensations = <String>[
  'Tight', 'Stiff', 'Achy', 'Heavy or fatigued', 'Sharp', 'Burning',
  'Tingling', 'Numb',
];
const _kDurations = <String>[
  'Less than 6 weeks', '6 weeks to 3 months', '3 to 6 months',
  '6 months to 1 year', 'More than 1 year',
];
const _kBehaviors = <String>[
  'Always Present', 'Comes and Goes', 'Only with certain Activities',
  'Varies day to day',
];
const _kLevels = <String>['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'];
const _kActivities = <String>[
  'Office / desk work', 'Standing work', 'Manual work', 'Sports / training',
  'Yoga / mobility', 'Running / cycling', 'Prolonged driving',
];
const _kWorse = <String>[
  'Sitting >30 min', 'Standing >30 min', 'Getting up from sitting', 'Walking',
  'Stairs', 'Bending backward', 'Twisting', 'Reaching', 'Morning',
  'End of day', 'During exercise', 'After exercise', 'None', 'Not sure',
];
const _kBetter = <String>[
  'Sitting', 'Standing and moving', 'Walking', 'Stretching', 'Knees-to-chest',
  'Heat', 'Cold', 'Gentle movement', 'Massage', 'Changing positions', 'Rest',
  'Exercise', 'Nothing yet',
];

/// A tappable suggestion chip.
class _ChipAction {
  final IconData icon;
  final String label;
  final bool hot;
  final VoidCallback onTap;
  const _ChipAction(this.icon, this.label, this.onTap, {this.hot = false});
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_Msg> _messages = [];
  List<_ChipAction> _chips = const [];
  bool _chipsVisible = true;
  bool _typing = false;
  // True while in the Recovery flow — after an area is picked it goes to the
  // Range-of-Motion step, then the guided-assessment questions. Performance is
  // untouched.
  bool _recovery = false;

  // Guided-assessment chat state (recovery only).
  /// Raw `placement-session` response for the last generated placement — kept so
  /// the "3D pad placement" chip can hand its `markers` to the 3D viewer.
  Map<String, dynamic>? _lastPlacement;
  String? _assessmentArea;
  int _stepIndex = 0;
  final Map<String, String> _answers = {};

  // Manual-entry ROM: the next typed input becomes the movement test name.
  bool _awaitingManualRom = false;
  String? _manualRomArea;

  // The guided-assessment questions, as chat steps (parity with the intake
  // panel's Area of Focus → Daily Activities steps).
  static const _steps = <_Step>[
    _Step('sensation', 'How does it feel?', _kSensations,
        Icons.spa_outlined),
    _Step('duration', 'How long has this been going on?', _kDurations,
        Icons.schedule_rounded),
    _Step('behavior', 'Is it constant, or does it come and go?', _kBehaviors,
        Icons.sync_rounded),
    _Step('level', 'On a 0–10 scale, how much discomfort right now?', _kLevels,
        Icons.speed_rounded),
    _Step('activity', 'What does a typical day look like?', _kActivities,
        Icons.work_outline_rounded),
    _Step('worse', 'What tends to make it worse?', _kWorse,
        Icons.trending_down_rounded),
    _Step('better', 'What helps it feel better?', _kBetter,
        Icons.trending_up_rounded),
  ];

  static const _greeting = 'Hey — what are we working on today?';

  bool get _isUniversity =>
      (ref.read(authStateProvider).user?.organizationType ?? '')
          .toUpperCase() ==
      'UNIVERSITY';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── conversation state helpers ─────────────────────────────────────────────

  void _initialize() {
    _messages.clear();
    _typing = false;
    _chipsVisible = true;
    if (widget.intent == 'pads') {
      _messages.add(const _Msg(
        false,
        'Let’s find the right pad placement. Are we prepping for performance, '
        'or working on recovery?',
        rich: [
          TextSpan(
              text:
                  'Let’s find the right pad placement. Are we prepping for '),
          TextSpan(
              text: 'performance',
              style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ', or working on '),
          TextSpan(
              text: 'recovery',
              style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '?'),
        ],
      ));
      _chips = _padChips;
    } else {
      _messages.add(const _Msg(false, _greeting));
      _chips = _homeChips;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 160,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _me(String text) {
    setState(() {
      _chipsVisible = false;
      _messages.add(_Msg(true, text));
    });
    _scrollToEnd();
  }

  /// Adds an AI bubble (after a short typing beat). When [then] is provided, it
  /// becomes the visible chip row.
  Future<void> _ai(String text,
      {List<InlineSpan>? rich, List<_ChipAction>? then}) async {
    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_Msg(false, text, rich: rich));
      if (then != null) {
        _chips = then;
        _chipsVisible = true;
      }
    });
    _scrollToEnd();
  }

  void _showChips(List<_ChipAction> chips) {
    if (!mounted) return;
    setState(() {
      _chips = chips;
      _chipsVisible = true;
    });
    _scrollToEnd();
  }

  // ── chip sets ──────────────────────────────────────────────────────────────

  List<_ChipAction> get _homeChips => [
        _ChipAction(Icons.play_arrow_rounded, 'Start a session', () {
          _me('Start a session');
          _ai('Open the Devices tab, pick your units and a protocol, then hit '
              'Start Session.');
        }, hot: true),
        _ChipAction(Icons.bolt_rounded, 'Prep a user', _onPerformance),
        _ChipAction(Icons.waves_rounded, 'Recovery', _onRecovery),
        _ChipAction(Icons.grid_view_rounded, 'Find pad placements', () {
          _me('Find pad placements');
          _ai(
            'Let’s find the right pad placement. Are we prepping for '
            'performance, or working on recovery?',
            rich: const [
              TextSpan(
                  text:
                      'Let’s find the right pad placement. Are we prepping for '),
              TextSpan(
                  text: 'performance',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ', or working on '),
              TextSpan(
                  text: 'recovery',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '?'),
            ],
            then: _padChips,
          );
        }),
      ];

  List<_ChipAction> get _padChips => [
        _ChipAction(Icons.bolt_rounded, 'Performance', _onPerformance,
            hot: true),
        _ChipAction(Icons.waves_rounded, 'Recovery', _onRecovery),
      ];

  // ── flows ───────────────────────────────────────────────────────────────────

  // Performance → pick a user, then the focus area. (Unchanged — no ROM step.)
  Future<void> _onPerformance() async {
    _recovery = false;
    _me('Performance');
    await _ai('Who are we prepping? Guest works too — no name needed.');
    final members = await _loadMembers();
    final uni = _isUniversity;
    _showChips([
      _ChipAction(Icons.person_outline_rounded, 'Guest — no name',
          () => _pickUser('Guest'),
          hot: true),
      for (final m in members)
        _ChipAction(Icons.person_outline_rounded, m.clientName,
            () => _pickUser(m.clientName)),
      _ChipAction(
        uni ? Icons.person_add_alt_1_rounded : Icons.person_add_alt_1_rounded,
        uni ? 'Add player' : 'Add client',
        () => uni
            ? showAddPlayerSheet(context, ref)
            : showNewClientSheet(context, ref),
      ),
    ]);
  }

  void _pickUser(String name) {
    _me(name);
    _ai('Great — $name. Where’s the focus area?').then((_) => _showAreas());
  }

  // Recovery → pick a discomfort area, then a range-of-motion check.
  Future<void> _onRecovery() async {
    _recovery = true;
    _me('Recovery');
    await _ai('Recovery — let’s find where you need it. Where’s the discomfort?');
    _showAreas();
  }

  void _showAreas() {
    // The full body-map region list (front + back, de-duped) — the same areas
    // the intake body map uses.
    _showChips([
      for (final a in kBodyMapAreas)
        _ChipAction(_areaIcon(a), a, () => _pickArea(a)),
    ]);
  }

  Future<void> _pickArea(String name) async {
    _me(name);
    if (_recovery) {
      await _showRoms(name);
    } else {
      // Performance path — left as-is (no ROM step, no API).
      await _ai('Here’s a Sun & Moon pad placement for $name. Open the Devices '
          'tab to load it and start the session.');
    }
  }

  // ── Recovery: range-of-motion step (guided-assessment tests) ────────────────

  Future<void> _showRoms(String area) async {
    await _ai(
      'For the ${area.toLowerCase()}, pick a range-of-motion check — or add '
      'your own.',
      rich: [
        const TextSpan(text: 'For the '),
        TextSpan(
            text: area.toLowerCase(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(
            text: ', pick a range-of-motion check — or add your own.'),
      ],
    );
    _showChips([
      for (var i = 0; i < _kRomTests.length; i++)
        _ChipAction(_romIcon(_kRomTests[i].name), _kRomTests[i].name,
            () => _pickRom(area, _kRomTests[i].name),
            hot: i == 0),
      _ChipAction(Icons.edit_outlined, 'Manual Entry',
          () => _startManualRom(area)),
    ]);
  }

  void _startManualRom(String area) {
    _me('Manual Entry');
    _manualRomArea = area;
    _awaitingManualRom = true;
    _ai('Sure — type the movement you’d like to check in the box below and '
        'send.');
  }

  Future<void> _pickRom(String area, String testName) async {
    _me(testName);
    // Continue into the guided-assessment questions (chat). The ROM test +
    // answers are collected in _answers for the (later) report call.
    _assessmentArea = area;
    _stepIndex = 0;
    _answers
      ..clear()
      ..['romTest'] = testName
      ..['area'] = area;
    await _ai('Got it — $testName. A few quick questions and I’ll have what I '
        'need for the recovery plan.');
    _askStep();
  }

  // ── Recovery: guided-assessment questions (chat) ────────────────────────────

  Future<void> _askStep() async {
    if (_stepIndex >= _steps.length) {
      await _finishAssessment();
      return;
    }
    final s = _steps[_stepIndex];
    await _ai(s.prompt);
    _showChips([
      for (final o in s.options)
        _ChipAction(s.icon, o, () => _answerStep(o)),
    ]);
  }

  void _answerStep(String value) {
    if (_stepIndex >= _steps.length) return;
    _answers[_steps[_stepIndex].key] = value;
    _me(value);
    _stepIndex++;
    _askStep();
  }

  Future<void> _finishAssessment() async {
    // Record the picked area as the session's area of focus. In CLIENT mode the
    // Devices tab gates "Start Session" on a non-empty guided-assessment
    // discomfort area, and this recovery flow lives outside that wizard — so
    // without this, Start stays disabled even after a placement is generated.
    _recordAreaOfFocus();

    // Build the AssessmentPayload and call the RAG pad-placement endpoint.
    final payload = _buildAssessmentPayload();
    setState(() {
      _chipsVisible = false;
      _typing = true;
    });
    _scrollToEnd();
    try {
      final result = await ref
          .read(padPlacementRemoteSourceProvider)
          .placementSession(payload);
      if (!mounted) return;
      setState(() {
        _typing = false;
        _lastPlacement = result;
        _messages.add(_Msg(false, _placementSummary(result)));
      });
      _scrollToEnd();
      // Offer to start the session (protocol is picked on the Devices tab), and
      // to view the Sun/Moon pads on the 3D anatomy model.
      final hasMarkers = (result['markers'] as List?)?.isNotEmpty ?? false;
      _showChips([
        _ChipAction(Icons.play_arrow_rounded, 'Start session',
            () => context.go(RoutePaths.devices),
            hot: true),
        if (hasMarkers)
          _ChipAction(
              Icons.view_in_ar_rounded, '3D pad placement', _open3DPlacement),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_Msg(false, 'Couldn’t generate the pad placement: $e'));
      });
      _scrollToEnd();
    }
  }

  /// Opens the 3D Sun/Moon pad-placement viewer for the last generated
  /// placement (port of the web `AnatomyScene`).
  void _open3DPlacement() {
    final placement = _lastPlacement;
    if (placement == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PadPlacement3DScreen(
          placement: placement,
          title: _assessmentArea == null
              ? '3D Pad Placement'
              : '3D Pad Placement — $_assessmentArea',
        ),
      ),
    );
  }

  /// Registers the picked recovery area into the shared guided-assessment state
  /// so the Devices tab's client-mode "Start Session" gate is satisfied. Skips
  /// duplicates so re-running the flow for the same area doesn't pile up.
  void _recordAreaOfFocus() {
    final area = _assessmentArea;
    if (area == null || area.trim().isEmpty) return;

    final existing = ref.read(guidedAssessmentProvider).discomfortAreas;
    if (existing
        .any((a) => a.bodyPart.toLowerCase() == area.toLowerCase())) {
      return;
    }

    final notes = [
      if ((_answers['romTest'] ?? '').isNotEmpty) 'ROM: ${_answers['romTest']}',
      if ((_answers['sensation'] ?? '').isNotEmpty)
        'Feels: ${_answers['sensation']}',
    ].join(' · ');

    ref.read(guidedAssessmentProvider.notifier).addArea(
          DiscomfortAreaInput(
            bodyPart: area,
            side: _sideEnum(area),
            discomfortBefore: int.tryParse(_answers['level'] ?? '') ?? 0,
            behavior: enumFromValue(DiscomfortBehavior.values,
                    _answers['behavior'], (e) => e.value) ??
                DiscomfortBehavior.comesAndGoes,
            temporalDuration: enumFromValue(TemporalDuration.values,
                    _answers['duration'], (e) => e.value) ??
                TemporalDuration.lessThan6Weeks,
            notes: notes.isEmpty ? null : notes,
          ),
        );
  }

  static DiscomfortSide _sideEnum(String area) {
    final n = area.toLowerCase();
    if (n.contains('left')) return DiscomfortSide.left;
    if (n.contains('right')) return DiscomfortSide.right;
    return DiscomfortSide.both;
  }

  /// Maps the recovery chat answers to the `AssessmentPayload` (`{ state,
  /// learningCases, persist }`) the endpoint expects.
  ///
  /// The Node rules engine (`@hydrawav3/placement-core`) only returns a
  /// recommendation once `getNextQuestion(state)` is satisfied, and it matches
  /// on **canonical IDs** — a body-map label like "Lower Back" or a goal of
  /// "recovery" is not recognized and yields `recommendation: null`. So we map
  /// the picked area → engine `region` id + `side` id and use `goal:
  /// 'performance'`, which the engine infers as `sessionIntent: 'recovery'` and
  /// routes through the direct ROM/recovery handler (covers every region).
  Map<String, dynamic> _buildAssessmentPayload() {
    final area = _assessmentArea ?? '';
    final client = ref.read(selectedClientProvider);
    final isGuest =
        ref.read(sessionClientModeProvider) == ClientMode.guest ||
            client == null;
    final rom = _answers['romTest'] ?? '';
    final sensation = _answers['sensation'] ?? '';

    final regionId = _regionId(area);
    final sideId = _sideId(area);

    final state = <String, dynamic>{
      'subscriptionTier': '',
      'clientMode': isGuest ? 'guest' : 'client',
      'clientName': isGuest ? 'Guest' : client.clientName,
      'clientNotes': '',
      // Recovery flow → 'performance' goal + 'recovery' session intent, which
      // routes through the engine's direct ROM/recovery placement handler.
      // Sending sessionIntent explicitly leaves getNextQuestion with nothing
      // outstanding (the engine would otherwise only infer it internally).
      'goal': 'performance',
      'sessionIntent': 'recovery',
      // Canonical engine region id (falls back to the raw label so an
      // unmapped area still round-trips as an "unsupported" recommendation).
      'region': regionId.isNotEmpty ? regionId : area,
      'side': sideId,
      // Engine only needs this truthy to mark the movement screen complete.
      'movementInstructionDone': rom.isNotEmpty ? rom : 'done',
      'movementResponse': _movementResponseId(sensation),
      // Region-specific fields the engine requires to resolve these areas.
      if (regionId == 'knee') 'kneeLocation': 'anterior',
      if (regionId == 'ankle_foot')
        'ankleFootZone': area.toLowerCase().contains('foot') ? 'foot' : 'ankle',
      'dailyActivities': [
        if ((_answers['activity'] ?? '').isNotEmpty) _answers['activity'],
      ],
      'sleepPosture': '',
      'worseFactors': [
        if ((_answers['worse'] ?? '').isNotEmpty) _answers['worse'],
      ],
      'betterFactors': [
        if ((_answers['better'] ?? '').isNotEmpty) _answers['better'],
      ],
      'positionTolerance': '',
      'hipTightness': '',
      'missingRemark': '',
      'assessmentAreaDetails': {
        area: {
          'level': int.tryParse(_answers['level'] ?? '') ?? 0,
          'behavior': _answers['behavior'] ?? '',
          'duration': _answers['duration'] ?? '',
          'notes': '',
        },
      },
      'assessmentFindings': [
        {
          'id': 'finding-1',
          'motionId': '',
          'motionTitle': rom,
          'affectedPart': area,
          'sensations': [if (sensation.isNotEmpty) sensation],
        },
      ],
    };

    return {'state': state, 'learningCases': const [], 'persist': false};
  }

  /// Maps a body-map area label to the engine's canonical `region` id. Returns
  /// '' for areas the engine has no placement rules for (head/chest/abdomen).
  static String _regionId(String area) {
    final n = area.toLowerCase();
    if (n.contains('neck')) return 'neck';
    if (n.contains('shoulder')) return 'shoulder';
    if (n.contains('upper back') || n.contains('mid back')) return 'upper_back';
    if (n.contains('lower back') || n.contains('low back')) return 'low_back';
    if (n.contains('hip')) return 'hip';
    if (n.contains('knee')) return 'knee';
    if (n.contains('elbow')) return 'elbow';
    // Check the specific arm segments before the generic "arm" fallback.
    if (n.contains('wrist') ||
        n.contains('forearm') ||
        n.contains('lower arm') ||
        n.contains('hand')) {
      return 'forearm_wrist';
    }
    if (n.contains('ankle') || n.contains('foot')) return 'ankle_foot';
    if (n.contains('arm')) return 'shoulder'; // upper arm → shoulder/arm region
    return '';
  }

  /// Engine `side` id. Bilateral regions (e.g. neck) still require a valid side,
  /// so midline/unknown areas default to 'right'.
  static String _sideId(String area) {
    final n = area.toLowerCase();
    if (n.contains('left')) return 'left';
    return 'right';
  }

  /// Maps a felt-sensation label to the engine's `movementResponse` id (used for
  /// caution text). Optional for the recovery path, but keeps parity.
  static String _movementResponseId(String sensation) {
    final s = sensation.toLowerCase();
    if (s.contains('tight') || s.contains('stiff')) return 'stretch_tight';
    if (s.contains('achy') || s.contains('heavy') || s.contains('fatigued')) {
      return 'contract_guard';
    }
    if (s.contains('sharp') || s.contains('burning')) return 'pinch_catch';
    if (s.contains('tingling') || s.contains('numb')) return 'weak_unstable';
    return 'stretch_tight';
  }

  /// A readable summary of the pad-placement response. The Node engine returns
  /// `{ engine, nextQuestion, recommendation: { title, summary, sets: [{ sun,
  /// moon }], caution, nextStep }, markers }`.
  String _placementSummary(Map<String, dynamic> r) {
    final rec = r['recommendation'];
    if (rec is! Map) {
      // No rules for this area (or state still incomplete) — engine returned null.
      return 'I couldn’t generate a pad placement for this area yet. Try a '
          'different area, or set it up manually on the Devices tab.';
    }

    final title = rec['title']?.toString() ?? '';
    final summary = rec['summary']?.toString() ?? '';
    final sets = rec['sets'] is List ? rec['sets'] as List : const [];
    final caution = rec['caution']?.toString() ?? '';
    final nextStep = rec['nextStep']?.toString() ?? '';

    final b = StringBuffer('Here’s the Sun & Moon pad placement.\n');
    if (title.isNotEmpty) b.writeln('\n$title');
    if (summary.isNotEmpty) b.writeln(summary);

    if (sets.isNotEmpty) {
      b.writeln('\nPlacements:');
      for (final s in sets) {
        if (s is! Map) continue;
        final st = s['title']?.toString() ?? 'Set';
        final sun = s['sun'] is Map ? (s['sun']['label']?.toString() ?? '') : '';
        final moon =
            s['moon'] is Map ? (s['moon']['label']?.toString() ?? '') : '';
        b.writeln('• $st');
        if (sun.isNotEmpty) b.writeln('   ☀ Sun — $sun');
        if (moon.isNotEmpty) b.writeln('   ☾ Moon — $moon');
        final setting = s['setting']?.toString() ?? '';
        if (setting.isNotEmpty && setting != 'Normal') {
          b.writeln('   Setting: $setting');
        }
      }
    }

    if (caution.trim().isNotEmpty) b.writeln('\n⚠ ${caution.trim()}');
    if (nextStep.isNotEmpty) b.writeln('\n$nextStep');

    final out = b.toString().trim();
    return out.isEmpty
        ? 'Pad placement is ready. Tap Start session to continue.'
        : out;
  }


  /// An icon for a ROM movement test.
  static IconData _romIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('squat')) return Icons.fitness_center_rounded;
    if (n.contains('bend')) return Icons.self_improvement_rounded;
    if (n.contains('rotation') || n.contains('trunk')) {
      return Icons.threesixty_rounded;
    }
    if (n.contains('ankle')) return Icons.directions_walk_rounded;
    if (n.contains('shoulder')) return Icons.sports_gymnastics_rounded;
    if (n.contains('neck')) return Icons.accessibility_new_rounded;
    return Icons.straighten_rounded;
  }

  Future<List<Client>> _loadMembers() async {
    try {
      final list = await ref.read(clientListProvider.future);
      return _isUniversity ? list.where((c) => c.isPlayer).toList() : list;
    } catch (_) {
      return const [];
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    // If we're waiting on a manual ROM entry, this becomes the movement test.
    if (_awaitingManualRom) {
      _awaitingManualRom = false;
      _pickRom(_manualRomArea ?? _assessmentArea ?? 'the area', text);
      return;
    }
    _me(text);
    _ai('Got it. I’m a demo assistant for now — tap a suggestion above, or head '
        'to the Devices tab to start a session.');
  }

  /// An icon for a body area (keyword-mapped; falls back to a body figure).
  static IconData _areaIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('head')) return Icons.face_outlined;
    if (n.contains('neck')) return Icons.accessibility_new_rounded;
    if (n.contains('shoulder')) return Icons.sports_gymnastics_rounded;
    if (n.contains('back')) return Icons.airline_seat_recline_normal_rounded;
    if (n.contains('chest') || n.contains('abdomen')) {
      return Icons.self_improvement_rounded;
    }
    if (n.contains('hip')) return Icons.accessibility_new_rounded;
    if (n.contains('arm') ||
        n.contains('elbow') ||
        n.contains('wrist') ||
        n.contains('hand')) {
      return Icons.back_hand_outlined;
    }
    if (n.contains('leg') ||
        n.contains('knee') ||
        n.contains('ankle') ||
        n.contains('foot')) {
      return Icons.directions_walk_rounded;
    }
    return Icons.accessibility_new_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 20, color: p.copperInk),
                            const SizedBox(width: 8),
                            Text(
                              'Assistant',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ask, tap a suggestion, or speak anytime',
                          style: TextStyle(fontSize: 12, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  _IconBtn(
                    palette: p,
                    icon: Icons.refresh_rounded,
                    onTap: () => setState(_initialize),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  for (final m in _messages) _Bubble(palette: p, msg: m),
                  if (_typing) _TypingBubble(palette: p),
                  if (_chipsVisible && _chips.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: [
                          for (final c in _chips) _Chip(palette: p, action: c),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(color: p.ink, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask or say what you need…',
                        hintStyle: TextStyle(color: p.ink3),
                        filled: true,
                        fillColor: p.card,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 13),
                        border: _barBorder(p.line),
                        enabledBorder: _barBorder(p.line),
                        focusedBorder: _barBorder(p.copper),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  _MicSendButton(palette: p, onTap: _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _barBorder(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: c, width: 1.5),
      );
}

/// `.msg.ai` / `.msg.me` — chat bubble.
class _Bubble extends StatelessWidget {
  final RefPalette palette;
  final _Msg msg;
  const _Bubble({required this.palette, required this.msg});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final me = msg.isMe;
    final base = TextStyle(
      fontSize: 14,
      height: 1.5,
      color: me ? const Color(0xFFF2E9E2) : p.ink,
    );
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            gradient: me ? p.heroGrad : null,
            color: me ? null : p.card,
            border: me ? null : Border.all(color: p.line),
            boxShadow: me ? null : p.shadow,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(19),
              topRight: const Radius.circular(19),
              bottomLeft: Radius.circular(me ? 19 : 7),
              bottomRight: Radius.circular(me ? 7 : 19),
            ),
          ),
          child: msg.rich != null
              ? Text.rich(TextSpan(style: base, children: msg.rich))
              : Text(msg.text, style: base),
        ),
      ),
    );
  }
}

/// `.typing` — three-dot indicator in an AI bubble.
class _TypingBubble extends StatefulWidget {
  final RefPalette palette;
  const _TypingBubble({required this.palette});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.card,
          border: Border.all(color: p.line),
          boxShadow: p.shadow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(19),
            topRight: Radius.circular(19),
            bottomLeft: Radius.circular(7),
            bottomRight: Radius.circular(19),
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_c.value - i * 0.15) % 1.0;
                final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: p.copper,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// `.chip` / `.chip.hot`.
class _Chip extends StatelessWidget {
  final RefPalette palette;
  final _ChipAction action;
  const _Chip({required this.palette, required this.action});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final hot = action.hot;
    return Material(
      color: hot ? p.tanSoft : p.chipBg,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: hot ? p.copper : p.line,
              width: 1.5,
            ),
            boxShadow: p.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 16, color: hot ? p.copperInk : p.ink2),
              const SizedBox(width: 7),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hot ? p.copperInk : p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.iconbtn` — restart.
class _IconBtn extends StatelessWidget {
  final RefPalette palette;
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({
    required this.palette,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line),
          ),
          child: Icon(icon, size: 19, color: p.ink2),
        ),
      ),
    );
  }
}

/// `.micbtn` — send.
class _MicSendButton extends StatelessWidget {
  final RefPalette palette;
  final VoidCallback onTap;
  const _MicSendButton({required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: p.sunGrad,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.send_rounded,
              size: 20, color: Color(0xFF2B1D12)),
        ),
      ),
    );
  }
}
