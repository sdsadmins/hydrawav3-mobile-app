import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../pad_placement/domain/pad_marker_mapper.dart';
import '../../../pad_placement/presentation/widgets/pad_anatomy_view.dart';
import '../../domain/performance_models.dart';
import 'go_to_session.dart';

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

  const PadMapScreen({super.key, required this.payload, this.clientName});

  @override
  ConsumerState<PadMapScreen> createState() => _PadMapScreenState();
}

class _PadMapScreenState extends ConsumerState<PadMapScreen> {
  final _anatomy = PadAnatomyController();
  late final PadPlacementViewData _data;

  /// null = the spec's "All areas" chip.
  int? _focusSet;
  late String _view;
  bool _showLabels = true;
  bool _showMuscles = false;

  // ---- web-parity view options (PerformanceProtocolStoreFlow.jsx) ------------------------------
  // The same four options the web exposes above its AnatomyScene, with the same semantics, so one
  // chain reads identically in both clients.

  /// Muscle Mode: the target muscle IS the indicator — painted red (Sun) / blue (Moon) with NO disc
  /// and NO badge on the body — and the un-targeted skin goes solid. Web parity:
  /// `padStyle="muscle"` + `transparentBody={!muscleMode}`. Defaults ON, matching the web view.
  bool _muscleMode = true;

  /// Off = the focused set only. On = the whole chain at once.
  bool _showAllSets = false;

  /// Flip the whole chain to the opposite side. Disabled under [_bilateral], which shows both anyway.
  bool _mirrored = false;

  /// Draw the chain on BOTH sides at once. Wins over [_mirrored] rather than compounding with it —
  /// mirroring something already drawn on both sides is a no-op, so it is ignored, not half-applied.
  bool _bilateral = false;

  /// What the mirror toggle reads. Bilateral overrides it, so say BOTH rather than naming a side that
  /// is not what is on screen.
  String get _mirrorLabel => _bilateral ? 'BOTH' : (_mirrored ? 'LEFT' : 'RIGHT');

  /// One source of truth for which pads are visible, so the stage, legend and notes cannot disagree.
  int? get _visibleSetIndex => _showAllSets ? null : _focusSet;

  /// `setIndex:role` keys the viewer reported it could not place.
  Set<String> _unmappedByViewer = const {};

  @override
  void initState() {
    super.initState();
    _data = PadPlacementViewData.from(widget.payload);
    _view = _data.viewFor(null);
  }

  Color _setColor(RefPalette p, int i) =>
      [p.set1, p.set2, p.set3][i % 3];

  /// Focusing a set jumps to the view that set sits on — `focusPadSet()` in the
  /// spec does the same, otherwise you focus a posterior set and see an empty
  /// front view.
  void _focus(int? index) {
    setState(() {
      _focusSet = index;
      _view = _data.viewFor(index);
    });
  }

  void _flip() => setState(() => _view = _view == 'front' ? 'back' : 'front');

  bool _isUnmapped(ResolvedPad pad) =>
      pad.isUnmapped || _unmappedByViewer.contains('${pad.setIndex}:${pad.role}');

  List<String> get _highlightMuscles {
    // Muscle Mode already colours every target muscle by role, from the markers themselves. Handing
    // the viewer a second flat list on top would repaint them one uniform tint and destroy the
    // Sun/Moon distinction — which in that mode is the ONLY thing marking the placement.
    if (_muscleMode) return const [];
    if (!_showMuscles) return const [];
    return _data
        .padsFor(_visibleSetIndex)
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
                  _padGuide(p),
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
    if (index == null) return sets;
    return index >= 0 && index < sets.length ? [sets[index]] : sets;
  }

  // ── head ───────────────────────────────────────────────────────────────────

