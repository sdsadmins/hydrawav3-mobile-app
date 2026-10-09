import 'package:flutter/material.dart';

import 'session_plan_widgets.dart';

/// The Session Plan "Find Pad Placements" card — the v6 prototype's
/// `.ry-ses-find` in the Select User / Find Pad Placements duo: a Sun & Moon
/// tile and chevron on top, the title and its line underneath.
class FindPadPlacementsCard extends StatelessWidget {
  final VoidCallback? onTap;
  const FindPadPlacementsCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final sub = PlanTones.sub(context);
    return PlanCard(
      neutralBorder: true,
      padding: const EdgeInsets.all(12),
      onTap: onTap ?? () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color.fromRGBO(192, 157, 132, .15)
                      : const Color(0xFFF6ECDF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const PlanSunMoonMark(),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 20, color: sub),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Find Pad Placements',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: dark ? const Color(0xFFF4EFEA) : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Sun & Moon pad map, performance or recovery',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.3, color: sub),
          ),
        ],
      ),
    );
  }
}
