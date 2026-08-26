import 'package:flutter/material.dart';

import 'ref_palette.dart';

/// University-only "Find Pad Placements" card — a 1:1 port of the cowork-os
/// handoff Session Plan card (`app.js` → `renderSetup`, `styles.css`): a
/// pressable `.card` with a sun-gradient pad icon, title, subtitle, and chevron.
/// Pure design (no backend); tapping is a no-op placeholder for now.
class FindPadPlacementsCard extends StatelessWidget {
  final VoidCallback? onTap;
  const FindPadPlacementsCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.cardline),
            boxShadow: p.shadow,
          ),
          child: Row(
            children: [
              // 36×36 sun-gradient icon.
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: p.sunGrad,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.grid_view_rounded,
                  size: 20,
                  color: Color(0xFF2B1D12),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find Pad Placements',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sun & Moon pad map, for performance or recovery',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
