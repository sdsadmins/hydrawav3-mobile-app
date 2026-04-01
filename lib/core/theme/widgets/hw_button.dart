import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';

class HwButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final Color? backgroundColor;
  final double? width;
  final double height;

  const HwButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.backgroundColor,
    this.width,
    this.height = 56,
  });

  @override
  State<HwButton> createState() => _HwButtonState();
}

class _HwButtonState extends State<HwButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.isLoading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: widget.isOutlined
                  ? ThemeConstants.darkTeal
                  : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: ThemeConstants.spacingSm),
              ],
              Text(widget.label),
            ],
          );

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          if (!widget.isLoading) widget.onPressed?.call();
        },
        onTapCancel: () => _controller.reverse(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: widget.height,
          width: widget.width,
          child: widget.isOutlined
              ? OutlinedButton(
                  onPressed: widget.isLoading ? null : widget.onPressed,
                  child: child,
                )
              : ElevatedButton(
                  onPressed: widget.isLoading ? null : widget.onPressed,
                  style: widget.backgroundColor != null
                      ? ElevatedButton.styleFrom(
                          backgroundColor: widget.backgroundColor)
                      : null,
                  child: child,
                ),
        ),
      ),
    );
  }
}
