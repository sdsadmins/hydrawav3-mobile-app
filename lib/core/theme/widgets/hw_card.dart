import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';

class HwCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? elevation;

  const HwCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      elevation: elevation,
      child: Padding(
        padding: padding ??
            const EdgeInsets.all(ThemeConstants.spacingMd),
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        child: card,
      );
    }

    return card;
  }
}
