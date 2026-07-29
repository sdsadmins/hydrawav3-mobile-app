import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../domain/anatomy_scene_marker.dart';
import 'pad_anatomy_view.dart' show PadAnatomyFallback;

/// The AnatomyScene stage — the high-fidelity Z-Anatomy viewer, shared by the
/// Performance pad map and the Recovery 3D placement screen.
///
/// The viewer is `assets/3d/anatomy_scene.html` + `anatomy_scene.bundle.js`
/// (built from `tool/kinetic_chain_viewer/anatomy_scene.src.js`), served over
/// the bundled localhost server so WebGL and the Draco worker can load. This
/// widget owns: starting the server, waiting for `window.__ready`, translating
/// markers, pushing options, and surfacing taps.
///
/// It sits ALONGSIDE [PadAnatomyView], which stays as the rollback path behind
/// `anatomy_scene_flag.dart` — see that file for what to delete once this has
/// shipped.
///
/// Markers go in as the app already produces them; [toAnatomySceneMarkers] does
/// the translation to the viewer's (web) vocabulary in here rather than at the
/// call sites, so no screen can forget it.
class AnatomySceneView extends StatefulWidget {
  /// Markers in the app's own shape — `PadPlacementViewData.markers()` output,
  /// or the raw `markers` array from the recovery placement session.
  final List<Map<String, dynamic>> markers;

  /// Which producer [markers] came from. Recovery and Performance are positioned
  /// by different tiers and must be adapted differently.
  final MarkerSource source;

  /// `PadSet.role` per set index; shown on the set-arc labels. Performance only.
  final List<String>? setRoles;

  /// 'front' | 'back' | 'left' | 'right' | 'side'.
  final String view;

  /// Frame the camera on the resolved markers, once, after the first render.
  /// Off by default: on a screen that owns an explicit front/back toggle, an
  /// auto-focus fights the user's choice.
  final bool autoFocusCameraOnce;

  /// Pad badges and set-arc labels.
  final bool showLabels;

  /// `'badge'`  — a contact pad + a Sun/Moon badge on the skin.
  /// `'muscle'` — no pad and no badge; the target muscle itself is painted red
  ///              (Sun) or blue (Moon). Web parity with `padStyle="muscle"`.
  /// `'dot'` is accepted as an alias for `'badge'` so a caller migrating from
  /// [PadAnatomyView] does not have to change this value.
  final String padStyle;

  /// X-ray: fade every non-target mesh so pads behind muscle stay readable.
  /// Web parity: `transparentBody={!muscleMode}`.
  final bool transparentBody;

  /// Colour badges, highlights and arcs by SET (Okabe-Ito) instead of by role.
  final bool colorBySet;

  /// Draw a labelled Sun→Moon arc per set, bowing around the body.
  final bool showSetLinks;

  /// The focused set, or null for "all". Only dims when [dimUnselected] is set.
  final int? focusSetIndex;

  /// Fade everything outside the focused set.
  final bool dimUnselected;

  /// Markers to hold highlighted, in the app's shape (adapted here too).
  final List<Map<String, dynamic>> activeMarkers;

  /// A flat list of muscles to tint. Ignored when [padStyle] is `'muscle'` or
  /// when [activeMarkers] is non-empty — those express the same thing per-marker
  /// and the two would fight.
  final List<String> highlightMuscles;

  /// An opaque CSS colour for the canvas, or null to stay transparent so the
  /// surrounding Flutter card shows through.
  final String? backgroundCss;

  /// Report a tap on the body itself (point + mesh name) instead of resolving it
  /// to a muscle.
  final bool bodyTapMode;

  final AnatomySceneController? controller;

  /// Fired once the stage is live, or with a message when it is not.
  final ValueChanged<String?>? onReady;

  /// `setIndex:role` keys no tier could place. Nothing is drawn for these.
  final ValueChanged<Set<String>>? onUnmapped;

  /// A pad was tapped. Carries the ORIGINAL (unadapted) marker, so callers work
  /// in their own vocabulary. Null when the tap missed every pad.
  final ValueChanged<Map<String, dynamic>?>? onRegionPick;

  /// `{point: [x,y,z], meshName: String}` — only when [bodyTapMode] is on.
  final ValueChanged<Map<String, dynamic>>? onBodyTap;

  /// A highlighted muscle was tapped: `{name, role, setIndex}`.
  final ValueChanged<Map<String, dynamic>>? onMuscleSelected;

