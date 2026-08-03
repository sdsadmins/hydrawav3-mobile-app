import 'package:flutter/material.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../domain/anatomy_scene_marker.dart';
import '../widgets/anatomy_scene_view.dart';

/// The 3D stage on its own, edge to edge.
///
/// The inline stage on the pad map is 380px tall and sits inside a scrolling
/// page — enough to read a placement, tight for inspecting one. This gives the
/// model the whole screen with nothing competing for the gesture.
///
/// It takes the caller's CURRENT stage settings rather than re-deriving them, so
/// expanding shows exactly what was on the small stage, just larger.
///
/// Chrome is drawn from [RefPalette], the same tokens as the rest of the app, so
/// this screen follows the active theme instead of being a white box that
/// ignores it — including the 3D canvas background, which is handed the theme's
/// card colour as CSS.
class AnatomySceneFullscreenScreen extends StatefulWidget {
  final List<Map<String, dynamic>> markers;
  final MarkerSource source;
  final List<String>? setRoles;

  final String title;
  final String initialView;

  final String padStyle;
  final bool transparentBody;
  final bool colorBySet;
  final bool showSetLinks;
  final int? focusSetIndex;
  final bool dimUnselected;
  final List<Map<String, dynamic>> activeMarkers;
  final List<String> highlightMuscles;
  final bool initialShowLabels;

  const AnatomySceneFullscreenScreen({
    super.key,
    required this.markers,
    required this.source,
    this.setRoles,
    this.title = '3D pad placement',
    this.initialView = 'front',
    this.padStyle = 'badge',
    this.transparentBody = false,
    this.colorBySet = false,
    this.showSetLinks = false,
    this.focusSetIndex,
    this.dimUnselected = false,
    this.activeMarkers = const [],
    this.highlightMuscles = const [],
    this.initialShowLabels = true,
  });

  @override
  State<AnatomySceneFullscreenScreen> createState() =>
      _AnatomySceneFullscreenScreenState();
}

class _AnatomySceneFullscreenScreenState
    extends State<AnatomySceneFullscreenScreen> {
  final _anatomy = AnatomySceneController();
  late bool _showLabels = widget.initialShowLabels;

  /// `#rrggbb` for the viewer, which takes a CSS colour. Alpha is dropped: the
  /// canvas fills an opaque screen, so there is nothing behind it to blend with.
  static String _cssOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HwSpace.s4),
              child: HwBackBar(
                title: widget.title,
                subtitle: 'Drag to rotate · pinch to zoom',
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    HwSpace.s3, 0, HwSpace.s3, HwSpace.s3),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card2,
                    borderRadius: BorderRadius.circular(HwRadius.xl),
                    border: Border.all(color: p.cardline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnatomySceneView(
                          markers: widget.markers,
                          source: widget.source,
                          setRoles: widget.setRoles,
                          view: widget.initialView,
                          showLabels: _showLabels,
                          padStyle: widget.padStyle,
                          transparentBody: widget.transparentBody,
                          colorBySet: widget.colorBySet,
                          showSetLinks: widget.showSetLinks,
                          focusSetIndex: widget.focusSetIndex,
                          dimUnselected: widget.dimUnselected,
                          activeMarkers: widget.activeMarkers,
                          highlightMuscles: widget.highlightMuscles,
                          // The canvas takes the same colour as the card it sits
                          // in, so the model reads as part of the surface rather
                          // than floating on a white rectangle.
                          backgroundCss: _cssOf(p.card2),
                          controller: _anatomy,
                        ),
                      ),
                      // Labels + zoom share the top-right corner so the bottom
                      // of the card is left clear for the exit action.
                      Positioned(
                        top: HwSpace.s3,
                        right: HwSpace.s3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _zoomCluster(p),
                            const SizedBox(height: HwSpace.s2),
                            _labelsToggle(p),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: HwSpace.s4,
                        left: 0,
                        right: 0,
                        child: Center(child: _exitButton(p)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The explicit collapse action, mirroring the ⤢ button that opened this
  /// screen. The back bar above would also close it, but that reads as "go back
  /// a page" rather than "shrink this view", and a thumb reaches the bottom of a
  /// phone far more easily than the top-left corner.
  Widget _exitButton(RefPalette p) {
    return HwPress(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: p.sunGrad,
          borderRadius: BorderRadius.circular(HwRadius.pill),
          boxShadow: p.shadow,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_fullscreen, size: 15, color: Colors.white),
            SizedBox(width: 7),
            Text(
              'Exit full screen',
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelsToggle(RefPalette p) {
    return HwPress(
      onTap: () => setState(() => _showLabels = !_showLabels),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _showLabels ? p.copper : p.card,
          borderRadius: BorderRadius.circular(HwRadius.xs),
          border: Border.all(color: _showLabels ? p.copper : p.line),
        ),
        child: Text(
          _showLabels ? 'Labels on' : 'Labels off',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
            color: _showLabels ? Colors.white : p.ink3,
          ),
        ),
      ),
    );
  }

  Widget _zoomCluster(RefPalette p) {
    Widget btn(IconData icon, VoidCallback onTap, {bool border = true}) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            border:
                border ? Border(right: BorderSide(color: p.line)) : null,
          ),
          child: Icon(icon, size: 16, color: p.ink3),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(HwRadius.md),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.add, _anatomy.zoomIn),
          btn(Icons.remove, _anatomy.zoomOut),
          btn(Icons.refresh, _anatomy.reset, border: false),
        ],
      ),
    );
  }
}
