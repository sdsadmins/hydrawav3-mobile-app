import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/glass_container.dart';
import '../../../../core/utils/extensions.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../services/session_engine.dart';
import '../../domain/session_model.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String protocolId;
  final List<String> deviceIds;

  const SessionScreen({
    super.key,
    required this.protocolId,
    required this.deviceIds,
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(sessionEngineProvider);
    final protocolAsync = ref.watch(protocolDetailProvider(widget.protocolId));

    // Load protocol into engine when ready
    protocolAsync.whenData((protocol) {
      if (engineState.protocol == null) {
        ref.read(sessionEngineProvider.notifier).loadSession(
              protocol,
              widget.deviceIds,
            );
      }
    });

    // Manage pulse animation based on state
    if (engineState.status == SessionStatus.running) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }

    final timer = engineState.timer;
    final status = engineState.status;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ThemeConstants.darkTeal, Color(0xFF0A1E27)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _entryController,
              curve: Curves.easeOut,
            ),
            child: Column(
              children: [
                // ⬆️ Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (status == SessionStatus.running ||
                              status == SessionStatus.paused) {
                            ref.read(sessionEngineProvider.notifier).stop();
                          }
                          context.pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      Text(
                        '🎯 Session',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(width: 42),
                    ],
                  ),
                ),

                // 📋 Protocol name
                protocolAsync.when(
                  data: (p) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GlassContainer(
                      opacity: 0.06,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.science_rounded,
                              color: ThemeConstants.tanLight, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            p.templateName,
                            style: const TextStyle(
                              color: ThemeConstants.tanLight,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const Spacer(),

                // ⏱️ Premium Timer
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => Transform.scale(
                    scale: status == SessionStatus.running
                        ? _pulseAnim.value
                        : 1.0,
                    child: child,
                  ),
                  child: _buildTimer(context, timer, status),
                ),

                const SizedBox(height: 16),

                // Status badge
                _StatusBadge(status: status),

                // Cycle info
                if (timer.totalCycles > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '🔄 Cycle ${timer.currentCycleIndex + 1}/${timer.totalCycles}  ·  Rep ${timer.currentRepetition + 1}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),

                const Spacer(),

                // 🎮 Control buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _buildControls(status),
                ),

                const SizedBox(height: 24),

                // 📡 Device status
                if (widget.deviceIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GlassContainer(
                      opacity: 0.06,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: ThemeConstants.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '📡 ${widget.deviceIds.length} device(s) connected',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimer(BuildContext context, TimerState timer, SessionStatus status) {
    return SizedBox(
      width: 260,
      height: 260,
      child: CustomPaint(
        painter: _TimerPainter(
          progress: timer.progress,
          isRunning: status == SessionStatus.running,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timer.remaining.formatted,
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -2,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                'remaining ⏳',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(SessionStatus status) {
    final engine = ref.read(sessionEngineProvider.notifier);

    switch (status) {
      case SessionStatus.idle:
        return _SessionButton(
          label: '▶️  Start Session',
          color: ThemeConstants.copper,
          onTap: () => engine.start(),
        );
      case SessionStatus.running:
        return Row(
          children: [
            Expanded(
              child: _SessionButton(
                label: '⏸️  Pause',
                color: Colors.white.withValues(alpha: 0.15),
                textColor: Colors.white,
                onTap: () => engine.pause(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SessionButton(
                label: '⏹️  Stop',
                color: ThemeConstants.error.withValues(alpha: 0.8),
                onTap: () => engine.stop(),
              ),
            ),
          ],
        );
      case SessionStatus.paused:
        return Row(
          children: [
            Expanded(
              child: _SessionButton(
                label: '▶️  Resume',
                color: ThemeConstants.copper,
                onTap: () => engine.resume(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SessionButton(
                label: '⏹️  Stop',
                color: ThemeConstants.error.withValues(alpha: 0.8),
                onTap: () => engine.stop(),
              ),
            ),
          ],
        );
      case SessionStatus.stopped:
      case SessionStatus.completed:
        return _SessionButton(
          label: '✅  Done',
          color: ThemeConstants.success,
          onTap: () => context.pop(),
        );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final SessionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SessionStatus.idle => ('⏳ Ready', ThemeConstants.textTertiary),
      SessionStatus.running => ('🟢 Running', ThemeConstants.success),
      SessionStatus.paused => ('🟡 Paused', ThemeConstants.warning),
      SessionStatus.stopped => ('🔴 Stopped', ThemeConstants.error),
      SessionStatus.completed => ('✅ Completed', ThemeConstants.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SessionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _SessionButton({
    required this.label,
    required this.color,
    this.textColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerPainter extends CustomPainter {
  final double progress;
  final bool isRunning;

  _TimerPainter({required this.progress, required this.isRunning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [ThemeConstants.copper, ThemeConstants.tanLight],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );

    // Glow dot at end of arc
    if (progress > 0 && isRunning) {
      final angle = -pi / 2 + 2 * pi * progress;
      final dotX = center.dx + radius * cos(angle);
      final dotY = center.dy + radius * sin(angle);

      final glowPaint = Paint()
        ..color = ThemeConstants.copper.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(dotX, dotY), 8, glowPaint);

      final dotPaint = Paint()..color = ThemeConstants.copper;
      canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimerPainter oldDelegate) =>
      progress != oldDelegate.progress || isRunning != oldDelegate.isRunning;
}
