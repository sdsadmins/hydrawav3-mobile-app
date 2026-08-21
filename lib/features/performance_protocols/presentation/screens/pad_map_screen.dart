import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../pad_placement/domain/anatomy_scene_marker.dart';
import '../../../pad_placement/domain/pad_marker_mapper.dart';
import '../../../pad_placement/domain/recovery_engine_models.dart';
import '../../../pad_placement/domain/set_colors.dart';
import '../../../pad_placement/presentation/screens/anatomy_scene_fullscreen_screen.dart';
import '../../../pad_placement/presentation/widgets/anatomy_scene_flag.dart';
import '../../../pad_placement/presentation/widgets/anatomy_scene_view.dart';
import '../../../pad_placement/presentation/widgets/pad_anatomy_view.dart';
import '../../domain/performance_models.dart';
import '../widgets/pad_geometry_diagram.dart';
import 'go_to_session.dart';

// The set palette now lives in `pad_placement/domain/set_colors.dart` — the same
// standalone-module shape the web uses — so the recovery pad screen can paint
// its sets from it too. Re-exported here because callers already import it from
// this screen.
export '../../../pad_placement/domain/set_colors.dart' show kAnatomySetColors;

/// The pad-map screen — a port of the UI spec's `scr-padmap` (`renderPadMap()`
/// in `hydrawav3-ui-handoff/app.js`), with the Z-Anatomy viewer as the body
/// stage instead of the spec's flat SVG figure (Layer Integration Plan §2.2 G:
/// "full-bleed Z-Anatomy viewer … skinned with our chrome").
///
/// Order, top to bottom, is the spec's: back bar → head → focus chips → body
/// stage → set legend → per-set notes → Sun/Moon guide → Back / Go to Session.
class PadMapScreen extends ConsumerStatefulWidget {
  final PadSetPayload payload;

  /// The client this placement is for, when one was picked ("Guest" otherwise).
  final String? clientName;

  /// The head line. Recovery resolves to the SAME pad shape — a Sun/Moon pair
  /// per set, anchored to a landmark — so it renders through this screen too and
  /// only needs to be named correctly.
  final String title;

  /// Whether "Go to Session" should pre-load the performance stack. Off for a
  /// recovery placement: nothing about it asked for "Performance Activation",
  /// and announcing a protocol that was never chosen is worse than leaving the
  /// practitioner to pick one.
  final bool preloadProtocol;

  const PadMapScreen({
    super.key,
    required this.payload,
    this.clientName,
    this.title = 'Performance Placement',
    this.preloadProtocol = true,
  });

  @override
  ConsumerState<PadMapScreen> createState() => _PadMapScreenState();
}

class _PadMapScreenState extends ConsumerState<PadMapScreen> {
  static const _sunLegend = Color(0xFFE11D48);
  static const _moonLegend = Color(0xFF2563EB);

  // Both controllers exist because `kUseAnatomyScenePerformance` decides which
  // stage is built; the zoom cluster dispatches to whichever is live.
  final _anatomy = AnatomySceneController();
  final _legacyAnatomy = PadAnatomyController();
  late final PadPlacementViewData _data;

  /// Everything the recovery engine returned BEYOND the pads — driver, thermal,
  /// clinical intent, reassessment, disclaimers. Null for a performance
  /// placement, which authors none of it.
  ///
  /// Read back out of `payload.raw`, which is the whole `/recovery-engine-v3/resolve`
  /// envelope, so no call site had to change to start showing it.
  late final RecoveryPlacement? _recovery;

  /// null = the spec's "All areas" chip.
  int? _focusSet;

  /// Sets the engine authored but whose role doesn't apply to this case at all.
  int get _withheldCount => widget.payload.withheldSets.length;

  /// Sets the engine authored WITH pads, sequenced into a later session.
  int get _deferredCount => widget.payload.deferredSets.length;
  late String _view;
  bool _showLabels = true;
  bool _showMuscles = false;

  // ---- web-parity view options (PerformanceProtocolStoreFlow.jsx) ------------------------------
  // The same four options the web exposes above its AnatomyScene, with the same semantics, so one
  // chain reads identically in both clients.

  /// Muscle Mode: the target muscle IS the indicator — painted red (Sun) / blue (Moon) with NO disc
  /// and NO badge on the body — and the un-targeted skin goes solid.
  /// `padStyle="muscle"` + `transparentBody={!muscleMode}`. Defaults OFF (mobile-only choice, not
  /// web parity): the body opens transparent/x-ray so the pads read against the skeleton first.
  bool _muscleMode = false;

  /// Off = the focused set only. On = the whole chain at once.
  bool _showAllSets = false;

  /// Flip the whole chain to the opposite side. Disabled under [_bilateral], which shows both anyway.
  bool _mirrored = false;

  /// Draw the chain on BOTH sides at once. Wins over [_mirrored] rather than compounding with it —
  /// mirroring something already drawn on both sides is a no-op, so it is ignored, not half-applied.
  bool _bilateral = false;

  /// What the mirror toggle reads. Bilateral overrides it, so say BOTH rather than naming a side that
  /// is not what is on screen.
  String get _mirrorLabel =>
      _bilateral ? 'BOTH' : (_mirrored ? 'LEFT' : 'RIGHT');

  /// One source of truth for which pads are visible, so the stage, legend and notes cannot disagree.
  int? get _visibleSetIndex => _showAllSets ? null : _focusSet;

  /// `setIndex:role` keys the viewer reported it could not place.
  Set<String> _unmappedByViewer = const {};

  @override
  void initState() {
    super.initState();
    _data = PadPlacementViewData.from(widget.payload);
    _recovery = RecoveryPlacement.fromPayload(widget.payload);
    _view = _data.viewFor(null);
    // Seed the toggle from the engine's own request rather than leaving it off
    // while the stage draws bilaterally anyway (see `markers()`'s `padBoth`) —
    // a "Both" pick at intake should read as BOTH here without the user having
    // to separately find and tap this switch.
    _bilateral = _data.pads.any((p) => p.pad.renderBothSides);
  }

  /// The set colour for chips, legend swatches and set-note badges.
  ///
  /// Follows the 3D stage: the AnatomyScene viewer paints per-set badges and
  /// arcs from the Okabe-Ito palette, so the chrome has to match it. The old
  /// three-grey `RefPalette` triple stays in use when the flag is off.
  Color _setColor(RefPalette p, int i) => kUseAnatomyScenePerformance
      ? kAnatomySetColors[i % kAnatomySetColors.length]
      : [p.set1, p.set2, p.set3][i % 3];

