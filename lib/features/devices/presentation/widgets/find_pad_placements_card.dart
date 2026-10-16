import 'package:flutter/material.dart';

import '../../../../core/theme/widgets/hw_tablet.dart';

import 'session_plan_widgets.dart';

/// The Session Plan "Find Pad Placements" card — the v6 prototype's
/// `.ry-ses-find` in the Select User / Find Pad Placements duo: a Sun & Moon
/// tile and chevron on top, the title and its line underneath.
class FindPadPlacementsCard extends StatelessWidget {
  final VoidCallback? onTap;

  /// Tablet: a "PICK A FOCUS" tile was tapped (a recovery goal value).
  final ValueChanged<String>? onFocus;
  const FindPadPlacementsCard({super.key, this.onTap, this.onFocus});

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final sub = PlanTones.sub(context);
    if (onFocus != null && HwTablet.of(context)) {
      return _TabletFind(onTap: onTap ?? () {}, onFocus: onFocus!);
    }
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

/// Tablet `.ry-ses-find.v6pf`: the header row, then the body picture beside
/// "PICK A FOCUS" — four recovery goals that open the Assistant on that goal.
class _TabletFind extends StatelessWidget {
  final VoidCallback onTap;
  final ValueChanged<String> onFocus;
  const _TabletFind({required this.onTap, required this.onFocus});

  static const _focus = [
    ('discomfort', 'Discomfort', Icons.radio_button_checked_rounded),
    ('range_of_motion', 'Joint Mobility', Icons.refresh_rounded),
    ('performance_recovery', 'Post-Workout', Icons.bolt_outlined),
    ('lymphatic_activation', 'Lymphatic', Icons.water_drop_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final sub = PlanTones.sub(context);
    final ink = dark ? const Color(0xFFF4EFEA) : const Color(0xFF1A1A1A);
    final line2 = dark
        ? const Color.fromRGBO(244, 239, 234, .05)
        : const Color.fromRGBO(26, 26, 26, .05);
    final line = dark
        ? const Color.fromRGBO(244, 239, 234, .10)
        : const Color.fromRGBO(26, 26, 26, .09);
    final card2 = dark ? const Color(0xFF212C33) : const Color(0xFFFBF8F5);
    final warmInk = dark ? const Color(0xFFE7D3C0) : const Color(0xFF6B4A32);
    return PlanCard(
      neutralBorder: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .v6pf-h
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find Pad Placements',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink)),
                        const SizedBox(height: 2),
                        Text('Sun & Moon pad map, performance or recovery',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: sub)),
                      ],
                    ),
                  ),
                  Opacity(
                    opacity: .5,
                    child:
                        Icon(Icons.chevron_right_rounded, size: 20, color: sub),
                  ),
                ],
              ),
            ),
          ),
          // .v6pf-body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 128,
                    child: Semantics(
                      button: true,
                      label: 'Find pad placements',
                      child: GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: line2),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: dark
                                  ? const [Color(0xFF1C2731), Color(0xFF111A21)]
                                  : const [
                                      Color(0xFFFBF7F2),
                                      Color(0xFFF0E5DA)
                                    ],
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/body_shot.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('PICK A FOCUS',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: sub)),
                        const SizedBox(height: 7),
                        Expanded(
                          child: Column(
                            children: [
                              for (var r = 0; r < 2; r++) ...[
                                if (r > 0) const SizedBox(height: 7),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var c = 0; c < 2; c++) ...[
                                        if (c > 0) const SizedBox(width: 7),
                                        Expanded(
                                          child: _FocusTile(
                                            label: _focus[r * 2 + c].$2,
                                            icon: _focus[r * 2 + c].$3,
                                            fill: card2,
                                            border: line,
                                            iconColor: warmInk,
                                            ink: ink,
                                            onTap: () =>
                                                onFocus(_focus[r * 2 + c].$1),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.v6pf-cat`
class _FocusTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fill;
  final Color border;
  final Color iconColor;
  final Color ink;
  final VoidCallback onTap;
  const _FocusTile({
    required this.label,
    required this.icon,
    required this.fill,
    required this.border,
    required this.iconColor,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: .9,
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