  Widget _head(RefPalette p, int count) {
    final chain = widget.payload.chain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Placement',
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
          '${widget.payload.contextLine.isEmpty ? '' : ' · ${widget.payload.contextLine}'}',
          style: TextStyle(fontSize: HwType.cap, color: p.ink3),
        ),
        if (chain != null && chain.name.trim().isNotEmpty) ...[
          const SizedBox(height: HwSpace.s2),
          Row(
            children: [
              Expanded(
                child: Text(
                  chain.name,
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
              ),
              if (chain.subline.isNotEmpty) HwPill(chain.subline),
            ],
          ),
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
          for (var i = 0; i < sets.length; i++) ...[
            const SizedBox(width: HwSpace.s2),
            _setChip(p, i, sets[i]),
          ],
        ],
      ),
    );
  }

  Widget _setChip(RefPalette p, int i, PadSet set) {
    final selected = _focusSet == i;
    final label = set.placementLabel.trim().isEmpty
        ? 'Set ${set.setIndex}'
        : set.placementLabel;
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
          boxShadow: selected ? null : p.shadow,
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
            Text(
              label,
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w600,
                color: selected ? p.copperInk : p.ink,
              ),
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
          Positioned.fill(
            child: PadAnatomyView(
              markers: _data.markers(
                focusSetIndex: _visibleSetIndex,
                mirrored: _mirrored,
                bilateral: _bilateral,
              ),
              view: _view,
              showLabels: _showLabels,
              padStyle: _muscleMode ? 'muscle' : 'dot',
              muscleMode: _muscleMode,
              highlightMuscles: _highlightMuscles,
              controller: _anatomy,
              onUnmapped: (keys) {
                if (!mounted || keys.isEmpty) return;
                setState(() => _unmappedByViewer = keys);
              },
            ),
          ),
          Positioned(
            top: HwSpace.s3,
            left: HwSpace.s3,
            child: HwPill(
              _view == 'front' ? 'Front' : 'Back',
              tone: HwPillTone.copper,
            ),
          ),
          Positioned(
            top: HwSpace.s3,
            right: HwSpace.s3,
            child: Column(
              children: [
                HwIconButton(asset: HwIcons.rotate, onTap: _flip),
                const SizedBox(height: HwSpace.s2),
                _stageToggle(
                  p,
                  label: _showLabels ? 'Labels on' : 'Labels off',
                  active: _showLabels,
                  onTap: () => setState(() => _showLabels = !_showLabels),
                ),
                const SizedBox(height: HwSpace.s1),
                _stageToggle(
                  p,
                  label: 'Muscles',
                  active: _showMuscles,
                  onTap: () => setState(() => _showMuscles = !_showMuscles),
                ),
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
                  _zoomBtn(p, Icons.add, _anatomy.zoomIn),
                  _zoomBtn(p, Icons.remove, _anatomy.zoomOut),
                  _zoomBtn(p, Icons.refresh, _anatomy.reset, border: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
            active ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
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
        for (var i = 0; i < sets.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _setColor(p, i),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: HwSpace.s1 + 2),
              Text(
                'Set ${sets[i].setIndex}',
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
    final i = _data.sets.indexOf(set);
    final sun = _data.padOf(i, 'sun');
    final moon = _data.padOf(i, 'moon');
    final offView = [sun, moon]
        .whereType<ResolvedPad>()
        .where((r) => r.view != _view && r.view != 'side')
        .toList();

    return Padding
      (padding: const EdgeInsets.only(bottom: HwSpace.s3),
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
                    color: _setColor(p, i).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(HwRadius.xs),
                    border: Border.all(color: _setColor(p, i), width: 1.5),
                  ),
                  child: Text(
                    '${set.setIndex}',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w800,
                      color: _setColor(p, i),
                    ),
                  ),
                ),
                const SizedBox(width: HwSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        set.title,
                        style: TextStyle(
                          fontSize: HwType.base,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
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
            if (set.clinicalReasoning.trim().isNotEmpty) ...[
              const SizedBox(height: HwSpace.s2),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
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
