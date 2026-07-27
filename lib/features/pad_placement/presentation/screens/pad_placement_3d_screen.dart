import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
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
  // `PadAnatomyView`, shared with the performance pad map.
  final _anatomy = PadAnatomyController();
  bool _showLabels = true;
  String _view = 'front';

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
              Positioned.fill(
                child: PadAnatomyView(
                  markers: _markers,
                  view: _view,
                  showLabels: _showLabels,
                  controller: _anatomy,
                ),
              ),
              Positioned(top: 10, right: 10, child: _controls()),
              Positioned(top: 10, left: 10, child: _viewSwitcher()),
            ],
          ),
        ),
        _bottomPanel(),
      ],
    );
  }

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
                btn(Icons.add, _anatomy.zoomIn),
                btn(Icons.remove, _anatomy.zoomOut),
                btn(Icons.refresh, _anatomy.reset, border: false),
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
    final title = set['title']?.toString() ?? 'Set ${index + 1}';
    final sun = set['sun'] is Map ? (set['sun']['label']?.toString() ?? '') : '';
    final moon =
        set['moon'] is Map ? (set['moon']['label']?.toString() ?? '') : '';
    final setting = set['setting']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
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
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
