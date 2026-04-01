import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

class VibrationControl extends StatelessWidget {
  final double minValue;
  final double maxValue;
  final ValueChanged<double> onMinChanged;
  final ValueChanged<double> onMaxChanged;

  const VibrationControl({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.onMinChanged,
    required this.onMaxChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vibration', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ThemeConstants.spacingSm),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('Min: ${minValue.toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall),
                  Slider(
                    value: minValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: ThemeConstants.copper,
                    onChanged: (v) {
                      if (v <= maxValue) onMinChanged(v);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Text('Max: ${maxValue.toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall),
                  Slider(
                    value: maxValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: ThemeConstants.copper,
                    onChanged: (v) {
                      if (v >= minValue) onMaxChanged(v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
