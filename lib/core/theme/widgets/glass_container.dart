import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';

/// Solid dark card — replaces the old GlassContainer.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur; // ignored, kept for API compat
  final Color? color;
  final double opacity; // ignored
  final VoidCallback? onTap;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = ThemeConstants.radiusMd,
    this.blur = 0,
    this.color,
    this.opacity = 0,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    Widget container = Container(
      padding: padding ?? const EdgeInsets.all(ThemeConstants.spacingMd),
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? ThemeConstants.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: ThemeConstants.border, width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: container);
    }
    return container;
  }
}

/// Solid dark card with tap feedback.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = ThemeConstants.radiusMd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeConstants.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding ?? const EdgeInsets.all(ThemeConstants.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: ThemeConstants.border, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
