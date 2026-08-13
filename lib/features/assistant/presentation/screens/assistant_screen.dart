import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../clients/presentation/widgets/new_client_sheet.dart';
import '../../../devices/presentation/providers/players_provider.dart';
import '../../../devices/presentation/widgets/players_section.dart';
import '../../../devices/presentation/widgets/ref_palette.dart';
import '../../../intake/domain/intake_enums.dart';
import '../../../intake/domain/intake_models.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../../pad_placement/data/recovery_chat_remote_source.dart';
import '../../../pad_placement/data/recovery_engine_remote_source.dart';
import '../../../pad_placement/domain/recovery_chat_models.dart';
import '../../../pad_placement/domain/recovery_engine_models.dart';
import '../../../performance_protocols/data/performance_remote_source.dart';
import '../../../performance_protocols/domain/performance_models.dart';
import '../../../performance_protocols/presentation/providers/performance_catalog_providers.dart';
import '../../../performance_protocols/presentation/providers/performance_session_provider.dart';
import '../../../performance_protocols/presentation/screens/go_to_session.dart';
import '../../../performance_protocols/presentation/screens/pad_map_screen.dart';
import '../../../performance_protocols/presentation/widgets/placement_card.dart';

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

  /// When set, this entry renders as the spec's `.placecard` instead of a
  /// bubble — the pad set the practitioner just landed on.
  final PadSetPayload? placement;

  const _Msg(this.isMe, this.text, {this.rich}) : placement = null;

  const _Msg.card(this.placement)
      : isMe = false,
        text = '',
        rich = null;
}

// The seven hardcoded range-of-motion tests that used to live here are gone.
// They were a guess at the corpus: the engine selects on the test a point is
// AUTHORED against, so a name that isn't one of those matches nothing, and a
// region's real tests ("Neck lateral flexion (ear to shoulder)") were not on the
// list at all. The chips now come from the region's own `movement_tests`.

/// The complaint's side, and the referral's — two fields with two vocabularies,
/// neither borrowed from the other.
///
/// The third option differs on purpose: the complaint's is `bilateral`, the
/// schema enum for `presentation.side`, while the referral's is `both`, which is
/// what the DTO accepts for `referral_side`. Web parity (`SIDE_CHOICES` /
/// `REFERRAL_SIDE_CHOICES`) — and "both" on a referral is a rendering
/// instruction (draw it on both sides) rather than a crossing.
const _kRecoverySides = <(String, String)>[
  ('right', 'Right'),
  ('left', 'Left'),
  ('bilateral', 'Both'),
];

const _kReferralSides = <(String, String)>[
  ('left', 'Left'),
  ('right', 'Right'),
  ('both', 'Both'),
];