  const AnatomySceneView({
    super.key,
    required this.markers,
    required this.source,
    this.setRoles,
    this.view = 'front',
    this.autoFocusCameraOnce = false,
    this.showLabels = true,
    this.padStyle = 'badge',
    this.transparentBody = false,
    this.colorBySet = false,
    this.showSetLinks = false,
    this.focusSetIndex,
    this.dimUnselected = false,
    this.activeMarkers = const [],
    this.highlightMuscles = const [],
    this.backgroundCss,
    this.bodyTapMode = false,
    this.controller,
    this.onReady,
    this.onUnmapped,
    this.onRegionPick,
    this.onBodyTap,
    this.onMuscleSelected,
  });

  @override
  State<AnatomySceneView> createState() => _AnatomySceneViewState();
}

/// Imperative hooks the surrounding Flutter chrome needs.
class AnatomySceneController {
  _AnatomySceneViewState? _state;

  void zoomIn() => _state?._eval('window.zoomIn && window.zoomIn()');
  void zoomOut() => _state?._eval('window.zoomOut && window.zoomOut()');
  void reset() => _state?._eval('window.resetView && window.resetView()');
  void setView(String view) =>
      _state?._eval("window.setView && window.setView('$view')");
  void focusCamera() =>
      _state?._eval('window.focusCamera && window.focusCamera()');

  /// The viewer's own account of what it rendered. There is no JS test harness,
  /// so this is the JS-side assertion surface — `anchorsHit` vs `anchorsTotal`
  /// in particular, because a silent drop from the anchor tier to the
  /// bounding-box tier looks fine on screen but places pads noticeably worse.
  Future<Map<String, dynamic>?> state() async => _state?._viewerState();
}

class _AnatomySceneViewState extends State<AnatomySceneView> {
  // Same pattern as PadAnatomyView and KineticChain3DScreen: each surface
  // declares its own instance and `shared: true` makes the concurrent bind
  // legal. Not extracted into a singleton because that would mean editing
  // pad_anatomy_view.dart, which is deliberately frozen as the rollback path.
  static final InAppLocalhostServer _server = InAppLocalhostServer(
    documentRoot: 'assets/3d',
    port: 8080,
    shared: true,
  );

  InAppWebViewController? _controller;
  bool _serverReady = false;
  bool _loading = true;
  bool _webglError = false;
  String? _serverError;