  /// Focusing a set jumps to the view that set sits on — `focusPadSet()` in the
  /// spec does the same, otherwise you focus a posterior set and see an empty
  /// front view.
  void _focus(int? index) {
    setState(() {
      _focusSet = index;
      _view = _data.viewFor(index);
    });
  }

  /// Which markers the viewer should treat as ACTIVE — and therefore paint.
  ///
  /// `activeMarkers` is not just "what is selected": in the viewer's badge path
  /// it is the whole basis of the colouring. `applyHighlights` builds its id set
  /// from this list, hides every `muscle-highlight` whose id isn't in it, and
  /// hands the same list to `setActiveAnatomyMeshHighlight` — which is what
  /// applies the per-set colour under `colorBySet`.
  ///
  /// This used to send an EMPTY list whenever no single set was focused, which
  /// is exactly the "Show all sets" case (and the "All areas" chip). Empty meant
  /// no ids matched, so every highlight was hidden and nothing was coloured:
  /// turning on "Show all sets" showed all the sets and removed all the colour
  /// that told them apart. Showing every set means every marker is active —
  /// nothing is dimmed either, since `dimUnselected` is already off.
  ///
  /// The one case that still needs the empty list is the flat "Muscles" overlay:
  /// the viewer only falls through to `applyFlatHighlight()` when there is no
  /// per-marker selection to express, so a non-empty list would suppress it.
  List<Map<String, dynamic>> _activeMarkers(
      List<Map<String, dynamic>> markers) {
    if (_visibleSetIndex == null && _highlightMuscles.isNotEmpty) {
      return const [];
    }
    return markers;
  }

  bool _isUnmapped(ResolvedPad pad) =>
      pad.isUnmapped ||
      _unmappedByViewer.contains('${pad.setIndex}:${pad.role}');

