import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

class TemperatureSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color activeColor;
  final double min;
  final double max;

  const TemperatureSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.activeColor = ThemeConstants.accent,
    this.min = 0,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${value.toInt()}%',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          activeColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