  late List<Map<String, dynamic>> _adapted;
  late List<Map<String, dynamic>> _adaptedActive;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _adapt();
    _startServer();
  }

  void _adapt() {
    _adapted = toAnatomySceneMarkers(
      widget.markers,
      source: widget.source,
      setRoles: widget.setRoles,
    );
    _adaptedActive = toAnatomySceneMarkers(
      widget.activeMarkers,
      source: widget.source,
      setRoles: widget.setRoles,
    );
  }

  @override
  void didUpdateWidget(AnatomySceneView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }

    final markersChanged = !_sameMaps(old.markers, widget.markers) ||
        !_sameStrings(old.setRoles ?? const [], widget.setRoles ?? const []);
    final activeChanged = !_sameMaps(old.activeMarkers, widget.activeMarkers);
    if (markersChanged || activeChanged) _adapt();

    if (_loading || _webglError) return;

    // Options FIRST: padStyle decides whether a marker becomes a pad or a
    // coloured muscle, so applying it after the marker render would draw the old
    // style for one frame.
    if (_optionsChanged(old)) _applyViewOptions();
    if (markersChanged) _renderMarkers();
    if (activeChanged) _applyActiveMarkers();
    if (old.view != widget.view) {
      _eval("window.setView && window.setView('${widget.view}')");
    }
    if (old.showLabels != widget.showLabels) {
      _eval('window.setLabels && window.setLabels(${widget.showLabels})');
    }
    if (!_sameStrings(old.highlightMuscles, widget.highlightMuscles)) {
      _applyHighlight();
    }
    if (old.backgroundCss != widget.backgroundCss) _applyBackground();
    if (old.bodyTapMode != widget.bodyTapMode) {
      _eval(
        'window.setBodyTapMode && window.setBodyTapMode(${widget.bodyTapMode})',
      );
    }
  }

  bool _optionsChanged(AnatomySceneView old) =>
      old.padStyle != widget.padStyle ||
      old.colorBySet != widget.colorBySet ||
      old.showSetLinks != widget.showSetLinks ||
      old.transparentBody != widget.transparentBody ||
      old.focusSetIndex != widget.focusSetIndex ||
      old.dimUnselected != widget.dimUnselected;

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      if (!_server.isRunning()) await _server.start();
      if (mounted) setState(() => _serverReady = true);
    } catch (e) {
      // Another 3D surface may already hold the port — a running server is fine.
      if (_server.isRunning()) {
        if (mounted) setState(() => _serverReady = true);
        return;
      }
      if (mounted) {
        setState(() {
          _serverError = e.toString();
          _loading = false;
        });
        widget.onReady?.call('Couldn’t start the 3D viewer.\n$e');
      }
    }
  }

  /// Poll `window.__ready`, then inject. The viewer sets it once the GLB is
  /// parsed — or immediately when WebGL is unavailable.
  Future<void> _injectWhenReady() async {
    final controller = _controller;
    if (controller == null) return;
    for (var i = 0; i < 100; i++) {
      final ready =
          await controller.evaluateJavascript(source: 'window.__ready === true');
      if (ready == true || ready == 'true') {
        final webglError = await controller.evaluateJavascript(
          source: 'window.__webglError === true',
        );
        if (webglError == true || webglError == 'true') {
          if (mounted) {
            setState(() {
              _webglError = true;
              _loading = false;
            });
            widget.onReady?.call('3D is not supported on this device.');
          }
          return;
        }

        await _checkVersion();
        // Options BEFORE the first render, for the reason in didUpdateWidget.
        await _applyViewOptions();
        await _applyBackground();
        await _renderMarkers();
        await _eval(
          'window.setLabels && window.setLabels(${widget.showLabels})',
        );
        if (widget.view != 'front') {
          await _eval("window.setView && window.setView('${widget.view}')");
        }
        await _applyHighlight();
        await _applyActiveMarkers();
        if (widget.bodyTapMode) {
          await _eval('window.setBodyTapMode && window.setBodyTapMode(true)');
        }
        if (widget.autoFocusCameraOnce) {
          await _eval('window.focusCamera && window.focusCamera()');
        }
        if (mounted) setState(() => _loading = false);
        widget.onReady?.call(null);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (mounted) {
      setState(() {
        _webglError = true;
        _loading = false;
      });
      widget.onReady?.call('The 3D viewer didn’t finish loading.');
    }
  }

  /// Every bridge call below is feature-detected (`window.fn && window.fn(...)`)
  /// so a stale `anatomy_scene.bundle.js` — someone pulled the Dart change
  /// without re-running `npm run build:anatomy` — degrades instead of throwing
  /// into a WebView nobody is watching. This turns the same situation into one
  /// log line rather than a silently wrong render.
  Future<void> _checkVersion() async {
    const expected = 'anatomy-scene-v1';
    final raw = await _controller?.evaluateJavascript(
      source: 'window.__viewerVersion || ""',
    );
    final actual = raw?.toString() ?? '';
    if (actual != expected) {
      debugPrint(
        '[AnatomyScene] bundle version mismatch: expected "$expected", '
        'got "$actual". Run `npm run build:anatomy` in tool/kinetic_chain_viewer.',
      );
    }
  }

  Future<void> _applyViewOptions() async {
    final opts = <String, dynamic>{
      // 'dot' is PadAnatomyView's name for the same thing.
      'padStyle': widget.padStyle == 'dot' ? 'badge' : widget.padStyle,
      'colorBySet': widget.colorBySet,
      'showSetLinks': widget.showSetLinks,
      'transparentBody': widget.transparentBody,
      'focusSetIndex': widget.focusSetIndex,
      'dimUnselected': widget.dimUnselected,
    };
    await _eval(
      'window.setViewOptions && window.setViewOptions(${jsonEncode(opts)})',
    );
  }

  Future<void> _renderMarkers() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: 'window.renderAnatomyMarkers && '
          'window.renderAnatomyMarkers(${jsonEncode(_adapted)})',
    );
    // Ask which pads no tier could place, so the caller can badge those rows
    // instead of implying a pad was drawn.
    final raw = await controller.evaluateJavascript(
      source: 'JSON.stringify(window.__unmapped || [])',
    );
    final unmapped = _parseUnmapped(raw);
    if (unmapped != null) widget.onUnmapped?.call(unmapped);
  }

  Future<void> _applyActiveMarkers() async {
    await _eval(
      'window.setActiveMarkers && '
      'window.setActiveMarkers(${jsonEncode(_adaptedActive)})',
    );
  }

  Future<void> _applyHighlight() async {
    // Muscle style colours from the markers themselves, so a flat list would
    // fight it.
    if (widget.padStyle == 'muscle') return;
    await _eval(
      'window.setHighlight && '
      'window.setHighlight(${jsonEncode(widget.highlightMuscles)})',
    );
  }

  Future<void> _applyBackground() async {
    final css = widget.backgroundCss;
    final arg = css == null ? 'null' : jsonEncode(css);
    await _eval('window.setBackground && window.setBackground($arg)');
  }

  Future<Map<String, dynamic>?> _viewerState() async {
    final raw = await _controller?.evaluateJavascript(
      source: 'window.getViewerState ? window.getViewerState() : "null"',
    );
    if (raw == null) return null;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A bundle without getViewerState — nothing to report.
    }
    return null;
  }

  void _onAnatomyEvent(List<dynamic> args) {
    if (args.isEmpty) return;
    final payload = args.first;
    if (payload is! Map) return;
    final map = Map<String, dynamic>.from(payload);
    switch (map['type']) {
      case 'pick':
        final marker = map['marker'];
        // Hand back the caller's ORIGINAL marker, not the adapted one, so
        // screens keep working in their own vocabulary.
        widget.onRegionPick?.call(_originalFor(marker));
        break;
      case 'bodyTap':
        widget.onBodyTap?.call(map);
        break;
      case 'muscle':
        widget.onMuscleSelected?.call(map);
        break;
    }
  }

  Map<String, dynamic>? _originalFor(Object? adapted) {
    if (adapted is! Map) return null;
    final index = adapted['__mobileIndex'];
    if (index is int && index >= 0 && index < widget.markers.length) {
      return widget.markers[index];
    }
    return null;
  }

  Future<void> _eval(String js) async {
    await _controller?.evaluateJavascript(source: js);
  }

  static Set<String>? _parseUnmapped(dynamic raw) {
    if (raw == null) return null;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List) return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      // A bundle without `__unmapped` — nothing to report.
    }
    return null;
  }

  static bool _sameMaps(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) =>
      jsonEncode(a) == jsonEncode(b);

  static bool _sameStrings(List<String> a, List<String> b) =>
      a.length == b.length && !a.asMap().entries.any((e) => b[e.key] != e.value);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_serverReady && _serverError == null)
          Positioned.fill(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('http://localhost:8080/anatomy_scene.html'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                hardwareAcceleration: true,
                useHybridComposition: true,
                // Transparent composition costs a real per-frame blend on
                // Android. A caller that supplies an opaque colour is telling us
                // it does not need to see through the canvas, so drop it.
                transparentBackground: widget.backgroundCss == null,
                supportZoom: false,
                // Deliberately NOT setting disableVerticalScroll /
                // disableHorizontalScroll. They look like the right way to stop
                // the WebView competing with the canvas, but on Android they can
                // swallow touch-move before it reaches the page — which kills
                // orbiting outright. The page already handles this correctly
                // with `touch-action: none` on the canvas, and the older
                // PadAnatomyView never needed them either.
                overScrollMode: OverScrollMode.NEVER,
                verticalScrollBarEnabled: false,
                horizontalScrollBarEnabled: false,
              ),
              // WITHOUT THIS THERE IS NO VERTICAL ROTATION.
              //
              // On the pad map this stage sits inside a vertically scrolling
              // ListView. Flutter's gesture arena hands vertical drags to the
              // nearest scrollable, so they scroll the page and never reach the
              // WebView — horizontal orbit works, vertical silently does not.
              // Claiming the gesture eagerly gives the 3D canvas every drag that
              // starts on it.
              //
              // The trade: you can no longer scroll the page by dragging across
              // the model. That is the right call for an interactive stage, and
              // it is why the fullscreen button next to it earns its place.
              gestureRecognizers: {
                const Factory<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              onWebViewCreated: (c) {
                _controller = c;
                c.addJavaScriptHandler(
                  handlerName: 'anatomyEvent',
                  callback: _onAnatomyEvent,
                );
              },
              onLoadStop: (c, url) => _injectWhenReady(),
              onConsoleMessage: (c, msg) {
                debugPrint('[AnatomyScene] ${msg.messageLevel}: ${msg.message}');
              },
            ),
          ),
        if (_loading && _serverError == null)
          Center(child: CircularProgressIndicator(color: ThemeConstants.accent)),
        if (_serverError != null || _webglError)
          Positioned.fill(
            child: PadAnatomyFallback(
              message: _serverError != null
                  ? 'Couldn’t start the 3D viewer.\n$_serverError'
                  : '3D is not supported on this device.',
            ),
          ),
      ],
    );
  }
}
