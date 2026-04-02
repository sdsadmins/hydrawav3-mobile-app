import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';

// ─── GRADIENT CARD ───
/// Premium card with subtle gradient background and optional glow.
class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final List<Color>? gradientColors;
  final bool showGlow;
  final double borderRadius;

  const GradientCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.gradientColors,
    this.showGlow = false,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ??
        [ThemeConstants.surface, ThemeConstants.surfaceVariant.withValues(alpha: 0.5)];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: ThemeConstants.accent.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── GLOW ICON BOX ───
/// Icon container with subtle radial glow behind it.
class GlowIconBox extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double glowRadius;

  const GlowIconBox({
    super.key,
    required this.icon,
    this.color,
    this.size = 44,
    this.iconSize = 22,
    this.glowRadius = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeConstants.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Icon(icon, color: c, size: iconSize),
    );
  }
}

// ─── ANIMATED ENTRANCE ───
/// Wraps child in a fade+slide entrance animation.
class AnimatedEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final int baseDelayMs;
  final int durationMs;

  const AnimatedEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelayMs = 100,
    this.durationMs = 500,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: durationMs + index * baseDelayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ─── SHIMMER LOADING ───
/// Premium shimmer placeholder while content loads.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
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
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _controller.value, 0),
              end: Alignment(-1 + 2 * _controller.value + 1, 0),
              colors: [
                ThemeConstants.surface,
                ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                ThemeConstants.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── STAT CHIP ───
/// Compact metric display — icon + value + label.
class StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? label;
  final Color? color;

  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeConstants.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(label!, style: const TextStyle(fontSize: 11, color: ThemeConstants.textTertiary)),
          ],
        ],
      ),
    );
  }
}

// ─── ACCENT DIVIDER ───
class AccentDivider extends StatelessWidget {
  const AccentDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeConstants.border.withValues(alpha: 0),
            ThemeConstants.accent.withValues(alpha: 0.2),
            ThemeConstants.border.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

// ─── SECTION HEADER ───
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ThemeConstants.textTertiary,
              letterSpacing: 1,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
