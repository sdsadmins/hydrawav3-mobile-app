import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../domain/anatomy_scene_marker.dart';
import '../../domain/set_colors.dart';
import '../widgets/anatomy_scene_flag.dart';
import '../widgets/anatomy_scene_view.dart';
import '../widgets/pad_anatomy_view.dart';

/// Full-screen 3D Sun/Moon pad-placement viewer — the mobile port of the web
/// `AnatomyScene` (Hydrawave3 `apps/web/src/components/AnatomyScene.jsx`).
///
/// The WebView loads `assets/3d/pad_placement.html` over the bundled localhost
/// server (so WebGL + the Draco WASM worker can load) and renders ONLY the 3D
/// canvas; the view buttons, zoom cluster, labels toggle, legend and the pad
/// list are native Flutter widgets driving the viewer through the `window.*`
/// JS bridge (see `tool/kinetic_chain_viewer/pad_placement.src.js`).
///
/// [placement] is the raw response from `POST ai-padplacement/placement-session`
/// — `{ engine, nextQuestion, recommendation: { title, summary, sets:[{sun,
/// moon}] }, markers }`. Marker positions come from each marker's `zone`
/// landmark key, resolved inside the viewer.
class PadPlacement3DScreen extends StatefulWidget {
  final Map<String, dynamic> placement;
  final String? title;

  const PadPlacement3DScreen({
    super.key,
    required this.placement,
    this.title,
  });

  @override
  State<PadPlacement3DScreen> createState() => _PadPlacement3DScreenState();
}

class _PadPlacement3DScreenState extends State<PadPlacement3DScreen> {
  static const _sun = Color(0xFFF59E0B);
  static const _moon = Color(0xFF6366F1);
  static const _muted = Color(0xFF6B7280);
  static const _ink = Color(0xFF1A1A1A);

  // The WebView bridge (localhost server, ready-poll, marker injection) lives in
  // the stage widget, shared with the performance pad map. Both controllers are
  // held because `kUseAnatomySceneRecovery` picks which stage is built.
  final _anatomy = AnatomySceneController();
  final _legacyAnatomy = PadAnatomyController();
  bool _showLabels = true;
  String _view = 'front';

  /// The set whose pads are held highlighted, or null for none. Tapping a pad in
  /// the 3D stage selects its set, and tapping a row in the list below
  /// highlights that set's pads — the selection runs both ways.
  int? _selectedSet;

