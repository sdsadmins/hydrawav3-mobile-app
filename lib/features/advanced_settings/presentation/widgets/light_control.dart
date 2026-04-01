import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

class LightControl extends StatelessWidget {
  final double intensity;
  final ValueChanged<double> onChanged;

  const LightControl({
    super.key,
    required this.intensity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Light Intensity',
                style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Icon(
                  Icons.lightbulb,
                  color: Color.lerp(
                    ThemeConstants.textTertiary,
                    ThemeConstants.warning,
                    intensity / 100,
                  ),
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  '${intensity.toInt()}%',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        Slider(
          value: intensity,
          min: 0,
          max: 100,
          divisions: 100,
          activeColor: ThemeConstants.warning,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
