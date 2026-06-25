import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

/// Tappable human body diagram with Front/Back views (parity with the web
/// `bodyMap.tsx`). Regions are SVG paths (viewBox 300x700) rendered with
/// [CustomPaint] and hit-tested on tap. Tapping a region calls [onSelect] with
/// the region's label (e.g. "Front Left Upper Leg"); selected regions are
/// highlighted.
class BodyMap extends StatefulWidget {
  final List<String> selectedAreas;
  final ValueChanged<String> onSelect;

  /// When set ('front' | 'back'), renders that view only with no toggle (used
  /// to show both views side by side). When null, shows a Front/Back toggle.
  final String? forcedView;

  const BodyMap({
    super.key,
    required this.selectedAreas,
    required this.onSelect,
    this.forcedView,
  });

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _BodyMapState extends State<BodyMap> {
  String _view = 'front'; // 'front' | 'back'

  @override
  Widget build(BuildContext context) {
    final view = widget.forcedView ?? _view;
    final regions = view == 'front' ? _frontRegions : _backRegions;

    final diagram = AspectRatio(
      aspectRatio: 300 / 700,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / 300.0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final p = details.localPosition;
              final vb = Offset(p.dx / scale, p.dy / scale);
              // Iterate in reverse so smaller, later-drawn regions
              // (elbows over arms) win on overlap.
              for (final r in regions.reversed) {
                if (_pathFor(r.d).contains(vb)) {
                  widget.onSelect(r.name);
                  return;
                }
              }
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _BodyPainter(
                regions: regions,
                selected: widget.selectedAreas.toSet(),
                scale: scale,
              ),
            ),
          );
        },
      ),
    );

    // Side-by-side usage: caller supplies the label; render the diagram only.
    if (widget.forcedView != null) return diagram;

    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: ThemeConstants.segmentInactiveBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _viewTab('Front', 'front'),
              _viewTab('Back', 'back'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 360, child: diagram),
      ],
    );
  }

  Widget _viewTab(String label, String value) {
    final active = _view == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _view = value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: active ? ThemeConstants.segmentActiveBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color:
                  active ? ThemeConstants.onNav : ThemeConstants.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Derive the [DiscomfortSide]-equivalent string from a region label.
String sideFromAreaName(String area) {
  final l = area.toLowerCase();
  if (l.contains('left')) return 'Left';
  if (l.contains('right')) return 'Right';
  return 'Both';
}

// --- Painter ---------------------------------------------------------------

class _BodyPainter extends CustomPainter {
  final List<_Region> regions;
  final Set<String> selected;
  final double scale;

  _BodyPainter({
    required this.regions,
    required this.selected,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ThemeConstants.background;
    final unselected = Paint()
      ..style = PaintingStyle.fill
      ..color = ThemeConstants.textSecondary.withValues(alpha: 0.32);
    final selectedPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = ThemeConstants.accent;

    for (final r in regions) {
      final path = _pathFor(r.d);
      canvas.drawPath(path, selected.contains(r.name) ? selectedPaint : unselected);
      canvas.drawPath(path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.selected != selected ||
      old.scale != scale ||
      old.regions != regions;
}

// --- SVG path parsing (cached) ---------------------------------------------

// Keyed by the path string (NOT the region name): bilateral parts like
// "Left Shoulder" have different geometry in the front vs back view.
final Map<String, ui.Path> _pathCache = {};

ui.Path _pathFor(String d) =>
    _pathCache.putIfAbsent(d, () => _parseSvgPath(d));

/// Minimal SVG path parser for the absolute commands used by the body map:
/// M, L, C, Q, Z. Sufficient for `bodyMap.tsx` (no relative/arc commands).
ui.Path _parseSvgPath(String d) {
  final path = ui.Path();
  final tokenRe = RegExp(r'([MLCQZ])([^MLCQZ]*)');
  final numRe = RegExp(r'-?\d*\.?\d+');
  for (final t in tokenRe.allMatches(d)) {
    final cmd = t.group(1)!;
    final nums = numRe
        .allMatches(t.group(2) ?? '')
        .map((m) => double.parse(m.group(0)!))
        .toList();
    switch (cmd) {
      case 'M':
        for (var i = 0; i + 2 <= nums.length; i += 2) {
          if (i == 0) {
            path.moveTo(nums[i], nums[i + 1]);
          } else {
            path.lineTo(nums[i], nums[i + 1]);
          }
        }
        break;
      case 'L':
        for (var i = 0; i + 2 <= nums.length; i += 2) {
          path.lineTo(nums[i], nums[i + 1]);
        }
        break;
      case 'C':
        for (var i = 0; i + 6 <= nums.length; i += 6) {
          path.cubicTo(nums[i], nums[i + 1], nums[i + 2], nums[i + 3],
              nums[i + 4], nums[i + 5]);
        }
        break;
      case 'Q':
        for (var i = 0; i + 4 <= nums.length; i += 4) {
          path.quadraticBezierTo(
              nums[i], nums[i + 1], nums[i + 2], nums[i + 3]);
        }
        break;
      case 'Z':
        path.close();
        break;
    }
  }
  return path;
}

// --- Region data (exact paths from web `bodyMap.tsx`) ----------------------

class _Region {
  final String name;
  final String d;
  const _Region(this.name, this.d);
}

const _commonRegions = <_Region>[
  _Region('Head',
      'M150,25 C132,25 120,38 120,60 C120,85 132,95 150,95 C168,95 180,85 180,60 C180,38 168,25 150,25 Z'),
  _Region('Neck', 'M136,94 L136,115 Q150,120 164,115 L164,94 Q150,100 136,94 Z'),
];

const _frontRegions = <_Region>[
  ..._commonRegions,
  _Region('Chest',
      'M136,115 Q150,120 164,115 L185,130 L180,170 L120,170 L115,130 L136,115 Z'),
  _Region('Abdomen', 'M120,172 L180,172 L175,205 Q150,215 125,205 L120,172 Z'),
  _Region('Front Right Hip',
      'M125,207 Q150,217 150,217 L150,325 L106,300 L98,280 Q100,250 120,230 L125,207 Z'),
  _Region('Front Left Hip',
      'M175,207 Q150,217 150,217 L150,325 L194,300 L202,280 Q200,250 180,230 L175,207 Z'),
  _Region('Right Shoulder',
      'M115,130 L120,170 L110,175 L75,155 Q70,135 88,122 L115,130 Z'),
  _Region('Left Shoulder',
      'M185,130 L180,170 L190,175 L225,155 Q230,135 212,122 L185,130 Z'),
  _Region('Front Right Upper Arm',
      'M75,157 L110,177 L107,240 Q107,250 95,250 Q83,250 83,240 L75,157 Z'),
  _Region('Front Left Upper Arm',
      'M225,157 L190,177 L193,240 Q193,250 205,250 Q217,250 217,240 L225,157 Z'),
  _Region('Right Elbow', 'M85,240 L105,240 L104,252 L86,252 Z'),
  _Region('Left Elbow', 'M195,240 L215,240 L214,252 L196,252 Z'),
  _Region('Front Right Lower Arm',
      'M83,252 Q95,252 107,252 L105,315 L85,315 L83,252 Z'),
  _Region('Front Left Lower Arm',
      'M217,252 Q205,252 193,252 L195,315 L215,315 L217,252 Z'),
  _Region('Right Wrist', 'M85,317 L105,317 L104,332 L86,332 Z'),
  _Region('Left Wrist', 'M195,317 L215,317 L214,332 L196,332 Z'),
  _Region('Right Hand',
      'M86,334 L104,334 Q110,350 107,370 L103,385 Q95,395 87,385 L83,370 Q80,350 86,334 Z'),
  _Region('Left Hand',
      'M196,334 L214,334 Q220,350 217,370 L213,385 Q205,395 197,385 L193,370 Q190,350 196,334 Z'),
  _Region('Front Right Upper Leg',
      'M106,302 L150,327 L144,450 L110,450 Q102,380 106,302 Z'),
  _Region('Front Left Upper Leg',
      'M194,302 L150,327 L156,450 L190,450 Q198,380 194,302 Z'),
  _Region('Right Knee',
      'M112,452 L142,452 Q140,485 142,490 L112,490 Q114,485 112,452 Z'),
  _Region('Left Knee',
      'M158,452 L188,452 Q186,485 188,490 L158,490 Q160,485 158,452 Z'),
  _Region('Front Right Lower Leg',
      'M113,492 L141,492 Q144,530 142,560 L140,600 L115,600 Q116,560 113,492 Z'),
  _Region('Front Left Lower Leg',
      'M187,492 L159,492 Q156,530 158,560 L160,600 L185,600 Q184,560 187,492 Z'),
  _Region('Right Ankle', 'M115,602 L140,602 L139,620 L116,620 Z'),
  _Region('Left Ankle', 'M185,602 L160,602 L161,620 L184,620 Z'),
  _Region('Right Foot', 'M116,622 L139,622 L144,645 Q120,660 105,640 Z'),
  _Region('Left Foot', 'M184,622 L161,622 L156,645 Q180,660 195,640 Z'),
];

const _backRegions = <_Region>[
  ..._commonRegions,
  _Region('Upper Back',
      'M136,115 Q150,120 164,115 L185,130 L183,160 L117,160 L115,130 L136,115 Z'),
  _Region('Mid Back', 'M117,162 L183,162 L180,220 L120,220 Z'),
  _Region('Lower Back', 'M120,222 L180,222 L183,250 L117,250 Z'),
  _Region('Back Left Hip',
      'M117,252 L150,252 L150,325 L106,300 L98,280 Q100,270 117,252 Z'),
  _Region('Back Right Hip',
      'M183,252 L150,252 L150,325 L194,300 L202,280 Q200,270 183,252 Z'),
  _Region('Left Shoulder',
      'M115,130 L120,170 L110,175 L75,155 Q70,135 88,122 L115,130 Z'),
  _Region('Right Shoulder',
      'M185,130 L180,170 L190,175 L225,155 Q230,135 212,122 L185,130 Z'),
  _Region('Back Left Upper Arm',
      'M75,157 L110,177 L107,240 Q107,250 95,250 Q83,250 83,240 L75,157 Z'),
  _Region('Back Right Upper Arm',
      'M225,157 L190,177 L193,240 Q193,250 205,250 Q217,250 217,240 L225,157 Z'),
  _Region('Left Elbow', 'M85,240 L105,240 L104,252 L86,252 Z'),
  _Region('Right Elbow', 'M195,240 L215,240 L214,252 L196,252 Z'),
  _Region('Back Left Lower Arm',
      'M83,252 Q95,252 107,252 L105,315 L85,315 L83,252 Z'),
  _Region('Back Right Lower Arm',
      'M217,252 Q205,252 193,252 L195,315 L215,315 L217,252 Z'),
  _Region('Left Wrist', 'M85,317 L105,317 L104,332 L86,332 Z'),
  _Region('Right Wrist', 'M195,317 L215,317 L214,332 L196,332 Z'),
  _Region('Left Hand',
      'M86,334 L104,334 Q110,350 107,370 L103,385 Q95,395 87,385 L83,370 Q80,350 86,334 Z'),
  _Region('Right Hand',
      'M196,334 L214,334 Q220,350 217,370 L213,385 Q205,395 197,385 L193,370 Q190,350 196,334 Z'),
  _Region('Back Left Upper Leg',
      'M106,302 L150,327 L144,450 L110,450 Q102,380 106,302 Z'),
  _Region('Back Right Upper Leg',
      'M194,302 L150,327 L156,450 L190,450 Q198,380 194,302 Z'),
  _Region('Left Knee',
      'M112,452 L142,452 Q140,485 142,490 L112,490 Q114,485 112,452 Z'),
  _Region('Right Knee',
      'M158,452 L188,452 Q186,485 188,490 L158,490 Q160,485 158,452 Z'),
  _Region('Back Left Lower Leg',
      'M113,492 L141,492 Q144,530 142,560 L140,600 L115,600 Q116,560 113,492 Z'),
  _Region('Back Right Lower Leg',
      'M187,492 L159,492 Q156,530 158,560 L160,600 L185,600 Q184,560 187,492 Z'),
  _Region('Left Ankle', 'M115,602 L140,602 L139,620 L116,620 Z'),
  _Region('Right Ankle', 'M185,602 L160,602 L161,620 L184,620 Z'),
  _Region('Left Foot', 'M116,622 L139,622 L144,645 Q120,660 105,640 Z'),
  _Region('Right Foot', 'M184,622 L161,622 L156,645 Q180,660 195,640 Z'),
];