  List<Map<String, dynamic>> get _markers =>
      ((widget.placement['markers'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Map<String, dynamic> get _recommendation {
    final r = widget.placement['recommendation'];
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> get _sets =>
      ((_recommendation['sets'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  void _toggleLabels() => setState(() => _showLabels = !_showLabels);

  void _setView(String v) => setState(() => _view = v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: ThemeConstants.background,
        foregroundColor: ThemeConstants.textPrimary,
        elevation: 0,
        title: Text(
          widget.title ?? '3D Pad Placement',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ThemeConstants.textPrimary,
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_markers.isEmpty) {
      return _fallback(
        'No pad markers to show for this placement yet.',
      );
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _stage()),
              Positioned(top: 10, right: 10, child: _controls()),
              Positioned(top: 10, left: 10, child: _sunMoonLegend()),
              Positioned(top: 10, left: 10 + 160, child: _viewSwitcher()),
            ],
          ),
        ),
        _bottomPanel(),
      ],
    );
  }

  /// The 3D stage.
  ///
  /// Recovery pads are positioned entirely by their curated `zone` landmark —
  /// the server sends no muscle list — so the new viewer resolves them through
  /// exactly the same landmark table the old one used. `colorBySet`,
  /// `showSetLinks` and `transparentBody` are all off: those are performance
  /// affordances, and a recovery placement is one or two sets with no chain to
  /// draw between them.
  Widget _stage() {
    if (!kUseAnatomySceneRecovery) {
      return PadAnatomyView(
        markers: _markers,
        view: _view,
        showLabels: _showLabels,
        controller: _legacyAnatomy,
      );
    }
    return AnatomySceneView(
      markers: _markers,
      source: MarkerSource.recovery,
      view: _view,
      showLabels: _showLabels,
      padStyle: 'badge',
      colorBySet: false,
      showSetLinks: false,
      transparentBody: false,
      // This screen has no persistent front/back state to fight, so framing the
      // pads on arrival saves the practitioner an orbit.
      autoFocusCameraOnce: true,
      backgroundCss: '#ffffff',
      activeMarkers: _selectedSet == null
          ? const []
          : _markers
              .where((m) => _asInt(m['setIndex']) == _selectedSet)
              .toList(),
      onRegionPick: (marker) {
        if (!mounted) return;
        setState(() => _selectedSet =
            marker == null ? null : _asInt(marker['setIndex']));
      },
      controller: _anatomy,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  // The zoom cluster drives whichever stage the flag actually built.
  void _zoomIn() =>
      kUseAnatomySceneRecovery ? _anatomy.zoomIn() : _legacyAnatomy.zoomIn();
  void _zoomOut() =>
      kUseAnatomySceneRecovery ? _anatomy.zoomOut() : _legacyAnatomy.zoomOut();
  void _resetView() =>
      kUseAnatomySceneRecovery ? _anatomy.reset() : _legacyAnatomy.reset();

  // --- Top-left: front/back/side view switcher -------------------------------
  Widget _viewSwitcher() {
    Widget item(String key, String label) {
      final active = _view == key;
      return InkWell(
        onTap: () => _setView(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: active ? const Color(0xFF132A35) : Colors.transparent,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: active ? Colors.white : _muted,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            item('front', 'FRONT'),
            item('back', 'BACK'),
            item('left', 'L'),
            item('right', 'R'),
          ],
        ),
      ),
    );
  }

  // --- Top-right: zoom cluster + labels toggle -------------------------------
  Widget _controls() {
    Widget btn(IconData icon, VoidCallback onTap, {bool border = true}) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            border: border
                ? const Border(right: BorderSide(color: Color(0xFFE5E7EB)))
                : null,
          ),
          child: Icon(icon, size: 15, color: _muted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                btn(Icons.add, _zoomIn),
                btn(Icons.remove, _zoomOut),
                btn(Icons.refresh, _resetView, border: false),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _toggleLabels,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: _showLabels
                  ? const Color(0xFF132A35)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _showLabels
                    ? const Color(0xFF132A35)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Text(
              _showLabels ? 'Labels On' : 'Labels Off',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                color: _showLabels ? Colors.white : _muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sunMoonLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendToken(const Color(0xFFE11D48), '☀', 'Sun'),
          const SizedBox(width: 12),
          _legendToken(const Color(0xFF2563EB), '☾', 'Moon'),
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

  // --- Bottom: legend + per-set Sun/Moon list --------------------------------
  Widget _bottomPanel() {
    final sets = _sets;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              _LegendDot(color: _sun, label: 'Sun'),
              SizedBox(width: 18),
              _LegendDot(color: _moon, label: 'Moon'),
            ],
          ),
          // Set legend, matching the performance pad map. The 3D stage already
          // paints per-set badges and arcs from [kAnatomySetColors]; without
          // this the recovery screen was the only surface where those colours
          // appeared on the model but were named nowhere in the chrome.
          if (sets.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (var i = 0; i < sets.length; i++)
                  _LegendDot(
                    color: anatomySetColor(i),
                    label: 'Set ${i + 1}',
                    square: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < sets.length; i++) _setRow(i, sets[i]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _setRow(int index, Map<String, dynamic> set) {
    // The number is carried by the badge now, so an absent title falls back to
    // nothing rather than repeating it ("1  Set 1").
    final title = set['title']?.toString().trim() ?? '';
    final sun = set['sun'] is Map ? (set['sun']['label']?.toString() ?? '') : '';
    final moon =
        set['moon'] is Map ? (set['moon']['label']?.toString() ?? '') : '';
    final setting = set['setting']?.toString() ?? '';
    // The other half of the two-way selection: tapping a row highlights that
    // set's pads on the model, and tapping a pad selects the row. Tapping the
    // selected row again clears it.
    final selected = kUseAnatomySceneRecovery && _selectedSet == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: kUseAnatomySceneRecovery
            ? () => setState(
                  () => _selectedSet = selected ? null : index,
                )
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? anatomySetColor(index).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              // Selection takes the SET's colour, so the highlighted row and the
              // pads lit on the model are visibly the same set.
              color: selected ? anatomySetColor(index) : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Set N" in its own colour, then the authored title — the same
              // badge-then-title shape the performance pad map uses for its set
              // notes, so a set is identified the same way on both screens.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: anatomySetColor(index).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: anatomySetColor(index),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: anatomySetColor(index),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.isEmpty ? 'Set ${index + 1}' : title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.6,
                        color: _ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (sun.isNotEmpty) _padLine('S${index + 1}', sun, _sun),
              if (moon.isNotEmpty) _padLine('M${index + 1}', moon, _moon),
              if (setting.isNotEmpty && setting != 'Normal')
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Setting: $setting',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _padLine(String badge, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF374151),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_outlined,
                color: Color(0xFF9CA3AF), size: 48),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  /// Sets use a rounded SQUARE swatch, Sun/Moon a circle — the same shape split
  /// the performance pad map uses, so the two legends can't be confused for one
  /// another at a glance.
  final bool square;

  const _LegendDot({
    required this.color,
    required this.label,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(3) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }
}
