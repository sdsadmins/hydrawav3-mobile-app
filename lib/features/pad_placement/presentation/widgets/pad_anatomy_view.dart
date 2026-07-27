import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/theme_constants.dart';

/// The Z-Anatomy pad stage — one copy of the WebView bridge, shared by the
/// recovery viewer (`PadPlacement3DScreen`) and the performance pad map.
///
/// The viewer itself is `assets/3d/pad_placement.html` +
/// `pad_placement.bundle.js` (built from `tool/kinetic_chain_viewer/
/// pad_placement.src.js`), served over the bundled localhost server so WebGL and
/// the Draco worker can load. This widget owns: starting the server, waiting for
/// `window.__ready`, injecting markers, and forwarding label/view/zoom calls.
///
/// Markers are declarative — hand it a new list and it re-renders. Pads the
/// viewer could not place are reported through [onUnmapped] so the caller can
/// badge them instead of pretending they were drawn.
class PadAnatomyView extends StatefulWidget {
  /// Marker maps as produced by `PadPlacementViewData.markers()`.
  final List<Map<String, dynamic>> markers;

  /// 'front' | 'back' | 'left' | 'right'.
  final String view;
  final bool showLabels;

  /// Muscles to tint behind the pads (the GLB is per-muscle). Empty = plain skin.
  final List<String> highlightMuscles;

  final PadAnatomyController? controller;

  /// `setIndex:role` keys the viewer could not place after both tiers.
  final ValueChanged<Set<String>>? onUnmapped;

  /// Fired once the stage is live, or with an error message when it is not.
  final ValueChanged<String?>? onReady;

  const PadAnatomyView({
    super.key,
    required this.markers,
    this.view = 'front',
    this.showLabels = true,
    this.highlightMuscles = const [],
    this.controller,
    this.onUnmapped,
    this.onReady,
  });

  @override
  State<PadAnatomyView> createState() => _PadAnatomyViewState();
}

/// Imperative hooks the surrounding chrome needs (zoom cluster, reset).
class PadAnatomyController {
  _PadAnatomyViewState? _state;

  void zoomIn() => _state?._eval('window.zoomIn()');
  void zoomOut() => _state?._eval('window.zoomOut()');
  void reset() => _state?._eval('window.resetView()');
}

class _PadAnatomyViewState extends State<PadAnatomyView> {
  // One shared server across screens and re-entries (`shared: true` makes
  // start() idempotent).
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

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _startServer();
  }

  @override
  void didUpdateWidget(PadAnatomyView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (_loading || _webglError) return;
    if (!_sameMarkers(old.markers, widget.markers)) _renderMarkers();
    if (old.view != widget.view) _eval("window.setView('${widget.view}')");
    if (old.showLabels != widget.showLabels) {
      _eval('window.setLabels(${widget.showLabels})');
    }
    if (!_sameStrings(old.highlightMuscles, widget.highlightMuscles)) {
      _applyHighlight();
    }
  }

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
      // Another screen may already hold the port — a running server is fine.
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

  /// Poll `window.__ready`, then inject. The viewer sets `__ready` once the GLB
  /// is parsed — or immediately when WebGL is unavailable.
  Future<void> _injectWhenReady() async {
    final controller = _controller;
    if (controller == null) return;
    for (var i = 0; i < 100; i++) {
      final ready = await controller.evaluateJavascript(
        source: 'window.__ready === true',
      );
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
        await _renderMarkers();
        await controller.evaluateJavascript(
          source: 'window.setLabels(${widget.showLabels})',
        );
        if (widget.view != 'front') {
          await controller.evaluateJavascript(
            source: "window.setView('${widget.view}')",
          );
        }
        await _applyHighlight();
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

  Future<void> _renderMarkers() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: 'window.renderPadPlacement(${jsonEncode(widget.markers)})',
    );
    // Ask the viewer which pads it could not place (tier-2 geometry misses) so
    // the list can badge them.
    final raw = await controller.evaluateJavascript(
      source: 'JSON.stringify(window.__unmapped || [])',
    );
    final unmapped = _parseUnmapped(raw);
    if (unmapped != null) widget.onUnmapped?.call(unmapped);
  }

  Future<void> _applyHighlight() async {
    final controller = _controller;
    if (controller == null) return;
    // Older bundles don't have setHighlight — guard so they keep working.
    await controller.evaluateJavascript(
      source: 'window.setHighlight && '
          'window.setHighlight(${jsonEncode(widget.highlightMuscles)})',
    );
  }

  static Set<String>? _parseUnmapped(dynamic raw) {
    if (raw == null) return null;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {
      // A bundle without `__unmapped` — nothing to report.
    }
    return null;
  }

  void _eval(String js) => _controller?.evaluateJavascript(source: js);

  static bool _sameMarkers(
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
                url: WebUri('http://localhost:8080/pad_placement.html'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                hardwareAcceleration: true,
                useHybridComposition: true,
                transparentBackground: true,
                supportZoom: false,
              ),
              onWebViewCreated: (c) => _controller = c,
              onLoadStop: (c, url) => _injectWhenReady(),
              onConsoleMessage: (c, msg) {
                debugPrint('[PadAnatomy] ${msg.messageLevel}: ${msg.message}');
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

/// The no-3D state. The written per-set placement list stays readable beneath it,
/// so a device without WebGL still gets usable guidance.
class PadAnatomyFallback extends StatelessWidget {
  final String message;
  const PadAnatomyFallback({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
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
                color: Color(0xFF6B7280),
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