  List<String> get _highlightMuscles {
    // Muscle Mode already colours every target muscle by role, from the markers themselves. Handing
    // the viewer a second flat list on top would repaint them one uniform tint and destroy the
    // Sun/Moon distinction — which in that mode is the ONLY thing marking the placement.
    if (_muscleMode) return const [];
    if (!_showMuscles) return const [];
    return _data
        .padsFor(_visibleSetIndex, includeDeferred: _showAllSets)
        .expand((p) => p.pad.targetMuscles)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final sets = _data.sets;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HwSpace.s4),
              child: HwBackBar(
                title: 'Pad placements',
                onBack: () => Navigator.of(context).maybePop(),
                trailing: HwIconButton(
                  asset: HwIcons.star,
                  onTap: _savePreset,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    HwSpace.s4, 0, HwSpace.s4, HwSpace.s5),
                children: [
                  _head(p, sets.length),
                  const SizedBox(height: HwSpace.s3),
                  // A composed point or a rerouted pathway changes what the
                  // whole placement MEANS, so they sit above it, not below.
                  if (_recovery case final r?) ..._recoveryNotices(p, r),
                  const HwEyebrow('Placement areas · tap to focus one'),
                  _focusChips(p, sets),
                  const SizedBox(height: HwSpace.s3),
                  _bodyStage(p),
                  // Directly under the stage, as the web places them — the options describe what the
                  // stage is showing, so putting them anywhere else breaks the association.
                  _viewOptions(p),
                  const SizedBox(height: HwSpace.s2),
                  _legend(p, sets),
                  const SizedBox(height: HwSpace.s3),
                  for (final set in _shownSets(sets)) _setNote(p, set),
                  if (widget.payload.deferredSets.isNotEmpty) ...[
                    HwEyebrow(
                        'Sequence into later sessions · '
                        '${widget.payload.deferredSets.length} set${widget.payload.deferredSets.length == 1 ? '' : 's'}'),
                    const SizedBox(height: HwSpace.s2),
                    for (final set in widget.payload.deferredSets)
                      _deferredNote(p, set),
                  ],
                  for (final set in widget.payload.withheldSets)
                    _withheldNote(p, set),
                  _sessionGuidance(p),
                  // What this chain is FOR, straight from the protocol record —
                  // web parity with the "Common injuries" and "Performance
                  // improvements" blocks. Both were already on the payload and
                  // simply never rendered here.
                  _chainOutcomes(p),
                  _padGuide(p),
                  // Driver → thermal → intent → reassessment → disclaimers,
                  // in the web panel's order.
                  if (_recovery case final r?) ..._recoveryDetail(p, r),
                  if (_data.hasUnmapped || _unmappedByViewer.isNotEmpty)
                    _unmappedNotice(p),
                  const SizedBox(height: HwSpace.s3),
                  Row(
                    children: [
                      Expanded(
                        child: HwButton(
                          label: 'Back',
                          filled: false,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: HwSpace.s3),
                      Expanded(
                        child: HwButton(
                          label: 'Go to Session',
                          onTap: () => goToSessionFromPlacement(
                            context,
                            ref,
                            payload: widget.payload,
                            clientName: widget.clientName,
                            preloadProtocol: widget.preloadProtocol,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Goes through [_visibleSetIndex], not [_focusSet], so "Show all sets" widens the written notes in
  /// step with the model. Notes describing a set that is not drawn is the mismatch this avoids.
  List<PadSet> _shownSets(List<PadSet> sets) {
    final index = _visibleSetIndex;
    if (index == null) {
      return _showAllSets
          ? [...sets, ...widget.payload.deferredSets]
          : sets;
    }
    return index >= 0 && index < sets.length ? [sets[index]] : sets;
  }

  // ── head ───────────────────────────────────────────────────────────────────

  Widget _head(RefPalette p, int count) {
    final chain = widget.payload.chain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            fontSize: HwType.xxl,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$count placement set${count == 1 ? '' : 's'}'
          // Web parity with "N set(s) of max M": say when the point authors more
          // than this session applies, so the count never reads as the whole
          // story — and say WHY separately for "later session" (role applies,
          // just not yet) vs "not applicable" (role doesn't apply to this case).
          '${_deferredCount == 0 ? '' : ' · $_deferredCount later session'}'
          '${_withheldCount == 0 ? '' : ' · $_withheldCount not applicable'}'
          '${widget.payload.contextLine.isEmpty ? '' : ' · ${widget.payload.contextLine}'}',
          style: TextStyle(fontSize: HwType.cap, color: p.ink3),
        ),
        if (chain != null && chain.name.trim().isNotEmpty) ...[
          const SizedBox(height: HwSpace.s2),
          Text(
            chain.name,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          // The subline sits BELOW the chain name rather than beside it: it is
          // server copy of unbounded length, so sharing a row with the name left
          // both squeezed and overflowed the row on longer chains. On its own
          // line it gets the full width and may wrap to two.
          if (chain.subline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: HwPill(chain.subline, maxLines: 2),
            ),
          ],
        ],
      ],
    );
  }

  // ── focus chips ────────────────────────────────────────────────────────────

  Widget _focusChips(RefPalette p, List<PadSet> sets) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          HwChip(
            label: sets.length > 1 ? 'All areas' : 'All',
            selected: _focusSet == null,
            onTap: () => _focus(null),
          ),
          for (final set in sets) ...[
            const SizedBox(width: HwSpace.s2),
            _setChip(p, widget.payload.markerIndexOf(set), set),
          ],
          // Sets authored WITH pads but sequenced into a later session — the
          // role applies, it just isn't applied yet. Sits before the
          // not-applicable chips, matching the order they're explained below.
          for (final set in widget.payload.deferredSets) ...[
            const SizedBox(width: HwSpace.s2),
            _deferredChip(p, set),
          ],
          // Sets the engine authored but whose role doesn't apply to this case
          // at all. They sit here, after the ones that apply, so "3 sets
          // authored, 2 applied, 1 not applicable" is visible at the control
          // where sets are picked rather than only in the guidance copy.
          for (final set in widget.payload.withheldSets) ...[
            const SizedBox(width: HwSpace.s2),
            _withheldChip(p, set),
          ],
        ],
      ),
    );
  }

  /// A deferred set has real pads, just not drawn this session. Tapping it
  /// focuses the 3D view on it too — same as an applied set's chip
  /// (`_focus`) — so the practitioner can actually SEE what's next in the
  /// chain, not just read its cue text.
  Widget _deferredChip(RefPalette p, PadSet set) {
    return HwPress(
      scale: 0.92,
      onTap: () {
        _focus(widget.payload.markerIndexOf(set));
        _explainDeferred(set);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.md),
          border: Border.all(color: p.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: p.ink3),
            const SizedBox(width: HwSpace.s2),
            Text(
              'Set ${widget.payload.displayIndexOf(set)} · later session',
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w600,
                color: p.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A withheld set has no pads to focus, so the chip states that instead of
  /// pretending to be a filter. Tapping it explains why the set isn't applied.
  Widget _withheldChip(RefPalette p, PadSet set) {
    return HwPress(
      scale: 0.92,
      onTap: () => _explainWithheld(set),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.md),
          border: Border.all(color: p.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 13, color: p.ink3),
            const SizedBox(width: HwSpace.s2),
            Text(
              'Set ${widget.payload.displayIndexOf(set)} · not applicable',
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w600,
                color: p.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _explainWithheld(PadSet set) {
    final p = RefPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(HwSpace.s4, 0, HwSpace.s4, HwSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set ${widget.payload.displayIndexOf(set)}'
                '${set.role.trim().isEmpty ? '' : ' · ${set.role}'}',
                style: TextStyle(
                  fontSize: HwType.lg,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Authored on this point, doesn’t apply to this case',
                style: TextStyle(fontSize: HwType.cap, color: p.ink3),
              ),
              const SizedBox(height: HwSpace.s3),
              Text(
                set.withheldReason.trim().isEmpty
                    ? 'The engine held this set back for this presentation.'
                    : set.withheldReason,
                style: TextStyle(
                  fontSize: HwType.sm,
                  height: 1.5,
                  color: p.ink2,
                ),
              ),
              const SizedBox(height: HwSpace.s4),
            ],
          ),
        ),
      ),
    );
  }

  /// A deferred set's own Sun/Moon, read straight off [PadSet] rather than
  /// through [_data.padOf] — `_data.sets` is `appliedSets` only, and this
  /// text should read the same whether or not the 3D resolver could place it
  /// (`_data.deferredPads` backs the 3D focus triggered alongside this sheet,
  /// but the cue text itself doesn't depend on that resolution succeeding).
  /// [Pad.cue] is used as-is: it's already "everything the practitioner needs
  /// if 3D can't place it".
  void _explainDeferred(PadSet set) {
    final p = RefPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(HwSpace.s4, 0, HwSpace.s4, HwSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.payload.titleOf(set),
                style: TextStyle(
                  fontSize: HwType.lg,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Authored with pads, sequenced for a later session'
                '${set.role.trim().isEmpty ? '' : ' · ${set.role}'}',
                style: TextStyle(fontSize: HwType.cap, color: p.ink3),
              ),
              const SizedBox(height: HwSpace.s3),
              if (set.sun != null)
                Text('Sun — ${set.sun!.cue}',
                    style: TextStyle(
                        fontSize: HwType.sm, height: 1.5, color: p.ink2)),
              if (set.sun != null && set.moon != null)
                const SizedBox(height: HwSpace.s1),
              if (set.moon != null)
                Text('Moon — ${set.moon!.cue}',
                    style: TextStyle(
                        fontSize: HwType.sm, height: 1.5, color: p.ink2)),
              const SizedBox(height: HwSpace.s4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _setChip(RefPalette p, int i, PadSet set) {
    final selected = _focusSet == i;
    // "Set 1" / "Set 2" LEADS, as it does everywhere else this set is named —
    // the legend, the set-note badge and the 3D stage's own badges all key off
    // the set number, and the web says "Set N" too (`RecoveryResultPanel.jsx`
    // and the performance set chip, which reads "N · role"). This chip used to
    // show ONLY the placement label when there was one, so the one control for
    // picking a set was the one place its number never appeared.
    //
    // The role (performance) or placement label (recovery) rides along as a
    // quieter suffix so the chip still says WHAT the set is.
    final suffix = set.role.trim().isNotEmpty
        ? set.role.trim()
        : set.placementLabel.trim();
    return HwPress(
      scale: 0.92,
      onTap: () => _focus(i),
      child: AnimatedContainer(
        duration: HwMotion.t2,
        curve: HwMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? p.tanSoft : p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.md),
          border: Border.all(
            color: selected ? p.copper : p.line,
            width: 1.5,
          ),
          // No shadow: these sit in a horizontally scrolling strip, where a drop
          // shadow on each chip reads as visual noise and clips against the
          // row's bounds. Selection is carried by the fill and the copper border.
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _setColor(p, i),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: HwSpace.s2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Set ${widget.payload.displayIndexOf(set)}',
                    style: TextStyle(
                      fontSize: HwType.sm,
                      fontWeight: FontWeight.w700,
                      color: selected ? p.copperInk : p.ink,
                    ),
                  ),
                  if (suffix.isNotEmpty)
                    TextSpan(
                      text: ' · $suffix',
                      style: TextStyle(
                        fontSize: HwType.sm,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? p.copperInk.withValues(alpha: 0.75)
                            : p.ink3,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── body stage ─────────────────────────────────────────────────────────────

  Widget _bodyStage(RefPalette p) {
    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(HwRadius.xl),
        border: Border.all(color: p.cardline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _stage()),
          // No Front/Back pill and no rotate button any more: the stage now
          // claims every drag that starts on it, so the model is turned by
          // dragging it. A button that flips to a fixed view — and a pill
          // naming that view — both stop being true the moment you rotate.
          Positioned(
            top: HwSpace.s3,
            left: HwSpace.s3,
            child: _sunMoonLegend(p),
          ),
          Positioned(
            top: HwSpace.s3,
            right: HwSpace.s3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _stageToggle(
                  p,
                  label: _showLabels ? 'Labels on' : 'Labels off',
                  active: _showLabels,
                  onTap: () => setState(() => _showLabels = !_showLabels),
                ),
                const SizedBox(height: HwSpace.s2),
                _stageToggle(
                  p,
                  label: 'Muscles',
                  active: _showMuscles,
                  onTap: () => setState(() => _showMuscles = !_showMuscles),
                ),
                if (kUseAnatomyScenePerformance) ...[
                  const SizedBox(height: HwSpace.s2),
                  _expandButton(p),
                ],
              ],
            ),
          ),
          Positioned(
            bottom: HwSpace.s3,
            right: HwSpace.s3,
            child: Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(HwRadius.md),
                border: Border.all(color: p.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _zoomBtn(p, Icons.add, _zoomIn),
                  _zoomBtn(p, Icons.remove, _zoomOut),
                  _zoomBtn(p, Icons.refresh, _resetView, border: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sunMoonLegend(RefPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(HwRadius.md),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendToken(_sunLegend, '☀', 'Sun'),
          const SizedBox(width: 12),
          _legendToken(_moonLegend, '☾', 'Moon'),
        ],
      ),
    );
  }

  Widget _legendToken(Color color, String symbol, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Text(
            symbol,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  /// The 3D stage.
  ///
  /// The option mapping follows the web performance flow exactly:
  ///   • `padStyle: 'muscle'` ALWAYS — the target muscle IS the indicator, so
  ///     no pad and no badge are ever drawn on this stage. The Muscle Mode
  ///     toggle no longer switches styles; it only switches `transparentBody`
  ///     below, so switching it off still shows the same coloured muscle, just
  ///     through a see-through body instead of a solid one.
  ///   • `transparentBody: !muscleMode` — this is the web's actual pairing
  ///     (`transparentBody={!muscleMode}`). Muscle Mode reads as "solid body";
  ///     with it off you get the X-ray, which the older viewer could not do at
  ///     all because it shared one material across every mesh.
  ///   • `showSetLinks` is always on here: this is the surface where a chain of
  ///     sets has to read as a chain, and the labelled arc is what carries the
  ///     set identity.
  ///   • `colorBySet` is deliberately OFF. With it on, focusing a set repainted
  ///     the pads and muscles in that set's palette colour, so the same pad
  ///     changed colour depending on which set was selected and Sun/Moon stopped
  ///     being readable at a glance. Role colour (Sun red / Moon blue) is the
  ///     one thing on this model that must never move.
  /// The single source of truth for what the stage shows — markers, style and
  /// every view flag. Both [_stage] (inline) and [_openFullscreen] (edge to
  /// edge) build their `AnatomySceneView` from THIS, rather than each keeping
  /// its own copy of the same field list — two copies is exactly how they drifted
  /// before (the fullscreen one kept `padStyle: _muscleMode ? 'muscle' : 'badge'`
  /// after the inline stage moved to always-`'muscle'`, so expanding with Muscle
  /// Mode off silently swapped every pad from muscle-colour to badge style).
  /// Only `key`, `controller`, `backgroundCss` and the callbacks vary per call
  /// site — those stay as constructor arguments on top of this.
  ({
    List<Map<String, dynamic>> markers,
    List<String> setRoles,
    String padStyle,
    bool transparentBody,
    int? focusSetIndex,
    bool dimUnselected,
    List<Map<String, dynamic>> activeMarkers,
    List<String> highlightMuscles,
  }) _stageOptions() {
    final markers = _data.markers(
      focusSetIndex: _visibleSetIndex,
      mirrored: _mirrored,
      bilateral: _bilateral,
      includeDeferred: _showAllSets,
    );
    return (
      markers: markers,
      setRoles: _data.sets.map((s) => s.role).toList(),
      // Always the muscle-coloured style — the Muscle Mode toggle only flips
      // transparentBody below now, not which style draws.
      padStyle: 'muscle',
      transparentBody: !_muscleMode,
      focusSetIndex: _visibleSetIndex,
      dimUnselected: !_showAllSets,
      activeMarkers: _activeMarkers(markers),
      highlightMuscles: _highlightMuscles,
    );
  }

  Widget _stage() {
    final p = RefPalette.of(context);

    void handleUnmapped(Set<String> keys) {
      if (!mounted || keys.isEmpty) return;
      setState(() => _unmappedByViewer = keys);
    }

    if (!kUseAnatomyScenePerformance) {
      final markers = _data.markers(
        focusSetIndex: _visibleSetIndex,
        mirrored: _mirrored,
        bilateral: _bilateral,
        includeDeferred: _showAllSets,
      );
      return PadAnatomyView(
        markers: markers,
        view: _view,
        showLabels: _showLabels,
        padStyle: _muscleMode ? 'muscle' : 'dot',
        muscleMode: _muscleMode,
        highlightMuscles: _highlightMuscles,
        controller: _legacyAnatomy,
        onUnmapped: handleUnmapped,
      );
    }

    final o = _stageOptions();
    return AnatomySceneView(
      markers: o.markers,
      source: MarkerSource.performance,
      // Drives the "Set N · Role" text on each arc.
      setRoles: o.setRoles,
      view: _view,
      showLabels: _showLabels,
      padStyle: o.padStyle,
      transparentBody: o.transparentBody,
      colorBySet: false,
      showSetLinks: true,
      focusSetIndex: o.focusSetIndex,
      dimUnselected: o.dimUnselected,
      activeMarkers: o.activeMarkers,
      highlightMuscles: o.highlightMuscles,
      // Matching the card behind it rather than staying transparent lets the
      // WebView composite opaquely, which is a measurable win while orbiting.
      backgroundCss: _cssOf(p.card2),
      controller: _anatomy,
      onUnmapped: handleUnmapped,
      // Tapping a pad focuses its set, which is the same thing the chips above
      // the stage do — so the two controls cannot disagree.
      onRegionPick: (marker) {
        if (!mounted) return;
        final index = marker?['setIndex'];
        if (index is int) _focus(index);
      },
    );
  }

  /// Opens the stage edge to edge, carrying the current view options across so
  /// it shows exactly what the small stage was showing.
  ///
  /// This matters more than it looks: the inline stage now claims every drag
  /// that starts on it (otherwise there is no vertical rotation inside a
  /// scrolling page), so full screen is where inspecting a placement properly
  /// belongs.
  Widget _expandButton(RefPalette p) {
    return HwPress(
      onTap: _openFullscreen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(HwRadius.xs),
          border: Border.all(color: p.line),
        ),
        child: Icon(Icons.open_in_full, size: 14, color: p.ink3),
      ),
    );
  }

  void _openFullscreen() {
    // Built from the exact same [_stageOptions] the inline stage just rendered
    // from — not a second, hand-copied field list — so expanding can never show
    // anything the collapsed stage didn't already show.
    final o = _stageOptions();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnatomySceneFullscreenScreen(
          markers: o.markers,
          source: MarkerSource.performance,
          setRoles: o.setRoles,
          title: 'Pad placements',
          initialView: _view,
          initialShowLabels: _showLabels,
          padStyle: o.padStyle,
          transparentBody: o.transparentBody,
          colorBySet: false,
          showSetLinks: true,
          focusSetIndex: o.focusSetIndex,
          dimUnselected: o.dimUnselected,
          activeMarkers: o.activeMarkers,
          highlightMuscles: o.highlightMuscles,
        ),
      ),
    );
  }

  /// `#rrggbb` for the viewer, which takes a CSS colour. Alpha is dropped —
  /// the stage sits on an opaque card, so there is nothing behind it to blend
  /// with anyway.
  static String _cssOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // The zoom cluster drives whichever stage the flag actually built.
  void _zoomIn() =>
      kUseAnatomyScenePerformance ? _anatomy.zoomIn() : _legacyAnatomy.zoomIn();
  void _zoomOut() => kUseAnatomyScenePerformance
      ? _anatomy.zoomOut()
      : _legacyAnatomy.zoomOut();
  void _resetView() =>
      kUseAnatomyScenePerformance ? _anatomy.reset() : _legacyAnatomy.reset();

  /// The web's four view options, in the web's order and with the web's wording.
  ///
  /// Mirror is DISABLED while Bilateral is on rather than silently doing nothing: bilateral already
  /// draws both sides, so mirroring it would be a no-op, and a control that looks live but changes
  /// nothing is worse than one that plainly says it does not apply.
  Widget _viewOptions(RefPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: HwSpace.s3),
      child: Wrap(
        spacing: HwSpace.s2,
        runSpacing: HwSpace.s2,
        children: [
          _optionChip(
            p,
            label: 'Muscle Mode (solid body)',
            active: _muscleMode,
            onTap: () => setState(() => _muscleMode = !_muscleMode),
          ),
          _optionChip(
            p,
            label: 'Show all sets',
            active: _showAllSets,
            onTap: () => setState(() => _showAllSets = !_showAllSets),
          ),
          _optionChip(
            p,
            label: 'Mirror — showing $_mirrorLabel',
            active: _mirrored && !_bilateral,
            enabled: !_bilateral,
            onTap: () => setState(() => _mirrored = !_mirrored),
          ),
          _optionChip(
            p,
            label: 'Bilateral — both sides at once',
            active: _bilateral,
            onTap: () => setState(() => _bilateral = !_bilateral),
          ),
        ],
      ),
    );
  }

  Widget _optionChip(
    RefPalette p, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? p.copper : p.card,
        borderRadius: BorderRadius.circular(HwRadius.xs),
        border: Border.all(color: active ? p.copper : p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 13,
            color: active ? Colors.white : p.ink3,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              color: active ? Colors.white : p.ink3,
            ),
          ),
        ],
      ),
    );
    if (!enabled) return Opacity(opacity: 0.45, child: chip);
    return HwPress(onTap: onTap, child: chip);
  }

  Widget _stageToggle(
    RefPalette p, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? p.copper : p.card,
          borderRadius: BorderRadius.circular(HwRadius.xs),
          border: Border.all(color: active ? p.copper : p.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
            color: active ? Colors.white : p.ink3,
          ),
        ),
      ),
    );
  }

  Widget _zoomBtn(RefPalette p, IconData icon, VoidCallback onTap,
      {bool border = true}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          border: border ? Border(right: BorderSide(color: p.line)) : null,
        ),
        child: Icon(icon, size: 15, color: p.ink3),
      ),
    );
  }

  // ── legend + per-set notes ─────────────────────────────────────────────────

  Widget _legend(RefPalette p, List<PadSet> sets) {
    return Wrap(
      spacing: HwSpace.s4,
      runSpacing: HwSpace.s1,
      children: [
        for (final set in sets)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _setColor(p, widget.payload.markerIndexOf(set)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: HwSpace.s1 + 2),
              Text(
                'Set ${widget.payload.displayIndexOf(set)}',
                style: TextStyle(
                  fontSize: HwType.cap,
                  fontWeight: FontWeight.w700,
                  color: p.ink2,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _setNote(RefPalette p, PadSet set) {
    final i = widget.payload.markerIndexOf(set);
    final sun = _data.padOf(i, 'sun');
    final moon = _data.padOf(i, 'moon');
    final offView = [sun, moon]
        .whereType<ResolvedPad>()
        .where((r) => r.view != _view && r.view != 'side')
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.payload.titleOf(set),
                              style: TextStyle(
                                fontSize: HwType.base,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                          ),
                          if (set.padGeometry.trim().isNotEmpty) ...[
                            const SizedBox(width: HwSpace.s2),
                            _geometryChip(p, set.padGeometry),
                          ],
                        ],
                      ),
                      if (set.role.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _roleLabel(set.role),
                          style: TextStyle(
                            fontSize: HwType.eyebrow,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: p.copperInk,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (offView.isNotEmpty) ...[
              const SizedBox(height: HwSpace.s2),
              Text(
                'On ${offView.first.view} — rotate to see',
                style: TextStyle(
                  fontSize: HwType.cap,
                  fontWeight: FontWeight.w500,
                  color: p.ink3,
                ),
              ),
            ],
            const SizedBox(height: HwSpace.s2),
            if (sun != null) _padLine(p, sun),
            if (moon != null) _padLine(p, moon),
            if (PadGeometryInfo.of(set.padGeometry) case final geometry?) ...[
              // The diagram sits WITH its sentence, not up beside the chip: the
              // picture says how the pair relates and the sentence says why, and
              // splitting them left the chip's one-word "reads" carrying the
              // whole idea on its own.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PadGeometryDiagram(
                    geometry: set.padGeometry,
                    padColor: p.copperInk,
                    bodyColor: p.ink3,
                    linkColor: p.copper,
                    captionColor: p.ink3,
                    width: 72,
                  ),
                  const SizedBox(width: HwSpace.s2),
                  Expanded(
                    child: Text(
                      geometry.intent,
                      style: TextStyle(
                        fontSize: HwType.eyebrow,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: p.ink3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HwSpace.s1),
            ],
            if (set.clinicalReasoning.trim().isNotEmpty) ...[
              const SizedBox(height: HwSpace.s2),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: HwSpace.s2),
                  title: Text(
                    'Why this placement',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        set.clinicalReasoning,
                        style: TextStyle(
                          fontSize: HwType.cap,
                          height: 1.5,
                          color: p.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Recovery's `pad_geometry` — HOW the Sun/Moon pair sits relative to each
  /// other, which the two pad lines alone never say. Web parity: the
  /// `recovery-geometry-chip` in `RecoveryResultPanel.jsx` — label, with the
  /// one-word "reads" beneath it, and the full intent under the pad lines.
  Widget _geometryChip(RefPalette p, String key) {
    final info = PadGeometryInfo.of(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: p.infoSoft,
        borderRadius: BorderRadius.circular(HwRadius.xs),
        border: Border.all(color: p.info.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            info?.label ?? _humanizeKey(key),
            style: TextStyle(
              fontSize: HwType.eyebrow,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: p.info,
            ),
          ),
          if (info != null)
            Text(
              info.reads,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: p.info.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  static String _humanizeKey(String key) {
    final s = key.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (s.isEmpty) return '';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  Widget _padLine(RefPalette p, ResolvedPad resolved) {
    final isSun = resolved.role == 'sun';
    final pad = resolved.pad;
    final side = resolved.side == null
        ? ''
        : '${resolved.side![0].toUpperCase()}${resolved.side!.substring(1)} ';
    final detail = [
      pad.plane,
      pad.positionAlongMuscle,
      pad.landmarkAnchor,
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: isSun ? p.sunGrad : p.moonGrad,
              borderRadius: BorderRadius.circular(HwRadius.xs),
            ),
            child: Text(
              isSun ? '☀' : '☾',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: isSun ? 'Sun' : 'Moon',
                        style: TextStyle(
                          fontSize: HwType.cap,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                      TextSpan(
                        text: ' → $side${pad.padLabel}',
                        style: TextStyle(
                          fontSize: HwType.cap,
                          color: p.ink2,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: HwType.eyebrow,
                      color: p.ink3,
                      height: 1.5,
                    ),
                  ),
                if (pad.proxyFor != null)
                  Text(
                    'Proxy for ${pad.proxyFor}',
                    style: TextStyle(
                      fontSize: HwType.eyebrow,
                      fontStyle: FontStyle.italic,
                      color: p.ink3,
                    ),
                  ),
                if (_isUnmapped(resolved))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.midSoft,
                        borderRadius: BorderRadius.circular(HwRadius.xs),
                      ),
                      child: Text(
                        'Placement not mapped — follow the written cue',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: p.mid,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'generator':
        return 'GENERATOR · WHERE THE MOVEMENT STARTS';
      case 'transfer':
        return 'TRANSFER · CARRIES THE LOAD THROUGH';
      case 'terminus':
        return 'TERMINUS · WHERE IT LANDS';
      default:
        return role.toUpperCase();
    }
  }

  /// The card for a set the engine authored but did not apply. Deliberately
  /// muted and pad-less — it is here so the practitioner can see the set exists
  /// and what would bring it in, not so it can be run.
  /// A deferred set's card in the "Sequence into later sessions" list — full
  /// Sun/Moon placement, same as an applied set's [_setNote], but tagged
  /// LATER SESSION instead of drawn on the model. Reads pads straight off
  /// [PadSet] (see [_explainDeferred]) rather than through [_data].
  Widget _deferredNote(RefPalette p, PadSet set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.chipBg,
                    borderRadius: BorderRadius.circular(HwRadius.xs),
                    border: Border.all(color: p.line, width: 1.5),
                  ),
                  child: Text(
                    '${set.setIndex}',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w800,
                      color: p.ink3,
                    ),
                  ),
                ),
                const SizedBox(width: HwSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.payload.titleOf(set),
                              style: TextStyle(
                                fontSize: HwType.base,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                          ),
                          if (set.padGeometry.trim().isNotEmpty) ...[
                            const SizedBox(width: HwSpace.s2),
                            _geometryChip(p, set.padGeometry),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (set.role.trim().isNotEmpty)
                            Expanded(
                              child: Text(
                                '${_roleLabel(set.role)}'
                                '${set.sessionPriority > 0 ? ' · priority ${set.sessionPriority}' : ''}',
                                style: TextStyle(
                                  fontSize: HwType.eyebrow,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                  color: p.copperInk,
                                ),
                              ),
                            ),
                          const SizedBox(width: HwSpace.s2),
                          const HwPill('later session'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: HwSpace.s2),
            if (set.sun != null)
              Text('☀ ${set.sun!.cue}',
                  style: TextStyle(
                      fontSize: HwType.cap, height: 1.5, color: p.ink2)),
            if (set.moon != null) ...[
              const SizedBox(height: 3),
              Text('☾ ${set.moon!.cue}',
                  style: TextStyle(
                      fontSize: HwType.cap, height: 1.5, color: p.ink2)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _withheldNote(RefPalette p, PadSet set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: Container(
        padding: const EdgeInsets.all(HwSpace.s3),
        decoration: BoxDecoration(
          color: p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.lg),
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.chipBg,
                    borderRadius: BorderRadius.circular(HwRadius.xs),
                    border: Border.all(color: p.line, width: 1.5),
                  ),
                  child: Text(
                    '${set.setIndex}',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w800,
                      color: p.ink3,
                    ),
                  ),
                ),
                const SizedBox(width: HwSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.payload.titleOf(set),
                        style: TextStyle(
                          fontSize: HwType.base,
                          fontWeight: FontWeight.w700,
                          color: p.ink2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'NOT APPLIED THIS SESSION'
                        '${set.role.trim().isEmpty ? '' : ' · ${set.role.toUpperCase()}'}',
                        style: TextStyle(
                          fontSize: HwType.eyebrow,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: p.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (set.withheldReason.trim().isNotEmpty) ...[
              const SizedBox(height: HwSpace.s2),
              Text(
                set.withheldReason,
                style: TextStyle(
                  fontSize: HwType.cap,
                  height: 1.5,
                  color: p.ink3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The engine's own words on how many sets to run this session and how to
  /// sequence the rest — web parity with `RecoveryResultPanel`'s guidance and
  /// `recovery-sequencing` lines. Rendered verbatim; the backend owns it.
  Widget _sessionGuidance(RefPalette p) {
    final guidance = widget.payload.guidance.trim();
    final sequencing = widget.payload.sequencingNote.trim();
    if (guidance.isEmpty && sequencing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HwEyebrow('This session'),
            const SizedBox(height: HwSpace.s2),
            if (guidance.isNotEmpty)
              Text(
                guidance,
                style: TextStyle(
                  fontSize: HwType.cap,
                  height: 1.5,
                  color: p.ink2,
                ),
              ),
            if (sequencing.isNotEmpty) ...[
              if (guidance.isNotEmpty) const SizedBox(height: HwSpace.s2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Sequencing: ',
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                    TextSpan(
                      text: sequencing,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        height: 1.5,
                        color: p.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Common injuries" and "Performance improvements" — what the selected chain
  /// is for, as the web renders them under the stage.
  ///
  /// Both lists are authored on the protocol record and already parsed into
  /// [ChainInfo]; they were simply never shown on this screen. Each block is
  /// dropped entirely when its list is empty rather than rendered as an empty
  /// heading, which is what the web does and what keeps a sparse chain from
  /// looking broken.
  ///
  /// Performance-only: a recovery placement carries no chain, so this is a
  /// no-op there.
  Widget _chainOutcomes(RefPalette p) {
    final chain = widget.payload.chain;
    if (chain == null) return const SizedBox.shrink();

    final injuries = chain.injuryRiskReduction
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final benefits = chain.performanceRomBenefits
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (injuries.isEmpty && benefits.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (injuries.isNotEmpty) ...[
              const HwEyebrow('Common injuries'),
              const SizedBox(height: HwSpace.s2),
              Text(
                'Injuries commonly seen in this role:',
                style: TextStyle(
                  fontSize: HwType.cap,
                  height: 1.5,
                  color: p.ink2,
                ),
              ),
              const SizedBox(height: HwSpace.s2),
              _bullets(p, injuries),
            ],
            if (injuries.isNotEmpty && benefits.isNotEmpty)
              const SizedBox(height: HwSpace.s2),
            if (benefits.isNotEmpty) ...[
              const HwEyebrow('Performance improvements'),
              const SizedBox(height: HwSpace.s2),
              _bullets(p, benefits),
            ],
          ],
        ),
      ),
    );
  }

  // ── recovery detail ────────────────────────────────────────────────────────
  //
  // Everything `/recovery-engine-v3/resolve` returns beyond the pads, in the
  // web's order and with the web's wording (`RecoveryResultPanel.jsx`): driver →
  // thermal → what this is for → reassessment → disclaimer → authored cautions →
  // data notes → source. The engine authors all of it; none of it is composed
  // here, and the two disclaimers and the wellness claim are printed verbatim.

  /// A titled block of rows — the web's `recovery-block`.
  Widget _recoveryBlock(
    RefPalette p,
    String title,
    List<Widget> children, {
    Widget? trailing,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: HwEyebrow(title)),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: HwSpace.s2),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _body(RefPalette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: HwSpace.s2),
        child: Text(
          text,
          style: TextStyle(fontSize: HwType.cap, height: 1.5, color: p.ink2),
        ),
      );

  /// A `dt`/`dd` pair from the web's `recovery-meta` / benefit grid.
  Widget _metaRow(RefPalette p, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: HwType.eyebrow,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: p.ink3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: HwType.cap, height: 1.45, color: p.ink2),
          ),
        ],
      ),
    );
  }

  Widget _bullets(RefPalette p, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•',
                      style:
                          TextStyle(fontSize: HwType.cap, color: p.copperInk)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        height: 1.45,
                        color: p.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A tinted callout — the web's `recovery-notice`.
  Widget _notice(RefPalette p, String title, String body, {Color? tint}) {
    final color = tint ?? p.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(HwSpace.s3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(HwRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (body.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: HwType.cap,
                  height: 1.5,
                  color: p.ink2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A collapsed list — the web's `<details>`. Used for the practitioner-only
  /// lists, which are deliberately not client-facing.
  Widget _collapsible(RefPalette p, String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s3),
      child: HwCard(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: HwSpace.s2),
            title: Text(
              '$title (${items.length})',
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w700,
                color: p.copperInk,
              ),
            ),
            children: [_bullets(p, items)],
          ),
        ),
      ),
    );
  }

  /// The notices that must sit ABOVE the placement, because they change what the
  /// placement means: a composed point, and a rerouted pathway.
  List<Widget> _recoveryNotices(RefPalette p, RecoveryPlacement r) {
    return [
      if (r.isComposed)
        _notice(
          p,
          'Composed placement — not authored',
          'This placement was composed by the engine rather than taken from an '
              'authored point. Read it as a starting position, not a prescription.',
          tint: p.mid,
        ),
      if (r.pathwayRerouted)
        _notice(
          p,
          'This is a lymphatic drainage placement',
          'You mentioned heaviness or swelling, so the engine routed this to the '
              'lymphatic branch instead of '
              '${_humanizeKey(r.requestedPathway).toLowerCase()}.',
        ),
    ];
  }

  /// Everything below the pads.
  List<Widget> _recoveryDetail(RefPalette p, RecoveryPlacement r) {
    return [
      // DRIVER — the core teaching: the driver, not the site.
      _recoveryBlock(p, 'Driver', [
        if (r.driverDescription.trim().isNotEmpty)
          _body(p, r.driverDescription),
        _metaRow(p, 'Case', r.caseType),
        _metaRow(p, 'You reported it travels to', r.referralTargetReported),
        _metaRow(p, 'Lymphatic hub', r.lymphaticRegion),
        _metaRow(p, 'Tissue', r.tissueType),
        _metaRow(p, 'Movement test', r.movementTest),
        // The engine's own reading of the presentation. Not on the web panel;
        // shown here because the practitioner is the only reader.
        _metaRow(
          p,
          'Presentation',
          [
            r.conditionFamily,
            r.acuity,
            [r.presentationSide, r.presentationAspect]
                .where((s) => s.trim().isNotEmpty)
                .join(' '),
          ].where((s) => s.trim().isNotEmpty).join(' · '),
        ),
      ]),

      // THERMAL — a recommendation, never an instruction. The tag says so.
      _recoveryBlock(
        p,
        'Thermal',
        [
          if (r.thermalRationale.trim().isNotEmpty)
            _body(p, r.thermalRationale),
          if (r.thermalDowngrade.trim().isNotEmpty)
            _notice(p, 'Adjusted from Fast switch', r.thermalDowngrade,
                tint: p.mid),
          if (r.thermalAlternatives.isNotEmpty) ...[
            Text(
              'Alternatives that may be justified:',
              style: TextStyle(
                fontSize: HwType.eyebrow,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: p.ink3,
              ),
            ),
            const SizedBox(height: 4),
            _bullets(p, r.thermalAlternatives),
          ] else
            Text(
              'No alternative authored for this case.',
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
        ],
        trailing: r.thermalMode.trim().isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HwPill(r.thermalLabel),
                  if (r.thermalRecommendationOnly) ...[
                    const SizedBox(width: 6),
                    Text(
                      'RECOMMENDATION',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: p.ink3,
                      ),
                    ),
                  ],
                ],
              ),
      ),

      // WHAT THIS IS FOR — mechanism is authored on every point, so it renders
      // unconditionally: a point missing it should look wrong, not silently drop
      // the section.
      _recoveryBlock(p, 'What this is for', [
        _bullets(p, r.whatItHelpsRelieve),
        _metaRow(
          p,
          'Mechanism',
          r.mechanismRationale.trim().isEmpty
              ? 'No mechanism is authored for this point.'
              : r.mechanismRationale,
        ),
        _metaRow(p, 'Mobility and range', r.mobilityBenefit),
        _metaRow(p, 'Lymphatic and circulatory', r.lymphaticBenefit),
        _metaRow(p, 'Tissue recovery', r.tissueBenefit),
        _metaRow(p, 'What it should feel like', r.expectedSensation),
        if (r.wellnessClaim.trim().isNotEmpty) _claim(p, r.wellnessClaim),
      ]),

      // REASSESSMENT — marker + window, authored on every point.
      _recoveryBlock(p, 'Reassessment', [
        _body(
          p,
          r.reassessmentMarker.trim().isEmpty
              ? 'No reassessment marker is authored for this point.'
              : r.reassessmentMarker,
        ),
        // Sits directly against the sentence it is about, and says so — a
        // warning beside a placement reads as a warning ABOUT the placement
        // unless it says otherwise.
        if (r.reassessmentNoteMessage.trim().isNotEmpty)
          _body(
            p,
            'Note — ${r.reassessmentNoteLabel}. ${r.reassessmentNoteMessage}'
            '${r.reassessmentTestsOffered.isEmpty ? '' : ' This region’s authored tests: ${r.reassessmentTestsOffered.join('; ')}.'}',
          ),
        if (r.expectedWindow.trim().isNotEmpty)
          _metaRow(
            p,
            'Typical window',
            '${r.expectedWindow}'
                '${r.expectedWindowNote.trim().isEmpty ? '' : ' — ${r.expectedWindowNote}'}',
          ),
      ]),

      // The client-facing contraindication LIST is deliberately not rendered
      // (Jul 25 review) — this short disclaimer replaces it. Nothing about what
      // is BLOCKED changed: the pre-gate still runs and a refer-out still
      // suppresses the pads.
      if (r.clientDisclaimer.trim().isNotEmpty)
        _disclaimer(p, r.clientDisclaimer),

      // Practitioner-only, collapsed.
      _collapsible(p, 'Authored cautions', r.cautions),
      _collapsible(p, 'Data notes on this point', r.reviewFlags),

      if (r.recoveryId.trim().isNotEmpty)
        _sourceLine(
            p,
            [
              r.recoveryId,
              if (r.pointVersion.trim().isNotEmpty) 'v${r.pointVersion}',
              if (r.generation.trim().isNotEmpty) r.generation,
              if (r.pointSource.trim().isNotEmpty) r.pointSource,
            ].join(' · ')),
      if (r.practitionerDisclaimer.trim().isNotEmpty)
        _sourceLine(p, r.practitionerDisclaimer),
    ];
  }

  /// The wellness claim, verbatim, set apart as the web's blockquote — it is
  /// compliance-authored wording and is never rephrased.
  Widget _claim(RefPalette p, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4, bottom: HwSpace.s1),
        padding: const EdgeInsets.fromLTRB(
            HwSpace.s3, HwSpace.s2, HwSpace.s3, HwSpace.s2),
        decoration: BoxDecoration(
          color: p.tanSoft,
          borderRadius: BorderRadius.circular(HwRadius.sm),
          border: Border(left: BorderSide(color: p.copper, width: 3)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: HwType.cap,
            height: 1.5,
            fontStyle: FontStyle.italic,
            color: p.ink2,
          ),
        ),
      );

  Widget _disclaimer(RefPalette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: HwSpace.s3),
        child: Text(
          text,
          style:
              TextStyle(fontSize: HwType.eyebrow, height: 1.5, color: p.ink3),
        ),
      );

  Widget _sourceLine(RefPalette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: HwSpace.s2),
        child: Text(
          text,
          style: TextStyle(fontSize: 10, height: 1.5, color: p.ink3),
        ),
      );

  // ── guide + notices ────────────────────────────────────────────────────────

  Widget _padGuide(RefPalette p) {
    Widget row(bool sun, String text) => Padding(
          padding: const EdgeInsets.only(bottom: HwSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: sun ? p.sunGrad : p.moonGrad,
                  borderRadius: BorderRadius.circular(HwRadius.xs),
                ),
                child: Text(
                  sun ? '☀' : '☾',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: HwSpace.s2),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: HwType.cap,
                    color: p.ink2,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );

    return HwCard(
      child: Column(
        children: [
          row(true, 'Sun pad → placed on the right / front side of the area'),
          row(false, 'Moon pad → placed on the left / back side of the area'),
        ],
      ),
    );
  }

  Widget _unmappedNotice(RefPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: HwSpace.s3),
      child: Container(
        padding: const EdgeInsets.all(HwSpace.s3),
        decoration: BoxDecoration(
          color: p.midSoft,
          borderRadius: BorderRadius.circular(HwRadius.lg),
        ),
        child: Text(
          'Some pads in this set aren’t mapped to the 3D model yet, so no marker '
          'is drawn for them. Use the written placement above — a marker in the '
          'wrong place would be worse than none.',
          style: TextStyle(fontSize: HwType.cap, color: p.mid, height: 1.5),
        ),
      ),
    );
  }

  void _savePreset() {
    // Presets are a separate feature (More → Presets); the spec's ☆ affordance
    // lives here so the surface is complete. Wiring it to the presets store is
    // out of scope for the pad-set work.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Save as preset is coming to this screen')),
    );
  }
}
