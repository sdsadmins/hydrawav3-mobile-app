import 'package:flutter/material.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../domain/performance_models.dart';

/// The in-chat placement card — the UI spec's `.placecard` from
/// `perfFlowPlacements()`: one coloured swatch per set with its placement label,
/// the Sun/Moon side reminder, then **3D pad map** / **Go to Session**.
///
/// Both ways in render this same card: the catalogue chips and a chat turn whose
/// `results` carried pads.
class PlacementCard extends StatelessWidget {
  final PadSetPayload payload;
  final VoidCallback onOpen3D;
  final VoidCallback onGoToSession;

  const PlacementCard({
    super.key,
    required this.payload,
    required this.onOpen3D,
    required this.onGoToSession,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final setColors = [p.set1, p.set2, p.set3];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: HwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (payload.chain != null &&
                payload.chain!.name.trim().isNotEmpty) ...[
              Text(
                payload.chain!.name,
                style: TextStyle(
                  fontSize: HwType.sm,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              if (payload.chain!.subline.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  payload.chain!.subline,
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
              ],
              const SizedBox(height: HwSpace.s3),
            ],
            for (var i = 0; i < payload.sets.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: setColors[i % 3],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        payload.sets[i].placementLabel.trim().isEmpty
                            ? 'Set ${payload.sets[i].setIndex}'
                            : payload.sets[i].placementLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: HwType.cap,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                    ),
                    if (payload.sets[i].role.trim().isNotEmpty)
                      Text(
                        payload.sets[i].role.toLowerCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: p.ink3,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '☀ Sun = right · ☾ Moon = left',
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
            const SizedBox(height: HwSpace.s3),
            Row(
              children: [
                Expanded(
                  child: HwButton(
                    label: '3D pad map',
                    filled: false,
                    onTap: onOpen3D,
                  ),
                ),
                const SizedBox(width: HwSpace.s2),
                Expanded(
                  child: HwButton(
                    label: 'Go to Session',
                    onTap: onGoToSession,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
