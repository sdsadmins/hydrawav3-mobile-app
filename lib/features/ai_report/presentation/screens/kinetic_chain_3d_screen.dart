import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/theme_constants.dart';

/// Full-screen 3D "Kinetic Chain" viewer for a single AI pattern (A or B),
/// mirroring the web `ZAnatomyViewer` + its report-modal chrome. The WebView
/// (`assets/3d/kinetic_chain.html`, served over `http://localhost` so WebGL +
/// the Draco WASM worker can load) renders ONLY the 3D canvas on a white
/// background; the header guidance, muscle-type toggle chips, zoom/reset/labels
/// controls, color legend and numbered Pathway list are native Flutter widgets
/// that drive the viewer through the `window.*` JS bridge (see viewer.src.js).
class KineticChain3DScreen extends StatefulWidget {
  final String patternLabel;
  final Map<String, dynamic> payload;

  const KineticChain3DScreen({
    super.key,
    required this.patternLabel,
    required this.payload,
  });

  @override
  State<KineticChain3DScreen> createState() => _KineticChain3DScreenState();
}

class _KineticChain3DScreenState extends State<KineticChain3DScreen> {
  // Role colors — verbatim from the web ANATOMY_COLORS so the legend/chips
  // match the highlighted meshes exactly.
  static const _cPrimary = Color(0xFFEF4444);
  static const _cSecondary = Color(0xFFF59E0B);
  static const _cStabilizing = Color(0xFF10B981);
  static const _cChain = Color(0xFF06B6D4); // chain flow line (cyan)
  static const _cSpinal = Color(0xFF8B5CF6); // spinal segments (purple)
  static const _darkTeal = Color(0xFF132A35);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF6B7280);

  // A single shared server for the whole app; `shared: true` makes start()
  // idempotent across screen re-entries.
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

  // Control state (web ZAnatomyViewer defaults).
  bool _showPrimary = true;
  bool _showSecondary = true;
  bool _showStabilizing = true;
  bool _showChain = false;
  bool _showSpine = false;
  bool _showLabels = false;

  List<String> get _pathway =>
      ((widget.payload['kineticChainPathway'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();

  List<String> get _spinal =>
      ((widget.payload['spinalSegments'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      if (!_server.isRunning()) {
        await _server.start();
      }
      if (mounted) setState(() => _serverReady = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverError = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Poll `window.__ready`, then inject the pattern data. The viewer sets
  /// `__ready` once the GLB is parsed (or immediately if WebGL is unavailable).
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
          }
          return;
        }
        await controller.evaluateJavascript(
          source: 'window.renderPattern(${jsonEncode(widget.payload)})',
        );
        // Push the initial control state (matches the defaults above).
        await controller.evaluateJavascript(source: _visibilityJs());
        await controller.evaluateJavascript(
          source: 'window.setChain($_showChain); window.setLabels($_showLabels);',
        );
        if (mounted) setState(() => _loading = false);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Timed out waiting for the model — surface the fallback rather than hang.
    if (mounted) {
      setState(() {
        _webglError = true;
        _loading = false;
      });
    }
  }

  String _visibilityJs() {
    final v = jsonEncode({
      'primary': _showPrimary,
      'secondary': _showSecondary,
      'stabilizing': _showStabilizing,
      'spinal': _showSpine,
    });
    return 'window.setGroupVisibility($v)';
  }

  void _eval(String js) {
    _controller?.evaluateJavascript(source: js);
  }

  void _toggleGroup(String key) {
    setState(() {
      switch (key) {
        case 'primary':
          _showPrimary = !_showPrimary;
          break;
        case 'secondary':
          _showSecondary = !_showSecondary;
          break;
        case 'stabilizing':
          _showStabilizing = !_showStabilizing;
          break;
        case 'spinal':
          _showSpine = !_showSpine;
          break;
      }
    });
    _eval(_visibilityJs());
  }

  void _toggleChain() {
    setState(() => _showChain = !_showChain);
    _eval('window.setChain($_showChain)');
  }

  void _toggleLabels() {
    setState(() => _showLabels = !_showLabels);
    _eval('window.setLabels($_showLabels)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: ThemeConstants.background,
        foregroundColor: ThemeConstants.textPrimary,
        elevation: 0,
        title: Text(
          widget.patternLabel,
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
    if (_serverError != null) {
      return _fallback('Couldn\'t start the 3D viewer.\n$_serverError');
    }
    if (_webglError) {
      return _fallback('3D is not supported on this device.');
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (_serverReady)
                Positioned.fill(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri('http://localhost:8080/kinetic_chain.html'),
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
                      debugPrint(
                          '[KineticChain3D] ${msg.messageLevel}: ${msg.message}');
                    },
                  ),
                ),
              // Controls (top-right): zoom cluster + Labels, then muscle chips.
              Positioned(top: 10, right: 10, child: _controls()),
              if (_loading)
                Center(
                  child: CircularProgressIndicator(
                    color: ThemeConstants.accent,
                  ),
                ),
            ],
          ),
        ),
        _bottomPanel(),
      ],
    );
  }

  // --- Top-right controls ----------------------------------------------------
  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _zoomCluster(),
            const SizedBox(width: 6),
            _toggleChip(
              label: _showLabels ? 'Label On' : 'Label Off',
              active: _showLabels,
              activeColor: _darkTeal,
              onTap: _toggleLabels,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 5,
          runSpacing: 5,
          children: [
            _toggleChip(
              label: 'Primary',
              active: _showPrimary,
              activeColor: _cPrimary,
              dot: _cPrimary,
              onTap: () => _toggleGroup('primary'),
            ),
            _toggleChip(
              label: 'Secondary',
              active: _showSecondary,
              activeColor: _cSecondary,
              dot: _cSecondary,
              onTap: () => _toggleGroup('secondary'),
            ),
            _toggleChip(
              label: 'Stabilizing',
              active: _showStabilizing,
              activeColor: _cStabilizing,
              dot: _cStabilizing,
              onTap: () => _toggleGroup('stabilizing'),
            ),
            _toggleChip(
              label: 'Chain',
              active: _showChain,
              activeColor: _cChain,
              dot: _cChain,
              onTap: _toggleChain,
            ),
            if (_spinal.isNotEmpty)
              _toggleChip(
                label: 'Spine',
                active: _showSpine,
                activeColor: _cSpinal,
                dot: _cSpinal,
                onTap: () => _toggleGroup('spinal'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _zoomCluster() {
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.add, () => _eval('window.zoomIn()')),
            btn(Icons.remove, () => _eval('window.zoomOut()')),
            btn(Icons.refresh, () => _eval('window.resetView()'), border: false),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
    Color? dot,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? activeColor : const Color(0xFFE5E7EB),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? Colors.white : dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                color: active ? Colors.white : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Bottom legend + pathway ----------------------------------------------
  Widget _bottomPanel() {
    final pathway = _pathway;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              const _LegendDot(color: _cPrimary, label: 'Primary'),
              const _LegendDot(color: _cSecondary, label: 'Secondary'),
              const _LegendDot(color: _cStabilizing, label: 'Stabilizing'),
              const _LegendDot(color: _cChain, label: 'Chain Flow'),
              if (_spinal.isNotEmpty)
                const _LegendDot(color: _cSpinal, label: 'Spine'),
            ],
          ),
          if (pathway.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      'PATHWAY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: _muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (var i = 0; i < pathway.length; i++) ...[
                    _pathwayPill(i + 1, pathway[i]),
                    if (i < pathway.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward,
                            size: 13, color: _cChain),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pathwayPill(int number, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA5F3FC)), // cyan-200
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _cChain,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _ink,
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
