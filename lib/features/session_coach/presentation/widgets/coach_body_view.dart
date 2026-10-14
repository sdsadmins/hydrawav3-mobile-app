import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../../core/utils/logger.dart';

/// Lets a parent drive the camera (the full-screen page's Front/Back buttons).
class CoachBodyController {
  _CoachBodyViewState? _s;
  void setView(String view) => _s?._setView(view);
}

/// The Session Coach's 3D body: the SAME Z-Anatomy viewer the admin places the
/// pads with on the website (`Hydrawav3-ai/public/anatomy-viewer`, copied to
/// `assets/3d/coach_viewer.html` + `coach_viewer.bundle.js`), opened read-only.
/// Markers go in exactly as the server stored them — same model, same
/// coordinates — so a pad lands where the admin put it.
///
/// Deliberately separate from `AnatomySceneView` / `PadAnatomyView`: those
/// drive a different build of the viewer and are left untouched.
class CoachBodyView extends StatefulWidget {
  /// The selected set's markers (`{id, type, position, normal, …}`).
  final List<Map<String, dynamic>> markers;

  /// Top-right button (the card's expand). Hidden when null.
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback? onAction;

  /// The view switch + action overlay. Off on the full-screen page, which
  /// draws its own controls.
  final bool showControls;

  /// The Front/Back/Left/Right strip (off on the card's small view).
  final bool showViewSwitch;

  /// Canvas colour (`#rrggbb`); the viewer's own navy when null.
  final String? background;

  final CoachBodyController? controller;

  const CoachBodyView({
    super.key,
    required this.markers,
    this.actionIcon = Icons.open_in_full_rounded,
    this.actionLabel = 'Expand',
    this.onAction,
    this.showControls = true,
    this.showViewSwitch = true,
    this.background,
    this.controller,
  });

  @override
  State<CoachBodyView> createState() => _CoachBodyViewState();
}

class _CoachBodyViewState extends State<CoachBodyView> {
  // Same localhost server the other 3D surfaces use; `shared: true` makes a
  // concurrent bind legal.
  static final InAppLocalhostServer _server = InAppLocalhostServer(
    documentRoot: 'assets/3d',
    port: 8080,
    shared: true,
  );

  InAppWebViewController? _controller;
  bool _serverReady = false;
  bool _ready = false;
  String? _error;
  String _view = 'front';

  @override
  void initState() {
    super.initState();
    widget.controller?._s = this;
    _startServer();
  }

  @override
  void dispose() {
    if (widget.controller?._s == this) widget.controller?._s = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(CoachBodyView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._s = null;
      widget.controller?._s = this;
    }
    if (_ready && jsonEncode(old.markers) != jsonEncode(widget.markers)) {
      _loadMarkers();
    }
  }

  Future<void> _startServer() async {
    try {
      if (!_server.isRunning()) await _server.start();
      if (mounted) setState(() => _serverReady = true);
    } catch (e) {
      if (_server.isRunning()) {
        if (mounted) setState(() => _serverReady = true);
        return;
      }
      if (mounted) setState(() => _error = 'Couldn’t start the 3D viewer.');
    }
  }

  Future<void> _eval(String js) async {
    try {
      await _controller?.evaluateJavascript(source: js);
    } catch (_) {}
  }

  /// The viewer reports `ready` through `getState()` once the model is parsed.
  Future<void> _whenReady() async {
    for (var i = 0; i < 150 && mounted; i++) {
      final raw = await _controller?.evaluateJavascript(
          source: 'window.getState ? window.getState() : null');
      if (raw is String && raw.contains('"ready":true')) {
        await _eval('window.setReadOnly(true)');
        await _eval('window.setPalette(false)');
        if (widget.background != null) {
          await _eval(
              "window.setBackground && window.setBackground('${widget.background}')");
        }
        if (!mounted) return;
        setState(() => _ready = true);
        await _loadMarkers();
        if (_view != 'front') await _eval("window.setView('$_view')");
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (mounted && !_ready) setState(() => _error = '3D model didn’t load.');
  }

  Future<void> _loadMarkers() =>
      _eval('window.loadMarkers(${jsonEncode(widget.markers)})');

  void _setView(String v) {
    setState(() => _view = v);
    if (_ready) _eval("window.setView('$v')");
  }

  Color get _bg {
    final hex = widget.background;
    if (hex == null || hex.length != 7) return const Color(0xFF0A192F);
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return ColoredBox(
      color: _bg,
      child: Stack(
        children: [
          if (_serverReady && _error == null)
            Positioned.fill(
              child: Opacity(
                // Hidden until the background is applied, so the viewer's
                // navy never flashes on the light page.
                opacity: _ready ? 1 : 0,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('http://localhost:8080/coach_viewer.html'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    hardwareAcceleration: true,
                    useHybridComposition: true,
                    transparentBackground: true,
                    supportZoom: false,
                    overScrollMode: OverScrollMode.NEVER,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                  ),
                  // The body orbits on drag; without this the page scroll
                  // steals vertical drags.
                  gestureRecognizers: {
                    const Factory<EagerGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                  onWebViewCreated: (c) => _controller = c,
                  onLoadStop: (c, url) => _whenReady(),
                  onConsoleMessage: (c, msg) =>
                      appLogger.i('[CoachBody JS] ${msg.message}'),
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8892B0)),
                ),
              ),
            )
          else if (!_ready)
            Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: p.copper),
              ),
            ),
          if (widget.showControls) ...[
            // front / back / left / right — the admin page's view switch.
            if (widget.showViewSwitch)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xE6112240),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF233554)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final v in const ['front', 'back', 'left', 'right'])
                        _ViewChip(
                          label: v[0].toUpperCase() + v.substring(1),
                          on: _view == v,
                          onTap: _ready ? () => _setView(v) : null,
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.onAction != null)
              Positioned(
                right: 10,
                top: 10,
                child: Semantics(
                  button: true,
                  label: widget.actionLabel,
                  child: Material(
                    color: const Color(0xB3606060),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: widget.onAction,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .25)),
                        ),
                        child: Icon(widget.actionIcon,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const _ViewChip({required this.label, required this.on, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFB87333) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: on ? Colors.white : const Color(0xFF8892B0),
          ),
        ),
      ),
    );
  }
}

