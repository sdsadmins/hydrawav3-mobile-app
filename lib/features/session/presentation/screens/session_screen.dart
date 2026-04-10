import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/logger.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../services/session_engine.dart';
import '../../domain/session_model.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String protocolId;
  final List<String> deviceIds;
  /// 'ble' or 'wifi'
  final String transport;
  const SessionScreen({
    super.key,
    required this.protocolId,
    required this.deviceIds,
    this.transport = 'ble',
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  bool _loadedOnce = false;
  ProviderSubscription? _protocolSub;

  @override
  void initState() {
    super.initState();
    appLogger.i(
      'SessionScreen: init(protocolId=${widget.protocolId}, transport=${widget.transport}, deviceIds=${widget.deviceIds})',
    );
    // Ensure engine knows the correct transport/deviceIds immediately, before
    // protocol detail finishes loading (prevents BLE-start aborts in WiFi mode).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sessionEngineProvider.notifier).prepareSession(
            deviceIds: widget.deviceIds,
            transport: widget.transport == 'wifi'
                ? SessionTransport.wifi
                : SessionTransport.ble,
          );
    });

    // IMPORTANT: `listenManual` may not fire immediately when the provider
    // already has a cached value. Fetch once explicitly so totalDuration and
    // auto-start always work (especially for WiFi sessions).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _loadedOnce) return;
      try {
        final protocol = await ref.read(
          protocolDetailProvider(widget.protocolId).future,
        );
        if (!mounted || _loadedOnce) return;
        final ctrl = ref.read(sessionEngineProvider.notifier);
        ctrl.loadSession(
          protocol,
          widget.deviceIds,
          transport: widget.transport == 'wifi'
              ? SessionTransport.wifi
              : SessionTransport.ble,
        );
        _loadedOnce = true;
        ctrl.start();
      } catch (e) {
        appLogger.e('SessionScreen: failed to load protocol for session: $e');
      }
    });
    // Listen once for the protocol details, then load + start the session.
    _protocolSub = ref.listenManual(
      protocolDetailProvider(widget.protocolId),
      (previous, next) {
        if (_loadedOnce) return;
        next.whenData((protocol) {
          final ctrl = ref.read(sessionEngineProvider.notifier);
          ctrl.loadSession(
            protocol,
            widget.deviceIds,
            transport: widget.transport == 'wifi'
                ? SessionTransport.wifi
                : SessionTransport.ble,
          );
          _loadedOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ctrl.start();
          });
        });
      },
    );
  }

  @override
  void dispose() {
    _protocolSub?.close();
    ref.read(sessionEngineProvider.notifier).reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(sessionEngineProvider);
    final protocolAsync = ref.watch(protocolDetailProvider(widget.protocolId));

    final timer = engine.timer;
    final status = engine.status;
    final ctrl = ref.read(sessionEngineProvider.notifier);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('Session'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (status == SessionStatus.running || status == SessionStatus.paused) {
              ctrl.stop();
            }
            ctrl.reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Protocol name
              protocolAsync.when(
                data: (p) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.science_rounded, color: ThemeConstants.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(p.templateName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    ],
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const Spacer(),

              // Timer ring with glow
              Container(
                decoration: status == SessionStatus.running
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.12), blurRadius: 40, spreadRadius: 5),
                        ],
                      )
                    : null,
                child: SizedBox(
                width: 240, height: 240,
                child: CustomPaint(
                  painter: _TimerRing(progress: timer.progress, active: status == SessionStatus.running),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(timer.remaining.formatted, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -2)),
                        Text('remaining', style: TextStyle(fontSize: 13, color: ThemeConstants.textTertiary)),
                      ],
                    ),
                  ),
                ),
              ),
              ),
              const SizedBox(height: 16),

              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              if (engine.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  engine.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ThemeConstants.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              if (timer.totalCycles > 0) ...[
                const SizedBox(height: 8),
                Text('Cycle ${timer.currentCycleIndex + 1}/${timer.totalCycles}', style: const TextStyle(color: ThemeConstants.textTertiary, fontSize: 13)),
              ],

              const Spacer(),

              // Controls
              _buildControls(status, ctrl),
              const SizedBox(height: 24),

              // Device status
              if (widget.deviceIds.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: ThemeConstants.success, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(
                        widget.transport == 'wifi'
                            ? '${widget.deviceIds.length} WiFi device(s) selected'
                            : '${widget.deviceIds.length} device(s) connected',
                        style: const TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(SessionStatus status, SessionEngine ctrl) {
    return switch (status) {
      SessionStatus.idle => SizedBox(
        height: 52,
        width: double.infinity,
        child: ElevatedButton(
          // WiFi sessions auto-start once protocol loads; don't allow manual start.
          onPressed: widget.transport == 'wifi' ? null : () => ctrl.start(),
          child: Text(widget.transport == 'wifi' ? 'Starting…' : 'Start Session'),
        ),
      ),
      SessionStatus.running => Row(children: [
          Expanded(child: SizedBox(height: 52, child: OutlinedButton(onPressed: () => ctrl.pause(), child: const Text('Pause')))),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 52, child: ElevatedButton(onPressed: () => ctrl.stop(), style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.error), child: const Text('Stop')))),
        ]),
      SessionStatus.paused => Row(children: [
          Expanded(child: SizedBox(height: 52, child: ElevatedButton(onPressed: () => ctrl.resume(), child: const Text('Resume')))),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 52, child: ElevatedButton(onPressed: () => ctrl.stop(), style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.error), child: const Text('Stop')))),
        ]),
      SessionStatus.stopped || SessionStatus.completed => SizedBox(height: 52, width: double.infinity, child: ElevatedButton(onPressed: () { ctrl.reset(); context.pop(); }, style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.success), child: const Text('Done'))),
    };
  }

  Color _statusColor(SessionStatus s) => switch (s) {
    SessionStatus.idle => ThemeConstants.textTertiary,
    SessionStatus.running => ThemeConstants.success,
    SessionStatus.paused => ThemeConstants.warning,
    SessionStatus.stopped => ThemeConstants.error,
    SessionStatus.completed => ThemeConstants.success,
  };

  String _statusLabel(SessionStatus s) => switch (s) {
    SessionStatus.idle => 'Ready',
    SessionStatus.running => 'Running',
    SessionStatus.paused => 'Paused',
    SessionStatus.stopped => 'Stopped',
    SessionStatus.completed => 'Completed',
  };
}

class _TimerRing extends CustomPainter {
  final double progress;
  final bool active;
  _TimerRing({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final bg = Paint()..color = ThemeConstants.border..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()..color = ThemeConstants.accent..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _TimerRing old) => progress != old.progress;
}
