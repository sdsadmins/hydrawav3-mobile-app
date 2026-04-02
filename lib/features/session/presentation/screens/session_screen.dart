import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
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
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _showDiscomfortModal = false;
  int? _selectedDiscomfort;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(sessionEngineProvider);
    final protocolAsync = ref.watch(protocolDetailProvider(widget.protocolId));

    protocolAsync.whenData((protocol) {
      if (engine.protocol == null) {
        ref.read(sessionEngineProvider.notifier)
            .loadSession(protocol, widget.deviceIds);
      }
    });

    final timer = engine.timer;
    final status = engine.status;
    final ctrl = ref.read(sessionEngineProvider.notifier);

    // Show discomfort modal on completion
    if (status == SessionStatus.completed && !_showDiscomfortModal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showDiscomfortModal = true);
      });
    }

    return Scaffold(
      backgroundColor: ThemeConstants.backgroundDeep,
      body: Stack(
        children: [
          // Background gradients
          _buildBackground(status),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(status),

                const Spacer(flex: 1),

                // Protocol info
                protocolAsync.when(
                  data: (p) => _buildProtocolInfo(p.templateName),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 32),

                // Timer circle
                _buildTimerCircle(timer, status),

                const SizedBox(height: 24),

                // Cycle info
                if (timer.totalCycles > 0)
                  Text(
                    'Cycle ${timer.currentCycleIndex + 1} of ${timer.totalCycles}',
                    style: const TextStyle(
                      color: ThemeConstants.metallic400,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                const SizedBox(height: 24),

                // Device status badges
                _buildDeviceBadges(),

                const Spacer(flex: 2),

                // Controls
                _buildControls(status, ctrl),

                const SizedBox(height: 48),
              ],
            ),
          ),

          // Discomfort modal overlay
          if (_showDiscomfortModal)
            _buildDiscomfortModal(ctrl),
        ],
      ),
    );
  }

  // ─── Background ───────────────────────────────────────────────────

  Widget _buildBackground(SessionStatus status) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final isRunning = status == SessionStatus.running;
        final pulseOpacity = isRunning
            ? 0.15 + (_pulseController.value * 0.15)
            : 0.0;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ThemeConstants.background,
                ThemeConstants.backgroundDeep,
              ],
            ),
          ),
          child: isRunning
              ? Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        ThemeConstants.accent.withValues(alpha: pulseOpacity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ─── Header ───────────────────────────────────────────────────────

  Widget _buildHeader(SessionStatus status) {
    final isActive = status == SessionStatus.running ||
        status == SessionStatus.paused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back button
          _buildCircularButton(
            icon: Icons.chevron_left_rounded,
            onTap: () {
              final ctrl = ref.read(sessionEngineProvider.notifier);
              if (isActive) ctrl.stop();
              context.pop();
            },
          ),

          const Spacer(),

          // Status text
          Text(
            _headerLabel(status),
            style: const TextStyle(
              color: ThemeConstants.accentLight,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),

          const Spacer(),

          // Settings button
          _buildCircularButton(
            icon: Icons.tune_rounded,
            onTap: () {
              // Settings action placeholder
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ThemeConstants.surface.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: ThemeConstants.surfaceVariant,
            width: 1,
          ),
        ),
        child: Icon(icon, color: ThemeConstants.textPrimary, size: 22),
      ),
    );
  }

  String _headerLabel(SessionStatus s) => switch (s) {
        SessionStatus.idle => 'READY TO START',
        SessionStatus.running => 'SESSION ACTIVE',
        SessionStatus.paused => 'SESSION PAUSED',
        SessionStatus.stopped => 'SESSION ENDED',
        SessionStatus.completed => 'SESSION COMPLETE',
      };

  // ─── Protocol Info ────────────────────────────────────────────────

  Widget _buildProtocolInfo(String name) {
    return Column(
      children: [
        Text(
          name,
          style: const TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Thermal Therapy',
          style: const TextStyle(
            color: ThemeConstants.metallic400,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ─── Timer Circle ─────────────────────────────────────────────────

  Widget _buildTimerCircle(TimerState timer, SessionStatus status) {
    final isRunning = status == SessionStatus.running;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: ThemeConstants.accent.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: SizedBox(
        width: 288,
        height: 288,
        child: CustomPaint(
          painter: _TimerRing(
            progress: timer.progress,
            active: isRunning,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timer.remaining.formatted,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                    fontFamily: 'monospace',
                    letterSpacing: -1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 13,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Device Badges ────────────────────────────────────────────────

  Widget _buildDeviceBadges() {
    if (widget.deviceIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: ThemeConstants.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
          border: Border.all(
            color: ThemeConstants.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: ThemeConstants.error, size: 16),
            const SizedBox(width: 8),
            Text(
              'No Devices Selected',
              style: TextStyle(
                color: ThemeConstants.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: widget.deviceIds.map((deviceId) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: ThemeConstants.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
            border: Border.all(color: ThemeConstants.surfaceVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulse dot
              _PulseDot(color: ThemeConstants.accent),
              const SizedBox(width: 8),
              Text(
                deviceId.length > 12
                    ? '${deviceId.substring(0, 12)}...'
                    : deviceId,
                style: const TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.battery_std_rounded,
                color: ThemeConstants.metallic400,
                size: 16,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Controls ─────────────────────────────────────────────────────

  Widget _buildControls(SessionStatus status, SessionEngine ctrl) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Stop button (visible when running or paused)
        if (status == SessionStatus.running || status == SessionStatus.paused)
          _StopButton(onTap: () => ctrl.stop()),

        if (status == SessionStatus.running || status == SessionStatus.paused)
          const SizedBox(width: 32),

        // Main play/pause button
        _buildMainButton(status, ctrl),

        // Done button replaces controls when stopped/completed
      ],
    );
  }

  Widget _buildMainButton(SessionStatus status, SessionEngine ctrl) {
    final VoidCallback? onTap;
    final IconData icon;

    switch (status) {
      case SessionStatus.idle:
        onTap = () => ctrl.start();
        icon = Icons.play_arrow_rounded;
      case SessionStatus.running:
        onTap = () => ctrl.pause();
        icon = Icons.pause_rounded;
      case SessionStatus.paused:
        onTap = () => ctrl.resume();
        icon = Icons.play_arrow_rounded;
      case SessionStatus.stopped:
        onTap = () => context.pop();
        icon = Icons.check_rounded;
      case SessionStatus.completed:
        onTap = null; // Modal handles completion
        icon = Icons.check_rounded;
    }

    return _PlayPauseButton(
      icon: icon,
      onTap: onTap ?? () {},
    );
  }

  // ─── Discomfort Modal ─────────────────────────────────────────────

  Widget _buildDiscomfortModal(SessionEngine ctrl) {
    return GestureDetector(
      onTap: () {}, // Block taps to background
      child: Container(
        color: ThemeConstants.backgroundDeep.withValues(alpha: 0.9),
        child: BackdropFilter(
          filter: _blurFilter,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: ThemeConstants.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ThemeConstants.surfaceVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  const Text(
                    'Session Complete!',
                    style: TextStyle(
                      color: ThemeConstants.accentLight,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Subtitle
                  const Text(
                    'How is your discomfort level now?',
                    style: TextStyle(
                      color: ThemeConstants.metallic400,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Number buttons 1-10
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: List.generate(10, (i) {
                      final level = i + 1;
                      final isSelected = _selectedDiscomfort == level;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDiscomfort = level);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? ThemeConstants.accent
                                : ThemeConstants.backgroundDeep,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? ThemeConstants.accent
                                  : ThemeConstants.surfaceVariant,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$level',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : ThemeConstants.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  if (_selectedDiscomfort != null)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _completeWithDiscomfort(ctrl),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Submit',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),

                  if (_selectedDiscomfort != null) const SizedBox(height: 12),

                  // Skip button
                  TextButton(
                    onPressed: () => _completeWithDiscomfort(ctrl),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static final _blurFilter =
      ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);

  void _completeWithDiscomfort(SessionEngine ctrl) {
    // Could save session record with discomfort value here
    setState(() => _showDiscomfortModal = false);
    context.pop();
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  Color _statusColor(SessionStatus s) => switch (s) {
        SessionStatus.idle => ThemeConstants.textTertiary,
        SessionStatus.running => ThemeConstants.accent,
        SessionStatus.paused => ThemeConstants.warning,
        SessionStatus.stopped => ThemeConstants.error,
        SessionStatus.completed => ThemeConstants.success,
      };

  String _statusLabel(SessionStatus s) => switch (s) {
        SessionStatus.idle => 'READY',
        SessionStatus.running => 'ACTIVE',
        SessionStatus.paused => 'PAUSED',
        SessionStatus.stopped => 'STOPPED',
        SessionStatus.completed => 'COMPLETE',
      };
}

// ═══════════════════════════════════════════════════════════════════════
// Play / Pause Button
// ═══════════════════════════════════════════════════════════════════════

class _PlayPauseButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PlayPauseButton({required this.icon, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ThemeConstants.accentLight,
                ThemeConstants.accentDark,
              ],
            ),
            border: Border.all(
              color: ThemeConstants.backgroundDeep,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeConstants.accent.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Stop Button
// ═══════════════════════════════════════════════════════════════════════

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          shape: BoxShape.circle,
          border: Border.all(color: ThemeConstants.surfaceVariant),
        ),
        child: const Icon(
          Icons.stop_rounded,
          color: ThemeConstants.error,
          size: 32,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Pulse Dot
// ═══════════════════════════════════════════════════════════════════════

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.6 + _controller.value * 0.4),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _controller.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Timer Ring Painter
// ═══════════════════════════════════════════════════════════════════════

class _TimerRing extends CustomPainter {
  final double progress;
  final bool active;
  _TimerRing({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Background ring
    final bgPaint = Paint()
      ..color = ThemeConstants.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    if (progress > 0) {
      // Glow effect behind progress arc
      if (active) {
        final glowPaint = Paint()
          ..color = ThemeConstants.accent.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -pi / 2,
          2 * pi * progress,
          false,
          glowPaint,
        );
      }

      final fgPaint = Paint()
        ..color = ThemeConstants.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimerRing old) =>
      progress != old.progress || active != old.active;
}