// ── full screen ─────────────────────────────────────────────────────────────

/// One set as the full-screen page shows it.
class CoachFullSet {
  final String name;
  final List<Map<String, dynamic>> markers;
  final List<String> sunMuscles;
  final List<String> moonMuscles;

  /// The unit this set is on, or null when it isn't in the session yet.
  final String? unitName;
  final String protocolName;
  final String duration;

  const CoachFullSet({
    required this.name,
    required this.markers,
    required this.sunMuscles,
    required this.moonMuscles,
    required this.unitName,
    required this.protocolName,
    required this.duration,
  });
}

/// The coach's 3D body full screen (prototype v6 "pad full"): title, set
/// pills, Front/Back/Left/Right, and the selected set's card underneath.
class CoachBodyFullScreen extends StatefulWidget {
  final String title;
  final List<CoachFullSet> sets;
  final int initialIndex;

  /// Test seam: widget tests can't host the WebView.
  final Widget Function(List<Map<String, dynamic>> markers)? bodyBuilder;

  const CoachBodyFullScreen({
    super.key,
    required this.title,
    required this.sets,
    this.initialIndex = 0,
    this.bodyBuilder,
  });

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<CoachFullSet> sets,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CoachBodyFullScreen(
          title: title, sets: sets, initialIndex: initialIndex),
    ));
  }

  @override
  State<CoachBodyFullScreen> createState() => _CoachBodyFullScreenState();
}

class _CoachBodyFullScreenState extends State<CoachBodyFullScreen> {
  late int _i = widget.initialIndex.clamp(0, widget.sets.length - 1);
  String _view = 'front';
  final _body = CoachBodyController();

  void _setView(String v) {
    setState(() => _view = v);
    _body.setView(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final sets = widget.sets;
    final set = sets[_i];
    final assigned = sets.where((s) => s.unitName != null).length;
    final side =
        HwTablet.sidePadding(context, column: HwTablet.wide, phone: 16);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 10, side, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── header ────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: p.ink)),
                        const SizedBox(height: 2),
                        Text(
                          '$assigned of ${sets.length} '
                          '${sets.length == 1 ? 'set' : 'sets'} assigned',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: Material(
                      color: p.card,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: p.cardline),
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 24, color: p.ink2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── the body ──────────────────────────────────────────────
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: p.cardline),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: widget.bodyBuilder?.call(set.markers) ??
                              CoachBodyView(
                                markers: set.markers,
                                showControls: false,
                                background: '#F4EEE8',
                                controller: _body,
                              ),
                        ),
                        // set pills
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 110,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var k = 0; k < sets.length; k++)
                                _SetPill(
                                  label: 'Set ${k + 1}',
                                  sub: sets[k].unitName ?? 'Off',
                                  on: k == _i,
                                  onTap: () => setState(() => _i = k),
                                ),
                            ],
                          ),
                        ),
                        // views
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Column(
                            children: [
                              for (final v in const [
                                'front',
                                'back',
                                'left',
                                'right'
                              ]) ...[
                                _ViewButton(
                                  label: v[0].toUpperCase() + v.substring(1),
                                  on: _view == v,
                                  onTap: () => _setView(v),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── the selected set ──────────────────────────────────────
              _SetCard(index: _i, set: set),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetPill extends StatelessWidget {
  final String label;
  final String sub;
  final bool on;
  final VoidCallback onTap;
  const _SetPill(
      {required this.label,
      required this.sub,
      required this.on,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: '$label, $sub',
      child: Material(
        color: on ? p.tanSoft : const Color(0xB3606060),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: on ? p.copper : Colors.white.withValues(alpha: .25)),
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: on ? p.ink : Colors.white)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: on ? p.ink2 : Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ViewButton(
      {required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? p.copper : const Color(0xB3606060),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 84,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  final int index;
  final CoachFullSet set;
  const _SetCard({required this.index, required this.set});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final muscles = <String>{...set.sunMuscles, ...set.moonMuscles}.join(' · ');
    const dim = Color(0xFFD9D2CB);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: p.heroGrad,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.copper,
              ),
              child: Text('${index + 1}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A1A12))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    muscles.isEmpty ? set.name : muscles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  if (set.sunMuscles.isNotEmpty)
                    _PadText(sun: true, text: set.sunMuscles.join(', ')),
                  if (set.moonMuscles.isNotEmpty)
                    _PadText(sun: false, text: set.moonMuscles.join(', ')),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (set.protocolName.isNotEmpty) set.protocolName,
                      set.unitName ?? 'Not assigned',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: dim),
                  ),
                ],
              ),
            ),
            if (set.duration.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(set.duration,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ],
        ),
      ),
    );
  }
}

class _PadText extends StatelessWidget {
  final bool sun;
  final String text;
  const _PadText({required this.sun, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(sun ? Icons.wb_twilight_rounded : Icons.nightlight_round,
              size: 15, color: const Color(0xFFD9D2CB)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFFD9D2CB))),
          ),
        ],
      ),
    );
  }
}