// The seven guided-assessment questions that used to run here are GONE, matching
// the web's Jul 25 review: the discomfort intake is region + side + movement
// test + referral, and nothing else.
//
// "How does it feel?" and "How long has it been going on?" fed `symptom_quality`
// and `acuity`, which do score point selection — the referral question is what
// replaced them, and it is the answer that changes the chain most. Thermal is
// unaffected either way: it comes from the retrieved point's own
// `thermal_config` and was never computed from acuity here.

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

  // Guided-assessment chat state (recovery only). `_answers` is what the
  // recovery CHAT surface sends as its screen answers and what the area-of-focus
  // record is built from; the guided flow below fills it as it goes.
  String? _assessmentArea;
  final Map<String, String> _answers = {};

  // ── Recovery flow state (the authored recovery corpus) ────────────────────
  //
  // These hold the ENGINE'S CANONICAL VALUES, never the chip labels. The region
  // the practitioner tapped carries its own id and the resolve matches on that
  // and nothing else: a body-map label sent as `region` resolves to no point at
  // all, and the flow dead-ends with nothing to show for it.
  RecoveryGoal? _recoveryGoal;
  RecoveryRegion? _recoveryRegion;
  String? _recoverySide;
  String? _recoveryAspect;
  String? _recoveryReferral;
  String? _recoveryReferralSide;
  String? _recoveryMovementTest;

  /// Ronel Option B — a region's movement test is skippable when it is too
  /// painful or too limited. Sent explicitly, because the engine reads a missing
  /// test as "no test was offered", which is a different fact.
  bool _recoveryTestSkipped = false;

  // The Part 11 radicular gate. `_nerveReferral` alone is a SELECTION signal
  // (it sets condition_family) and blocks nothing; only its combination with
  // one of the other two is the refer-out.
  bool _nerveReferral = false;
  bool _motorWeakness = false;
  bool _bladderBowelChange = false;

  /// The safety disclaimer is shown once per conversation, not once per topic —
  /// it is the same sentence every time and repeating it above every placement
  /// turns the one thing that must be read into noise.
  bool _disclaimerShown = false;

  // The last placement is deliberately NOT held in a field. It rides on the
  // message that rendered it (`_Msg.card`), which is what the pad map opens
  // from — a "last placement" field and a scrollback of cards disagree the
  // moment a second area is run, and the card you tapped is the one you meant.

  // ── Performance flow state (the pad_protocols catalogue) ──────────────────
  /// The client this prep is for; null = Guest.
  Client? _perfClient;
  String _perfWho = 'Guest';
  String? _perfDiscipline;
  String _perfDisciplineLabel = '';
  String? _perfRole;
  String? _perfSubtype;

  /// Conversation memory for `performance-chat/message` — threaded back on every
  /// turn, which is how the service remembers discipline/role across messages.
  Map<String, dynamic> _slots = const {};

  /// The performance topic slots, explicitly NULLED — how a new topic starts.
  ///
  /// The service keeps its OWN per-session slot memory and merges
  /// `{...serverMemory, ...clientSlots}`, so sending `{}` does not start a new
  /// topic: the server's memory for this `sessionId` survives and a later "hi"
  /// comes back with the last sport's chains instead of the sport list. (The
  /// web console looks stateless only because it sends `sessionId: null`, which
  /// opts out of the memory — and out of the tier-1 safety lock with it.)
  ///
  /// Explicit nulls override the remembered values on the merge, which clears
  /// the topic WITHOUT rotating the session id — so the safety lock survives.
  static const _clearedPerfSlots = <String, dynamic>{
    'discipline': null,
    'role': null,
    'subtype': null,
    'chainId': null,
    'bodyRegion': null,
    'injuryKeyword': null,
    'romGoal': null,
  };

  /// The same idea for `recovery-chat/message`, kept SEPARATE: the two services
  /// hold different slots (`region`/`side`/`goal` vs `discipline`/`role`), so
  /// feeding one's memory to the other resolves nothing and confuses both.
  Map<String, dynamic> _recoverySlots = const {};

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

    // Deep links that already know what they want skip the "performance or
    // recovery?" question entirely. Without this, arriving from the Hub tiles
    // or a player profile dropped you on the generic greeting and made you
    // re-answer something you'd already chosen.
    if (widget.intent == 'performance' || widget.intent == 'recovery') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.intent == 'recovery') {
          _onRecovery();
        } else {
          _onPerformance();
        }
      });
      return;
    }

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

  /// True between requesting a scroll and the post-frame callback running, so a
  /// burst of `_scrollToEnd()` calls in one turn produces ONE animation.
  ///
  /// A single reply can ask to scroll four times (typing on, reply text, pad
  /// card, chips — see `_perfChat`). Each used to schedule its own `animateTo`,
  /// and each new one interrupts the previous mid-flight, which is what made the
  /// list visibly jerk on send.
  bool _scrollQueued = false;

  void _scrollToEnd() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!_scroll.hasClients) return;
      // Animate to the END, not past it. This used to target
      // `maxScrollExtent + 160`, which is outside the scrollable range: the
      // physics clamped it and sprang back, so every message ended with an
      // overscroll bounce. The post-frame callback already runs after layout,
      // so `maxScrollExtent` is the real bottom by this point.
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
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
        // The catalogue as dropdowns, for browsing rather than conversing.
        _ChipAction(Icons.list_alt_rounded, 'Browse protocol chains',
            () => context.push(RoutePaths.performanceProtocols)),
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
    // A new prep is a new topic. Without this the service's session memory
    // answers the next typed message with the PREVIOUS sport's chains.
    _slots = _clearedPerfSlots;
    _me('Performance');

    // If the caller already picked someone — a player profile, or the Game
    // Ready board — carry them through instead of asking again.
    final preselected = ref.read(selectedClientProvider);
    if (preselected != null &&
        ref.read(sessionClientModeProvider) == ClientMode.client) {
      _pickUser(preselected.displayName, client: preselected);
      return;
    }

    await _ai('Who are we prepping? Guest works too — no name needed.');
    final members = await _loadMembers();
    final uni = _isUniversity;
    _showChips([
      _ChipAction(Icons.person_outline_rounded, 'Guest — no name',
          () => _pickUser('Guest'),
          hot: true),
      for (final m in members)
        _ChipAction(Icons.person_outline_rounded, m.clientName,
            () => _pickUser(m.clientName, client: m)),
      _ChipAction(
        uni ? Icons.person_add_alt_1_rounded : Icons.person_add_alt_1_rounded,
        uni ? 'Add player' : 'Add client',
        () => uni
            ? showAddPlayerSheet(context, ref)
            : showNewClientSheet(context, ref),
      ),
    ]);
  }

  void _pickUser(String name, {Client? client}) {
    _me(name);
    // A different person is a different conversation: rotate the session so the
    // previous person's safety lock and slot memory don't follow them. (Rotate
    // only on a real switch — mid-flow it would drop a tier-1 lock.)
    if (client?.id != _perfClient?.id) resetPerformanceSessionFromWidget(ref);
    _perfClient = client;
    _perfWho = name;
    _perfDiscipline = null;
    _perfRole = null;
    _perfSubtype = null;
    // The local fields above and the service's memory have to agree, or the
    // next typed message resolves against the person we just moved off.
    _slots = _clearedPerfSlots;
    _perfStartDiscipline();
  }

  // ── Performance: the pad_protocols catalogue (discipline → role → chain) ────
  //
  // Chip-for-chip the UI spec's `perfFlowSportAsk` → `perfFlowPosition` →
  // `perfFlowPlacements`, with the catalogue endpoints behind it instead of the
  // spec's seeded PLAYBOOK data.

  Future<void> _perfStartDiscipline() async {
    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    final List<Discipline> disciplines;
    try {
      disciplines = await ref.read(disciplinesProvider.future);
    } catch (e) {
      return _failStep('Couldn’t load disciplines', _perfStartDiscipline, e);
    }
    if (!mounted) return;
    setState(() => _typing = false);

    // Reached only when the service answered with a real, empty list — a
    // response we couldn't read throws above and lands in `_failStep`, so this
    // never blames the account for a wiring problem.
    if (disciplines.isEmpty) {
      await _ai('No performance disciplines are authored for this account yet.');
      _showChips([
        _ChipAction(Icons.refresh_rounded, 'Try again', _perfStartDiscipline),
        _ChipAction(Icons.waves_rounded, 'Recovery instead', _onRecovery),
      ]);
      return;
    }

    // The spec's fast path: the player's stored sport + position already resolve
    // in the catalogue, so don't ask what we already know.
    final fast = await _fastPathFor(disciplines);
    if (fast != null) {
      _me('${fast.$1.label} · ${fast.$2}');
      _perfDiscipline = fast.$1.discipline;
      _perfDisciplineLabel = fast.$1.label;
      return _perfPickRole(fast.$2);
    }

    // A single discipline needs no question (spec: `keys.length === 1` skips).
    if (disciplines.length == 1) {
      _perfDiscipline = disciplines.first.discipline;
      _perfDisciplineLabel = disciplines.first.label;
      return _perfStartRole();
    }

    // A picked player already carries their sport on the profile, so don't ask
    // "What are we prepping for?" again — adopt it and go straight to the
    // position step. (The fast path above needs a resolvable position too; this
    // covers the player who has a sport but no position on file.)
    for (final d in disciplines) {
      if (_matchesClientSport(d)) {
        _me(d.label);
        _perfDiscipline = d.discipline;
        _perfDisciplineLabel = d.label;
        return _perfStartRole();
      }
    }

    await _ai('What are we prepping for?');
    _showChips(_disciplineChipsFrom(disciplines));
  }

  /// The tap-flow's discipline picker (ballet, cricket, …), built once so a
  /// typed message that the chat can't resolve to a sport gets the exact same
  /// chip row instead of falling back to the generic home chips.
  List<_ChipAction> _disciplineChipsFrom(List<Discipline> disciplines) => [
        for (final d in disciplines.take(8))
          _ChipAction(Icons.sports_rounded, d.label, () {
            _me(d.label);
            _pickDiscipline(d);
          }, hot: _matchesClientSport(d)),
        if (disciplines.length > 8)
          _ChipAction(Icons.grid_view_rounded, 'Browse all disciplines…',
              () => _showDisciplineSheet(disciplines)),
      ];

  /// Commit a discipline choice and start the position step. A role/subtype
  /// picked under a PREVIOUS discipline (e.g. tapping "Pick another
  /// discipline" after already reaching the chains step, or browsing the full
  /// sheet) must not survive the switch — a stale role/subtype from the old
  /// sport riding along in `_slots` is exactly what made the service answer
  /// with an unresolved "which sport" reply instead of the new sport's chains.
  void _pickDiscipline(Discipline d) {
    _perfDiscipline = d.discipline;
    _perfDisciplineLabel = d.label;
    _perfRole = null;
    _perfSubtype = null;
    _slots = {
      ..._slots,
      'discipline': d.discipline,
      'role': null,
      'subtype': null,
      'chainId': null,
    };
    _perfStartRole();
  }

  Future<void> _perfStartRole() async {
    final discipline = _perfDiscipline;
    if (discipline == null) return _perfStartDiscipline();

    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    final List<RoleOption> roles;
    try {
      roles = await ref.read(rolesProvider(discipline).future);
    } catch (e) {
      return _failStep('Couldn’t load positions', _perfStartRole, e);
    }
    if (!mounted) return;
    setState(() => _typing = false);

    if (roles.isEmpty) {
      await _ai('No positions are authored for $_perfDisciplineLabel yet.');
      _showChips([
        _ChipAction(Icons.edit_outlined, 'Pick another discipline',
            _perfStartDiscipline),
      ]);
      return;
    }

    final clientPositions = await _clientPositionNames();
    await _ai('Select the position or line group.');
    _showChips([
      for (final r in roles)
        _ChipAction(Icons.groups_2_outlined, r.label, () {
          _me(r.label);
          _perfSubtype = r.subtype;
          _perfPickRole(r.role);
        },
            hot: clientPositions
                .any((p) => p.toLowerCase() == r.role.toLowerCase())),
    ]);
  }

  Future<void> _perfPickRole(String role) async {
    _perfRole = role;
    final discipline = _perfDiscipline;
    if (discipline == null) return _perfStartDiscipline();

    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    final List<ChainSummary> chains;
    try {
      chains = await ref.read(
        chainsProvider(ChainsQuery(discipline, role, subtype: _perfSubtype))
            .future,
      );
    } catch (e) {
      return _failStep('Couldn’t load chains', () => _perfPickRole(role), e);
    }
    if (!mounted) return;
    setState(() => _typing = false);

    if (chains.isEmpty) {
      await _ai('No chains are authored for $role yet.');
      _showChips([
        _ChipAction(
            Icons.edit_outlined, 'Pick another position', _perfStartRole),
      ]);
      return;
    }

    // A MENU, not a ranking — these carry no scores, so no "closest match"
    // language (the exact bug e5ef4f6 fixed).
    await _ai('Here are the chains for $role.');
    _showChips([
      for (final c in chains)
        _ChipAction(Icons.link_rounded, c.label, () {
          _me(c.label);
          _perfPads(c);
        }),
    ]);
  }

  Future<void> _perfPads(ChainSummary chain) async {
    // The chain's OWN discipline/role win when it carries them. A chat option
    // list spans roles — "cricket" offers Fast Bowler, Batsman and Fielder
    // chains in one list — so fetching every tapped chain under the
    // conversation's current role asks for combinations that don't exist.
    final discipline = chain.discipline ?? _perfDiscipline;
    final role = chain.role ?? _perfRole;
    if (discipline == null || role == null) return _perfStartDiscipline();
    // Keep the conversation on whatever the practitioner just picked, so
    // "Change position" and a follow-up message continue from there.
    _perfDiscipline = discipline;
    _perfRole = role;

    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    try {
      final payload = await ref.read(performanceRemoteSourceProvider).chain(
            discipline: discipline,
            role: role,
            chainId: chain.chainId,
            subtype: chain.subtype ?? _perfSubtype,
            sessionId: ref.read(performanceSessionIdProvider),
          );
      if (!mounted) return;
      setState(() => _typing = false);

      // The catalogue runs the same safety guard as retrieval — a block answers
      // `chain: null`, never pads.
      if (payload.isRefusal) return _refusal(payload.refusalMessage);

      await _showPlacement(payload);
    } on PerformanceRefusal catch (r) {
      if (!mounted) return;
      setState(() => _typing = false);
      _refusal(r.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _typing = false);
      _failStep('Couldn’t load the pad set', () => _perfPads(chain), e);
    }
  }

  /// The spec's `.placecard` + its delayed follow-up chips.
  Future<void> _showPlacement(PadSetPayload payload) async {
    final context = payload.contextLine;
    await _ai('Placements ready for $_perfWho'
        '${context.isEmpty ? '' : ' — $context'}.');
    if (!mounted) return;
    setState(() => _messages.add(_Msg.card(payload)));
    _scrollToEnd();

    // The spec delays these by ~600 ms so the card lands first.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _showChips([
      _ChipAction(Icons.autorenew_rounded, 'Prep another user', _onPerformance),
      _ChipAction(Icons.edit_outlined, 'Change position', _perfStartRole),
    ]);
  }

  /// The pad map — ONE screen for both surfaces.
  ///
  /// Which one this is comes off the payload itself rather than off flow state:
  /// the card that opened it is a widget in a scrolled list and may well be from
  /// a recovery turn the conversation has since moved past, so reading
  /// `_recovery` here would title an old card by what is happening now.
  void _openPadMap(PadSetPayload payload) {
    final isRecovery = payload.discipline == 'recovery';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PadMapScreen(
          payload: payload,
          clientName: _perfWho,
          title: isRecovery ? 'Recovery Placement' : 'Performance Placement',
          // "Performance Activation" is the performance flow's default stack.
          // Loading it off a recovery placement would announce a protocol
          // nothing about this placement asked for.
          preloadProtocol: !isRecovery,
        ),
      ),
    );
  }

  /// A safety-guard block: show what the service said, offer a way onward, and
  /// never open the 3D view.
  void _refusal(String? message) {
    _messages.add(_Msg(
      false,
      message ??
          'I can’t bring up a placement for that. If this is urgent, please '
              'get in-person care.',
    ));
    setState(() {});
    _scrollToEnd();
    _showChips([
      _ChipAction(Icons.link_rounded, 'Try another chain', _perfStartRole),
      _ChipAction(Icons.waves_rounded, 'Recovery instead', _onRecovery),
    ]);
  }

  /// [detail] carries the server's own words (wrong base URL, unreadable
  /// payload, timeout) — without it every failure reads the same and there's
  /// nothing to act on.
  Future<void> _failStep(String message, VoidCallback retry,
      [Object? detail]) async {
    if (!mounted) return;
    setState(() => _typing = false);
    final because = detail == null ? '' : '\n\n${_reason(detail)}';
    await _ai('$message — tap to retry.$because');
    if (!mounted) return;
    _showChips([
      _ChipAction(Icons.refresh_rounded, 'Try again', retry),
      _ChipAction(Icons.home_rounded, 'Start over', _startOver),
    ]);
  }

  static String _reason(Object error) {
    if (error is ServerException) return error.message;
    return error.toString();
  }

  /// "Start over" — the one place a genuinely new conversation begins, so it is
  /// the one place the session id rotates. Clearing the bubbles alone left the
  /// service still holding the old topic (and the old safety lock) server-side,
  /// which is how a fresh-looking chat kept answering with the last sport.
  void _startOver() {
    resetPerformanceSessionFromWidget(ref);
    _slots = const {};
    _recoverySlots = const {};
    _resetRecovery();
    // The transcript is cleared, so the disclaimer goes with it and has to be
    // said again — a placement reached without it on screen is the one state
    // this must not have.
    _disclaimerShown = false;
    setState(_initialize);
  }

  void _showDisciplineSheet(List<Discipline> all) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisciplineSheet(
        disciplines: all,
        onPick: (d) {
          Navigator.of(context).pop();
          _me(d.label);
          _pickDiscipline(d);
        },
      ),
    );
  }

  bool _matchesClientSport(Discipline d) {
    final sport = _perfClient?.sport?.trim().toLowerCase();
    if (sport == null || sport.isEmpty) return false;
    return d.label.toLowerCase() == sport ||
        d.discipline.toLowerCase() == sport;
  }

  /// The player's position names, resolved from the org's sport mapping (the
  /// client model stores Position ObjectIds, not names).
  Future<List<String>> _clientPositionNames() async {
    final ids = _perfClient?.positions ?? const [];
    if (ids.isEmpty) return const [];
    try {
      final sports = await ref.read(orgSportsProvider.future);
      final names = <String>[];
      for (final sport in sports) {
        for (final pos in sport.positions) {
          if (ids.contains(pos.id)) names.add(pos.name);
        }
      }
      return names;
    } catch (_) {
      return const [];
    }
  }

  /// The spec's deterministic fast path: sport + position already on the
  /// profile → skip both questions and go straight to chains.
  Future<(Discipline, String)?> _fastPathFor(
      List<Discipline> disciplines) async {
    final client = _perfClient;
    if (client == null) return null;
    Discipline? discipline;
    for (final d in disciplines) {
      if (_matchesClientSport(d)) {
        discipline = d;
        break;
      }
    }
    if (discipline == null) return null;

    final positions = await _clientPositionNames();
    if (positions.isEmpty) return null;
    try {
      final roles = await ref.read(rolesProvider(discipline.discipline).future);
      for (final r in roles) {
        for (final pos in positions) {
          if (r.role.toLowerCase() == pos.toLowerCase()) {
            _perfSubtype = r.subtype;
            return (discipline, r.role);
          }
        }
      }
    } catch (_) {
      // Fall back to asking.
    }
    return null;
  }

  // ── Recovery: the guided flow, ported from the web's RecoveryEngineFlow ─────
  //
  // GOAL FIRST, THEN THE AREA. "What are we working on?" is the opening question
  // in both clients, and the order is load-bearing rather than a preference: the
  // engine's selector hard-filters on `goal_pathway` before it looks at anything
  // else, so the region list is SCOPED to the chosen pathway. Asking for the area
  // first means offering areas the pathway has no point for — which is how
  // `performance_recovery` + `full-body` became offerable on the web and answered
  // nothing.
  //
  // EVERY CHIP IS AUTHORED DATA. The goals' counts, the areas, the movement tests
  // and their `reveals`, the aspects, the sides and the referral menu all come
  // from the serving library's own catalogue. The hardcoded body-map labels and
  // the seven-item ROM list that used to be here were the bug: they offered areas
  // the corpus cannot answer for and named tests no point is authored against.
  //
  // WHAT THIS PATHWAY NO LONGER ASKS, matching the web's Jul 25 review: the
  // "how does it feel?" and "how long has it been going on?" steps are gone from
  // the discomfort intake. Thermal comes from the retrieved point's own
  // `thermal_config` and was never computed from acuity, so dropping them cannot
  // change a thermal recommendation; they DID feed point selection, and the
  // referral question is what replaced them.
  Future<void> _onRecovery() async {
    _recovery = true;
    // Recovery keeps its slots CLIENT-side only (the service has no session
    // memory of its own), so an empty map really does start a new topic here.
    _recoverySlots = const {};
    _resetRecovery();
    _me('Recovery');
    _askGoal();
  }

  void _resetRecovery() {
    _recoveryGoal = null;
    _recoveryRegion = null;
    _recoverySide = null;
    _recoveryAspect = null;
    _recoveryReferral = null;
    _recoveryReferralSide = null;
    _recoveryMovementTest = null;
    _recoveryTestSkipped = false;
    _nerveReferral = false;
    _motorWeakness = false;
    _bladderBowelChange = false;
    _assessmentArea = null;
    _answers.clear();
  }

  // ── Step 1: "What are we working on?" ──────────────────────────────────────

  /// The four pathways, ASKED IMMEDIATELY.
  ///
  /// They are a fixed list — the same `PATHWAYS` constant the web renders — so
  /// the question does not wait on a request. The dispatch is kicked off behind
  /// it and awaited at the next step, which is the web's shape too: its goal grid
  /// renders on mount while the cutover/screen/intake effect is still in flight.
  ///
  /// That ordering matters here more than it does on the web. The v3 intake
  /// derives the catalogue from the whole live corpus and takes ~40 s against a
  /// dev tunnel; blocking the first question on it means staring at a typing
  /// bubble before there is anything to even choose between.
  ///
  /// Stays a `VoidCallback` — "change goal" and "start over" both come back here.
  void _askGoal() {
    // Start the fetch NOW, without awaiting it. By the time a goal is tapped and
    // its blurb has been read, this has usually landed.
    //
    // The `.ignore()` swallows the rejection HERE and nowhere else: the failure
    // is still held by the provider and is surfaced by the step that awaits it
    // (`_askRegion`), which is where there is something to say about it. Without
    // it an early failure is an unhandled async error that crashes the zone
    // before the flow ever gets to report it.
    ref.read(recoveryDispatchProvider.future).ignore();
    _showGoalChips();
  }

  Future<void> _showGoalChips() async {
    // ALWAYS SHOWN, WITH NOTHING TO CLICK. This is the whole of what replaced
    // the red-flag screen as a UI gate: the questions are still fetched and
    // still answered on the wire, and the ENGINE still runs the universal
    // pre-gate on every resolve. What went is the client-side asking.
    //
    // The authored sentence when the screen has already loaded, the generic
    // floor when it has not — never nothing, because a placement reached with no
    // disclaimer on screen is the one state this must not have.
    if (!_disclaimerShown) {
      _disclaimerShown = true;
      final screen = ref.read(recoveryDispatchProvider).valueOrNull?.screen;
      await _ai((screen ?? const RecoverySafetyScreen()).disclaimerOrFallback);
      if (!mounted) return;
    }

    await _ai('What are we working on?');
    if (!mounted) return;
    // Every pathway is offered, as the web offers every card. Whether the corpus
    // can actually answer for one is a question about REGIONS, and it is
    // answered at the next step against that pathway's own list — hiding a goal
    // on a count would also hide it whenever the catalogue is merely slow.
    _showChips([
      for (final goal in RecoveryGoal.all)
        _ChipAction(_goalIcon(goal), goal.label, () => _pickGoal(goal)),
    ]);
  }

  Future<void> _pickGoal(RecoveryGoal goal) async {
    _me(goal.label);
    _resetRecovery();
    _recoveryGoal = goal;
    _answers['goal'] = goal.value;
    // The card's blurb, said once, so the pathway's scope is stated before the
    // area list narrows to it. Doubles as cover for the catalogue fetch.
    if (goal.blurb.isNotEmpty) await _ai(goal.blurb);
    if (!mounted) return;
    await _askRegion();
  }

  // ── Step 2: the area, scoped to the chosen pathway ─────────────────────────

  /// THE STEP THAT WAITS. Everything the area list needs — which generation is
  /// serving, and that generation's catalogue — is fetched here, or was started
  /// when the goal question went up and is simply awaited.
  ///
  /// A failed dispatch stops the flow rather than falling back: with no
  /// generation there is no endpoint to send a resolve to, and resolving against
  /// whichever library used to be right returns a wrong answer that looks exactly
  /// like a real one.
  Future<void> _askRegion() async {
    final goal = _recoveryGoal;
    if (goal == null) return _askGoal();

    final RecoveryDispatch dispatch;
    try {
      dispatch = await _awaitDispatch();
    } catch (e) {
      await _failStep('Couldn’t reach the recovery engine', _askRegion, e);
      return;
    }
    if (!mounted) return;

    if (dispatch.hasNothingToOffer) {
      // A catalogue that LOADED and offers nothing is a deployment fact, not a
      // network failure, so there is no "try again" chip: it would be a lie. The
      // message distinguishes "nothing published" from "published and being
      // refused wholesale", which are different faults with different owners.
      await _ai(dispatch.emptyCatalogReason);
      if (!mounted) return;
      _showChips([
        _ChipAction(Icons.bolt_rounded, 'Performance instead', _onPerformance),
        _ChipAction(Icons.home_rounded, 'Start over', _startOver),
      ]);
      return;
    }

    final regions = dispatch.catalog.regionsFor(goal.value);
    if (regions.isEmpty) {
      // The library has content and this pathway has none — a real, specific
      // answer, and a different one from "the library is empty".
      await _ai('Nothing is authored for ${goal.label.toLowerCase()} yet. '
          'Pick another goal.');
      if (!mounted) return;
      _showChips([
        _ChipAction(Icons.tune_rounded, 'Change goal', _askGoal),
        _ChipAction(Icons.bolt_rounded, 'Performance instead', _onPerformance),
      ]);
      return;
    }

    await _ai(goal.regionPrompt);
    if (!mounted) return;
    _showChips([
      for (final r in regions)
        _ChipAction(_areaIcon(r.label), r.label, () => _pickRegion(r)),
      _ChipAction(Icons.tune_rounded, 'Change goal', _askGoal),
    ]);
  }

  /// The dispatch, awaited behind a typing bubble ONLY if it has not landed yet.
  ///
  /// Cached after the first run, so every later step — "another area", "change
  /// goal", a second topic — reads it with no request and no bubble.
  Future<RecoveryDispatch> _awaitDispatch() async {
    final cached = ref.read(recoveryDispatchProvider).valueOrNull;
    if (cached != null) return cached;

    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();
    try {
      return await ref.read(recoveryDispatchProvider.future);
    } finally {
      if (mounted) setState(() => _typing = false);
    }
  }

  Future<void> _pickRegion(RecoveryRegion region) async {
    _me(region.label);
    _recoveryRegion = region;
    _assessmentArea = region.label;
    _recoveryAspect = null;
    _recoveryReferral = null;
    _recoveryReferralSide = null;
    _recoveryMovementTest = null;
    _recoveryTestSkipped = false;
    _answers['area'] = region.label;
    await _askAspect();
  }

  /// Front/back or inner/outer — asked ONLY where the region permits a CHOICE.
  /// One authored value is not a question: a corpus authored entirely
  /// "posterior" for the low back has nothing to ask, which is exactly what
  /// v3.1 removed from the lower, upper and mid back.
  Future<void> _askAspect() async {
    final region = _recoveryRegion!;
    final aspects = region.aspects.where((a) => a != 'na').toList();
    if (!region.aspectOffered || aspects.length < 2) {
      await _askSide();
      return;
    }
    await _ai('Which part of the ${region.label.toLowerCase()}?');
    if (!mounted) return;
    _showChips([
      for (final a in aspects)
        _ChipAction(Icons.my_location_rounded, _aspectLabel(a), () {
          _me(_aspectLabel(a));
          _recoveryAspect = a;
          _askSide();
        }),
    ]);
  }

  /// Which side.
  ///
  /// It used to be read out of the chip label ("Left Knee"), which the authored
  /// region ids carry no equivalent of — `knee` is one region and the side is a
  /// fact about the person in front of you. Getting it wrong mirrors the chain.
  /// Not asked on the lymphatic pathway, which drains through a hub.
  Future<void> _askSide() async {
    final goal = _recoveryGoal!;
    if (!goal.asksSide) {
      await _afterSide();
      return;
    }
    await _ai('Which side?');
    if (!mounted) return;
    _showChips([
      for (final s in _kRecoverySides)
        _ChipAction(_sideIcon(s.$1), s.$2, () {
          _me(s.$2);
          _recoverySide = s.$1;
          _afterSide();
        }),
    ]);
  }

  Future<void> _afterSide() async {
    if (_recoveryGoal!.asksMovementTest) {
      await _showRoms();
      return;
    }
    await _askNerveReferral();
  }

  // ── Step 3 (discomfort only): the region's own movement tests ──────────────

  Future<void> _showRoms() async {
    final region = _recoveryRegion!;
    final tests = region.movementTests;
    if (tests.isEmpty) {
      // Not rendered empty and not pointlessly skippable: on v2 most points are
      // direct-select and there is genuinely nothing to run.
      await _ai('No movement test is authored for '
          '${region.label.toLowerCase()}, so we go straight on.');
      if (!mounted) return;
      await _askReferral();
      return;
    }

    await _ai('Which movement did you try? Run one of these and note where '
        'else you feel it — each one reveals something different.');
    if (!mounted) return;
    _showChips([
      for (var i = 0; i < tests.length; i++)
        _ChipAction(_romIcon(tests[i].test), tests[i].test,
            () => _pickRom(tests[i].test),
            hot: i == 0),
      // Ronel's Option B, kept: a test that is too painful or too limited is
      // skipped and the point selected directly. "I ran this one" and "I could
      // not run any" are different answers, so skipping clears the chosen test.
      _ChipAction(Icons.do_not_touch_outlined, 'Too painful — skip the test',
          _skipRom),
    ]);
  }

  Future<void> _skipRom() async {
    _me('Too painful — skip the test');
    _recoveryTestSkipped = true;
    _recoveryMovementTest = null;
    _answers['movementTest'] = 'skipped';
    await _askReferral();
  }

  Future<void> _pickRom(String testName) async {
    _me(testName);
    _recoveryMovementTest = testName;
    _recoveryTestSkipped = false;
    _answers['movementTest'] = testName;

    // The test's authored reading, where the catalogue describes it. Never
    // templated: a test the config does not describe gets no sentence rather
    // than a manufactured one — that wording is clinical and is not written here.
    final reveals = _revealsFor(testName);
    if (reveals.isNotEmpty) {
      await _ai('That tells us about the $reveals.');
      if (!mounted) return;
    }
    await _askReferral();
  }

  String _revealsFor(String testName) {
    for (final t in _recoveryRegion?.movementTests ?? const <RecoveryMovementTest>[]) {
      if (t.test.trim().toLowerCase() == testName.trim().toLowerCase()) {
        return t.reveals.trim();
      }
    }
    return '';
  }

  // ── Step 4 (discomfort only, optional): does it travel? ────────────────────

  /// The referral is the answer that changes the placement most: a low-back
  /// complaint travelling to the calf runs the calf's set alongside the primary
  /// one this session, instead of sequencing it for a later visit.
  ///
  /// CHIPS ONLY, from the region's AUTHORED menu. A destination not on it is one
  /// the engine has no chain for, so a free-text box could only ever produce a
  /// no-match dressed up as a question the user was invited to answer.
  Future<void> _askReferral() async {
    final region = _recoveryRegion!;
    if (!_recoveryGoal!.asksReferral || region.referralMenu.isEmpty) {
      await _askNerveReferral();
      return;
    }
    await _ai('Does it travel anywhere else?');
    if (!mounted) return;
    _showChips([
      _ChipAction(Icons.check_circle_outline, 'No — just there', () {
        _me('No — just there');
        _recoveryReferral = null;
        _recoveryReferralSide = null;
        _askNerveReferral();
      }, hot: true),
      for (final target in region.referralMenu)
        _ChipAction(_areaIcon(target), _titleCase(target), () {
          _me(_titleCase(target));
          _recoveryReferral = target;
          _askReferralSide();
        }),
    ]);
  }

  /// WHICH SIDE IT TRAVELS TO — its own question, and clinically it has to be.
  ///
  /// A referral on the OTHER side is a cross-body chain, a different case type
  /// the library has essentially none of (1 authored point against 69 same-side).
  /// The engine derives the case type from this against the complaint side, and
  /// the user is the only one who knows which they have. Defaulted to the
  /// complaint side, so the common case is one tap and a crossing is deliberate.
  Future<void> _askReferralSide() async {
    final target = _titleCase(_recoveryReferral ?? '');
    await _ai('Which side does it travel to?');
    if (!mounted) return;
    _showChips([
      for (final s in _kReferralSides)
        _ChipAction(_sideIcon(s.$1), s.$2, () {
          _me(s.$2);
          _recoveryReferralSide = s.$1;
          // Said in words, because "left" beside "left" is not obviously a
          // same-side chain and "left" beside "right" is not obviously a
          // crossing. The engine names the pattern on the result; this is the
          // same statement at the moment of choosing, so it is not a surprise.
          _ai(s.$1 == 'both'
              ? 'Both sides — the ${target.toLowerCase()} pads are drawn left and right.'
              : (_recoverySide != null && _recoverySide != s.$1)
                  ? 'That’s a cross-body pattern. The main pads stay on the '
                      '$_recoverySide; the ${target.toLowerCase()} pads go on the ${s.$1}.'
                  : 'Same side — the ${target.toLowerCase()} pads go on the '
                      '${s.$1} with the main pads.');
          _askNerveReferral();
        }),
    ]);
  }

  // ── Step 5: the radicular detail ───────────────────────────────────────────

  /// The Part 11 radicular gate, which the universal red-flag screen cannot
  /// reach — it never asks about bladder or bowel.
  ///
  /// It is also the ONLY control that sets `condition_family: nerve_referral`,
  /// which the selector reads, so it is an input to the placement and not only a
  /// gate question. On the web it is a collapsed practitioner panel; a chat has
  /// no "collapsed", so it is one question with an easy No.
  ///
  /// A nerve-referral pattern ALONE blocks nothing — it is a selection signal.
  /// Only the combination with weakness or a bladder/bowel change is the
  /// refer-out.
  /// No longer asked — always defaults to No (no nerve-referral pattern, no
  /// motor weakness, no bladder/bowel change) and moves straight to the
  /// resolve, instead of prompting the user for it.
  Future<void> _askNerveReferral() async {
    _nerveReferral = false;
    _motorWeakness = false;
    _bladderBowelChange = false;
    await _finishAssessment();
  }

  // ── The resolve ────────────────────────────────────────────────────────────

  /// The pad set, and the same `.placecard` performance lands on.
  ///
  /// The answer comes back as authored pad geometry — a Sun and a Moon pad per
  /// set, each with its landmark anchor and target muscles — which is the
  /// identical shape the performance pad set has. So it renders through the same
  /// [PlacementCard] and the same [PadMapScreen], with the same 3D stage and the
  /// same marker mapper, rather than through a recovery-only summary bubble that
  /// could only list the pads as text.
  Future<void> _finishAssessment() async {
    // Record the picked area as the session's area of focus so the Session tab
    // and the AI report see it. Start Session is NOT gated on this — running
    // the recovery flow first is optional.
    _recordAreaOfFocus();

    final region = _recoveryRegion;
    final goal = _recoveryGoal;
    if (region == null || goal == null) return _askGoal();

    // Cached by now — the area list could not have been drawn without it — but
    // read through the same await so there is one way to get the generation and
    // no path that resolves without one.
    final RecoveryDispatch dispatch;
    try {
      dispatch = await _awaitDispatch();
    } catch (e) {
      await _failStep(
          'Couldn’t reach the recovery engine', _finishAssessment, e);
      return;
    }
    if (!mounted) return;

    setState(() {
      _chipsVisible = false;
      _typing = true;
    });
    _scrollToEnd();

    final RecoveryPlacement placement;
    try {
      placement = await ref.read(recoveryEngineRemoteSourceProvider).resolve(
            generation: dispatch.generation,
            goal: goal.value,
            region: region.region,
            regionLabel: region.label,
            side: _recoverySide,
            movementTest: _recoveryMovementTest,
            movementTestSkipped: _recoveryTestSkipped,
            aspect: _recoveryAspect,
            referralTarget: _recoveryReferral,
            referralSide: _recoveryReferralSide,
            // Every authored flag, answered NO, from the screen's own keys —
            // not `{}`, which is the different statement "not asked".
            redFlags: dispatch.screen.allFlagsNo,
            nerveReferral: _nerveReferral,
            motorWeakness: _motorWeakness,
            bladderBowelChange: _bladderBowelChange,
            sessionId: ref.read(performanceSessionIdProvider),
          );
    } catch (e) {
      await _failStep(
          'Couldn’t generate the pad placement', _finishAssessment, e);
      return;
    }
    if (!mounted) return;
    setState(() => _typing = false);

    // A refer-out, or nothing authored for this combination. Both come back 200
    // with no sets, and neither may open the 3D view.
    if (!placement.hasPads) {
      await _ai(placement.emptyReason);
      if (!mounted) return;
      _showChips([
        _ChipAction(Icons.waves_rounded, 'Try another area', _askRegion),
        _ChipAction(Icons.tune_rounded, 'Change goal', _askGoal),
      ]);
      return;
    }

    await _showRecoveryPlacement(placement);
  }

  Future<void> _showRecoveryPlacement(RecoveryPlacement placement) async {
    // The compliance-authored client sentence, rendered VERBATIM. The backend
    // owns this wording on purpose and it is never rephrased here.
    final claim = placement.wellnessClaim.trim();
    await _ai(claim.isEmpty
        ? 'Placements ready for ${placement.payload.displayName}.'
        : claim);
    if (!mounted) return;

    setState(() => _messages.add(_Msg.card(placement.payload)));
    _scrollToEnd();

    // The thermal mode is a RECOMMENDATION and the device is not driven from
    // it, so it is said in words next to the card rather than pre-set anywhere.
    final thermal = [
      if (placement.thermalMode.trim().isNotEmpty)
        '${placement.thermalLabel} recommended',
      if (placement.thermalRationale.trim().isNotEmpty)
        placement.thermalRationale.trim(),
    ].join(' — ');
    if (thermal.isNotEmpty) await _ai(thermal);
    if (!mounted) return;

    if (placement.cautions.isNotEmpty) {
      await _ai('⚠ ${placement.cautions.join(' · ')}');
      if (!mounted) return;
    }

    // The spec delays these by ~600 ms so the card lands first.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _showChips([
      _ChipAction(Icons.play_arrow_rounded, 'Start session',
          () => context.go(RoutePaths.devices),
          hot: true),
      _ChipAction(Icons.waves_rounded, 'Another area', _askRegion),
      _ChipAction(Icons.tune_rounded, 'Change goal', _askGoal),
    ]);
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

    // WHAT THE FLOW ACTUALLY ASKED, and nothing it did not.
    //
    // The discomfort level, the behaviour and the duration used to come from
    // three chat questions this pathway no longer asks. Their old fallbacks —
    // `0`, "comes and goes", "less than 6 weeks" — are still what the record
    // carries, but they are now DEFAULTS rather than answers, so they are not
    // dressed up as findings in the notes. Someone reading the area of focus
    // should be able to tell an unanswered field from a reported one.
    final notes = [
      if (_recoveryGoal != null) 'Goal: ${_recoveryGoal!.label}',
      if ((_answers['movementTest'] ?? '').isNotEmpty)
        'Movement: ${_answers['movementTest']}',
      if ((_recoveryReferral ?? '').isNotEmpty)
        'Travels to: ${_titleCase(_recoveryReferral!)}',
    ].join(' · ');

    ref.read(guidedAssessmentProvider.notifier).addArea(
          DiscomfortAreaInput(
            bodyPart: area,
            side: _sideEnum(),
            discomfortBefore: 0,
            behavior: DiscomfortBehavior.comesAndGoes,
            temporalDuration: TemporalDuration.lessThan6Weeks,
            notes: notes.isEmpty ? null : notes,
          ),
        );
  }

  /// The side the practitioner ACTUALLY chose, not one parsed back out of a
  /// label. The authored region ids carry no side ("knee", never "Left Knee"),
  /// so there is nothing in the label to read.
  DiscomfortSide _sideEnum() {
    switch (_recoverySide) {
      case 'left':
        return DiscomfortSide.left;
      case 'right':
        return DiscomfortSide.right;
      default:
        return DiscomfortSide.both;
    }
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
    // The manual movement-test entry is gone. The engine selects on the test a
    // point is AUTHORED against, so a typed movement that is not on the region's
    // menu matches nothing — a no-match dressed up as a question the user was
    // invited to answer. A typed message goes to the chat surface like any other.
    _me(text);
    // Two chatbots, one input box. A typed message must reach the surface the
    // conversation is actually on: the recovery corpus can't answer "hamstring
    // chain for a sprinter" and the performance corpus can't answer "my low
    // back is tight", so sending everything to one of them made half the
    // messages unanswerable. Nothing chosen yet → performance, as before.
    if (_recovery) {
      _recoveryChat(text);
    } else {
      _perfChat(text);
    }
  }

  // ── Typed text → performance-chat (the query path, conversationally) ────────

  /// `POST performance-chat/message`. [_slots] is threaded back every turn —
  /// that is the conversation memory, so a follow-up doesn't re-ask the
  /// discipline. The reply's `render`/`results` are the query service's output
  /// verbatim, so pads render through the same card as the catalogue path.
  /// The catalogue discipline this message names OUTRIGHT — the whole message
  /// is the sport and nothing else ("cricket").
  ///
  /// Returns null when the catalogue isn't in cache yet or the message says
  /// more than the sport ("cricket fast bowler"); both fall through to the chat,
  /// which is the general case. Deliberately reads the CACHE and never awaits:
  /// a typed message must not pay for a catalogue fetch just to find out it
  /// wasn't a sport name.
  Discipline? _disciplineNamedOutright(String text) {
    final list = ref.read(disciplinesProvider).valueOrNull;
    if (list == null) return null;
    final t = text.trim().toLowerCase();
    for (final d in list) {
      if (d.label.trim().toLowerCase() == t ||
          d.discipline.trim().toLowerCase() == t) {
        return d;
      }
    }
    return null;
  }

  Future<void> _perfChat(String text) async {
    // A bare sport name needs no chat turn: the catalogue already knows the
    // sport, and the position step is where this was always going to land. It
    // answers in about a second instead of the ~90 s a retrieval turn costs.
    final named = _disciplineNamedOutright(text);
    if (named != null) {
      _perfDiscipline = named.discipline;
      _perfDisciplineLabel = named.label;
      _perfRole = null;
      _perfSubtype = null;
      // Keep the service's memory in step, or a LATER typed message resolves
      // against the sport and position we just moved off.
      _slots = {
        ..._slots,
        'discipline': named.discipline,
        'role': null,
        'subtype': null,
        'chainId': null,
      };
      return _perfStartRole();
    }

    // Whether a position was already on the table BEFORE this turn. Needed
    // below to tell "the service chose a position for them" apart from "they
    // are following up on the position they already picked".
    final roleBefore = (_slots['role']?.toString().trim().isNotEmpty ?? false)
        ? _slots['role'].toString().trim()
        : _perfRole;

    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    final ChatReply reply;
    try {
      reply = await ref.read(performanceRemoteSourceProvider).chatMessage(
            message: text,
            sessionId: ref.read(performanceSessionIdProvider),
            slots: _slots,
            screenAnswers: _screenAnswers(),
          );
    } on PerformanceRefusal catch (r) {
      if (!mounted) return;
      setState(() => _typing = false);
      return _refusal(r.message);
    } catch (e) {
      return _failStep(
          'Couldn’t reach the assistant', () => _perfChat(text), e);
    }
    if (!mounted) return;

    setState(() {
      _typing = false;
      // MERGE, don't replace. When the typed text doesn't match anything the
      // service resets ITS OWN session slots to null rather than echoing back
      // what was already picked — blindly assigning `_slots = reply.slots` in
      // that case wiped the discipline/role we already had (and the NEXT
      // typed turn would then carry that emptied map to the service, making
      // the loss stick). Keep every existing value; only overwrite a key when
      // the reply actually resolved something non-empty for it, so an
      // unmatched message is a no-op for state instead of a silent restart.
      if (reply.slots.isNotEmpty) {
        final merged = Map<String, dynamic>.from(_slots);
        for (final entry in reply.slots.entries) {
          final value = entry.value;
          final isEmpty =
              value == null || (value is String && value.trim().isEmpty);
          if (!isEmpty) merged[entry.key] = value;
        }
        _slots = merged;
      }
    });
    _adoptSlots(reply.slots);

    // ── Bare sport name → let them pick the position ─────────────────────────
    //
    // Asked only for a discipline ("cricket"), the service resolves a position
    // ITSELF — the top-ranked one — and answers with that position's chains.
    // For someone who named a sport and nothing else that is a silent choice:
    // cricket has Batsman and Fielder chains too, and neither was offered.
    //
    // So when a position appears that was neither on the table before this turn
    // nor named in the message, drop into the catalogue's position picker
    // instead of the service's narrowed answer. It's the same step the chip
    // flow uses, and it answers in about a second against the catalogue rather
    // than another full chat turn.
    final resolvedRole = reply.slots['role']?.toString().trim() ?? '';
    final roleWasChosenForThem = resolvedRole.isNotEmpty &&
        (roleBefore == null || roleBefore.isEmpty) &&
        !text.toLowerCase().contains(resolvedRole.toLowerCase());
    if (!reply.hasPads && roleWasChosenForThem && _perfDiscipline != null) {
      // The chat's slots carry no display name, but its option rows do — take
      // it so the position step can name the sport in its empty state.
      if (_perfDisciplineLabel.isEmpty) {
        _perfDisciplineLabel =
            reply.options.firstOrNull?.displayName ?? _perfDiscipline!;
      }
      // Nothing is narrowed to this position yet, so don't let it leak into
      // the catalogue call or into the next typed turn.
      _perfRole = null;
      _perfSubtype = null;
      _slots = {..._slots, 'role': null, 'subtype': null, 'chainId': null};
      return _perfStartRole();
    }

    // The service couldn't resolve the typed text to a sport it has chains
    // for. Its own reply text at this point tends to just echo/name the
    // unmatched sport back in prose — not tappable, and redundant once the
    // chip picker below repeats the same names as actual buttons — so skip
    // printing it and ask the tap flow's own question instead, followed by
    // the exact same discipline chips (ballet, cricket, …) rather than the
    // generic home chips.
    //
    // The service can also fail to resolve mid-conversation, once a
    // discipline (and maybe a role) is already picked — its own prose at that
    // point (e.g. "…I have documented protocol for: Ballet, Basketball, …")
    // reads as a reset back to square one. It isn't: we already know where
    // the conversation left off, so re-show THAT step instead of printing the
    // service's reply. Not gated on the reply's wording — any unresolved
    // message mid-flow should return to the current step, since the wording
    // the backend uses for "didn't understand that" isn't a stable contract.
    // A role was already picked → the chains for it, unchanged (not the
    // discipline picker); a discipline only → the position picker.
    if (!reply.hasPads && reply.options.isEmpty) {
      if (_perfRole != null) {
        return _perfPickRole(_perfRole!);
      }
      if (_perfDiscipline != null) {
        return _perfStartRole();
      }
    }
    if (!reply.hasPads && reply.options.isEmpty && _perfDiscipline == null) {
      try {
        final disciplines = await ref.read(disciplinesProvider.future);
        if (mounted && disciplines.isNotEmpty) {
          await _ai('What are we prepping for?');
          _showChips(_disciplineChipsFrom(disciplines));
          return;
        }
      } catch (_) {
        // Fall through to the service's own reply/home chips below.
      }
    }

    if (reply.reply.trim().isNotEmpty) {
      setState(() => _messages.add(_Msg(false, reply.reply.trim())));
      _scrollToEnd();
    } else if (reply.needs.isNotEmpty) {
      await _ai('I need a bit more first: ${reply.needs.join(', ')}.');
    }

    if (reply.hasPads) {
      final ranked = reply.results;
      setState(() => _messages.add(_Msg.card(ranked.first.payload)));
      _scrollToEnd();
      _showChips([
        // These DO carry scores, so ranking language is honest here.
        for (final r in ranked.skip(1).take(3))
          _ChipAction(
            Icons.link_rounded,
            r.payload.chain?.name ?? 'Another match',
            () {
              _me(r.payload.chain?.name ?? 'Another match');
              setState(() => _messages.add(_Msg.card(r.payload)));
              _scrollToEnd();
              // Open the body for THIS chain immediately, same as tapping the
              // card's own "3D pad map" button — otherwise picking a later
              // match just adds another card and the 3D view (if already
              // open from the first match) keeps showing the old one.
              _openPadMap(r.payload);
            },
          ),
        _ChipAction(
            Icons.autorenew_rounded, 'Prep a user instead', _onPerformance),
      ]);
      return;
    }

    if (reply.options.isNotEmpty) {
      // A MENU for the resolved role — the whole catalogue, unscored. Calling
      // these "closest matches" would be the bug e5ef4f6 fixed.
      // Only introduce the list if the service didn't already. Its own reply
      // ("I have 4 documented chains for Cricket · Fast Bowler … pick the one
      // you're working on") says this better and names the position, so adding
      // "Here are the chains I have." under it was two bubbles saying one
      // thing — and the vaguer one came second.
      if (reply.reply.trim().isEmpty) {
        final role = _perfRole ?? (reply.slots['role']?.toString() ?? '');
        await _ai(role.isEmpty
            ? 'Here are the chains I have.'
            : 'Here are the chains for $role.');
      }
      _showChips([
        for (final c in reply.options)
          _ChipAction(Icons.link_rounded, c.label, () {
            _me(c.label);
            _perfSubtype ??= c.subtype;
            _perfPads(c);
          }),
      ]);
      return;
    }

    if (reply.reply.trim().isEmpty && reply.needs.isEmpty) {
      await _ai('I don’t have a placement for that yet. Try naming the sport '
          'and position, or tap a suggestion.');
    }
    _showChips(_homeChips);
  }

  // ── Typed text → recovery-chat (the recovery engine, conversationally) ─────

  /// `POST recovery-chat/message`. The recovery twin of [_perfChat]:
  /// [_recoverySlots] is threaded back every turn (that's how the area sticks
  /// across messages) and the guided-assessment answers ride along as
  /// `redFlags`, which is what the engine's safety gate screens.
  ///
  /// The service phrases the whole answer — header, pad lines, thermal note,
  /// citation — so the reply is rendered verbatim rather than re-formatted
  /// here. [slotPatch] carries an exact value from a tapped chip, so a chip
  /// answer doesn't have to survive a second round of text parsing.
  Future<void> _recoveryChat(
    String text, {
    Map<String, dynamic> slotPatch = const {},
  }) async {
    setState(() {
      _typing = true;
      _chipsVisible = false;
    });
    _scrollToEnd();

    final RecoveryChatReply reply;
    try {
      reply = await ref.read(recoveryChatRemoteSourceProvider).message(
            message: text,
            sessionId: ref.read(performanceSessionIdProvider),
            slots: {..._recoverySlots, ...slotPatch},
            redFlags: _screenAnswers(),
          );
    } catch (e) {
      return _failStep('Couldn’t reach the recovery assistant',
          () => _recoveryChat(text, slotPatch: slotPatch), e);
    }
    if (!mounted) return;

    setState(() {
      _typing = false;
      if (reply.slots.isNotEmpty) _recoverySlots = reply.slots;
      if (reply.reply.trim().isNotEmpty) {
        _messages.add(_Msg(false, reply.reply.trim()));
      }
    });
    _scrollToEnd();

    // A gate block. Show what the service said and offer a way onward — never
    // pads, and never the "start a session" chip alongside it.
    if (reply.isRefusal) {
      if (reply.reply.trim().isEmpty) return _refusal(null);
      _showChips([
        _ChipAction(Icons.waves_rounded, 'Try another area', _askRegion),
        _ChipAction(Icons.home_rounded, 'Start over', _startOver),
      ]);
      return;
    }

    // One missing slot, asked once with chips (the service's own wording is
    // already in the bubble above).
    if (reply.options.isNotEmpty) {
      _showChips([
        for (final c in reply.options.take(12))
          _ChipAction(_areaIcon(c.label), c.label, () {
            _me(c.label);
            // Record the area the same way the chip flow does, so Start Session
            // and the AI report see it.
            if (c.region != null) _assessmentArea = c.label;
            _recoveryChat(c.label, slotPatch: c.slotPatch);
          }),
      ]);
      return;
    }

    if (reply.hasPlacement) {
      // The area the engine actually resolved — not the label that was typed.
      final region = reply.slots['region']?.toString();
      if (region != null && region.trim().isNotEmpty) {
        _assessmentArea = region.replaceAll('-', ' ');
        _recordAreaOfFocus();
      }
      _showChips([
        _ChipAction(Icons.play_arrow_rounded, 'Start session',
            () => context.go(RoutePaths.devices),
            hot: true),
        _ChipAction(Icons.waves_rounded, 'Another area', _askRegion),
      ]);
      return;
    }

    if (reply.reply.trim().isEmpty) {
      await _ai('I don’t have a recovery placement for that yet. Try naming the '
          'area and how it feels, or pick an area below.');
    }
    _showChips([
      _ChipAction(Icons.waves_rounded, 'Pick an area', _askGoal),
      _ChipAction(Icons.bolt_rounded, 'Performance instead', _onPerformance),
    ]);
  }

  /// Adopts whatever the service resolved so a later chain tap can call
  /// `/chain` with the right discipline and role.
  void _adoptSlots(Map<String, dynamic> slots) {
    final discipline = slots['discipline']?.toString();
    final role = slots['role']?.toString();
    final subtype = slots['subtype']?.toString();
    if (discipline != null && discipline.trim().isNotEmpty) {
      _perfDiscipline = discipline;
      _perfDisciplineLabel =
          slots['display_name']?.toString() ?? _perfDisciplineLabel;
    }
    if (role != null && role.trim().isNotEmpty) _perfRole = role;
    if (subtype != null && subtype.trim().isNotEmpty && subtype != 'null') {
      _perfSubtype = subtype;
    }
  }

  /// What the practitioner has already told the app — the guided-assessment
  /// areas plus this conversation's answers. `{}` when nothing was collected.
  Map<String, dynamic> _screenAnswers() {
    final areas = ref.read(guidedAssessmentProvider).discomfortAreas;
    return {
      if (_answers.isNotEmpty) ..._answers,
      if (_assessmentArea != null) 'area': _assessmentArea,
      if (areas.isNotEmpty)
        'discomfortAreas': [
          for (final a in areas)
            {
              'bodyPart': a.bodyPart,
              'side': a.side.value,
              'discomfort': a.discomfortBefore,
            }
        ],
    };
  }

  /// `low-back` / `medial` → `Low back` / `Medial`. The engine's ids are the
  /// contract and the labels are for reading, so they are derived here and the
  /// id is never reconstructed back out of a label.
  static String _titleCase(String key) {
    final s = key.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (s.isEmpty) return '';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  /// Aspect labels in the words a client would use, not the enum.
  static String _aspectLabel(String aspect) {
    const labels = {
      'anterior': 'Front',
      'posterior': 'Back',
      'medial': 'Inner',
      'lateral': 'Outer',
      'palmar': 'Palm',
      'plantar': 'Sole',
      'dorsal': 'Top / back of hand',
      'superior': 'Upper',
      'inferior': 'Lower',
    };
    return labels[aspect.toLowerCase()] ?? _titleCase(aspect);
  }

  static IconData _goalIcon(RecoveryGoal goal) {
    switch (goal.value) {
      case 'range_of_motion':
        return Icons.open_in_full_rounded;
      case 'performance_recovery':
        return Icons.fitness_center_rounded;
      case 'lymphatic_activation':
        return Icons.water_drop_outlined;
      default:
        return Icons.healing_outlined;
    }
  }

  static IconData _sideIcon(String side) {
    switch (side.toLowerCase()) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
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
                    onTap: _startOver,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                // KEYS MATTER HERE. Messages are only ever appended, so an index
                // key is stable for every existing entry. Without keys, Flutter
                // matches these children positionally: when the typing bubble is
                // removed and a real bubble is appended in the same frame, every
                // widget after that point shifts by one and gets remounted —
                // which is the repaint flash that shows on send. The trailing
                // typing row and chip row carry their own const keys so they can
                // never be confused with a message bubble.
                children: [
                  for (var i = 0; i < _messages.length; i++)
                    if (_messages[i].placement != null)
                      PlacementCard(
                        key: ValueKey('msg-$i'),
                        payload: _messages[i].placement!,
                        onOpen3D: () => _openPadMap(_messages[i].placement!),
                        onGoToSession: () => goToSessionFromPlacement(
                          context,
                          ref,
                          payload: _messages[i].placement!,
                          client: _perfClient,
                          clientName: _perfWho,
                        ),
                      )
                    else
                      _Bubble(
                        key: ValueKey('msg-$i'),
                        palette: p,
                        msg: _messages[i],
                      ),
                  if (_typing)
                    _TypingBubble(key: const ValueKey('typing'), palette: p),
                  if (_chipsVisible && _chips.isNotEmpty)
                    Padding(
                      key: const ValueKey('chips'),
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
  const _Bubble({super.key, required this.palette, required this.msg});

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
  const _TypingBubble({super.key, required this.palette});

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
              // A Wrap hands each child the row's full width as its MAXIMUM, so
              // a label wider than that overflows unless the text is allowed to
              // give way. Short chips still size to their content (the Row is
              // still mainAxisSize.min); only an over-long one wraps, and two
              // lines is the ceiling so a chip can't grow without bound.
              // Labels here run long by design — a chain list that spans roles
              // has to say "Cricket · Fast Bowler — Lumbar extension-lateral
              // chain", because the bare chain name repeats across roles.
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hot ? p.copperInk : p.ink,
                    height: 1.25,
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

/// The searchable discipline picker — the spec's `allSportsSheet()`: a search
/// field over the full catalogue so a long list stays usable when chips don't.
class _DisciplineSheet extends StatefulWidget {
  final List<Discipline> disciplines;
  final ValueChanged<Discipline> onPick;

  const _DisciplineSheet({required this.disciplines, required this.onPick});

  @override
  State<_DisciplineSheet> createState() => _DisciplineSheetState();
}

class _DisciplineSheetState extends State<_DisciplineSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.disciplines
        : widget.disciplines
            .where((d) => d.label.toLowerCase().contains(q))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'All ${widget.disciplines.length} disciplines',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search disciplines…',
                hintStyle: TextStyle(color: p.ink3),
                prefixIcon: Icon(Icons.search_rounded, color: p.ink3, size: 18),
                filled: true,
                fillColor: p.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: p.line, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: p.line, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: p.copper, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'No match — new disciplines appear here as their pad '
                        'protocols land.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: p.divider,
                      ),
                      itemBuilder: (_, i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          list[i].label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                        trailing:
                            Icon(Icons.chevron_right_rounded, color: p.ink3),
                        onTap: () => widget.onPick(list[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
