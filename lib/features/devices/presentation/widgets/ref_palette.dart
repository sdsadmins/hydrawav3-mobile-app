import 'package:flutter/material.dart';

/// The cowork-os handoff palette (copper), resolved for light/dark from the
/// current theme brightness — values copied verbatim from `:root` and
/// `[data-theme="dark"]` in the handoff `styles.css`. Shared by the
/// university-only Devices sections (Select User + Session setup).
class RefPalette {
  final Color copper;
  final Color copperInk;
  final Color tanSoft;
  final Color good;
  final Color goodSoft;
  final Color infoSoft;
  final Color card;
  final Color card2;
  final Color chipBg;
  final Color bg;
  final Color bg2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color cardline;
  final Gradient heroGrad;
  final Gradient sunGrad;
  final List<BoxShadow> shadow;

  const RefPalette({
    required this.copper,
    required this.copperInk,
    required this.tanSoft,
    required this.good,
    required this.goodSoft,
    required this.infoSoft,
    required this.card,
    required this.card2,
    required this.chipBg,
    required this.bg,
    required this.bg2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.cardline,
    required this.heroGrad,
    required this.sunGrad,
    required this.shadow,
  });

  static const _sunGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0B896), Color(0xFFB5825F)],
  );

  static RefPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const RefPalette(
        copper: Color(0xFFC69E83),
        copperInk: Color(0xFFC69E83), // dark: copper-ink → copper
        tanSoft: Color(0xFF2A3238),
        good: Color(0xFF3F8F6B),
        goodSoft: Color(0xFF22352C),
        infoSoft: Color(0xFF223038),
        card: Color(0xFF1C252B),
        card2: Color(0xFF212C33),
        chipBg: Color(0xFF232E35),
        bg: Color(0xFF101518),
        bg2: Color(0xFF151C21),
        ink: Color(0xFFF4EFEA),
        ink2: Color(0xFFC0B7AE),
        ink3: Color(0xFF877E75),
        line: Color.fromRGBO(244, 239, 234, 0.10),
        cardline: Color.fromRGBO(198, 158, 131, 0.32),
        heroGrad: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2A3D4A), Color(0xFF1F2B33), Color(0xFF141F26)],
          stops: [0.0, 0.55, 1.0],
        ),
        sunGrad: _sunGrad,
        shadow: [
          BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
          BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      );
    }
    return const RefPalette(
      copper: Color(0xFFC69E83),
      copperInk: Color(0xFF8A5F42),
      tanSoft: Color(0xFFF2E9E2),
      good: Color(0xFF3F8F6B),
      goodSoft: Color(0xFFE3F0E9),
      infoSoft: Color(0xFFE3EDF1),
      card: Color(0xFFFFFFFF),
      card2: Color(0xFFFBF8F5),
      chipBg: Color(0xFFFFFFFF),
      bg: Color(0xFFF6F2EE),
      bg2: Color(0xFFEFE9E3),
      ink: Color(0xFF1A1A1A),
      ink2: Color(0xFF5C5650),
      ink3: Color(0xFF948B82),
      line: Color.fromRGBO(26, 26, 26, 0.09),
      cardline: Color.fromRGBO(198, 158, 131, 0.55),
      heroGrad: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF243541), Color(0xFF1F2B33), Color(0xFF192A35)],
        stops: [0.0, 0.55, 1.0],
      ),
      sunGrad: _sunGrad,
      shadow: [
        BoxShadow(color: Color(0x0D1F2B33), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x121F2B33), blurRadius: 24, offset: Offset(0, 8)),
      ],
    );
  }
}

/// `goalColor(goal)` from app.js — the protocol chip's text color + soft fill +
/// icon gradient, keyed off the protocol goal string.
class GoalColor {
  final Color text;
  final Color soft;
  final List<Color> grad;
  const GoalColor(this.text, this.soft, this.grad);

  static GoalColor of(String goal, RefPalette p) {
    if (goal.contains('Recovery')) {
      return GoalColor(const Color(0xFF2F4A5A), p.infoSoft,
          const [Color(0xFF3D5260), Color(0xFF1F2B33)]);
    }
    if (goal.contains('Comfort')) {
      return GoalColor(const Color(0xFF8A5F42), p.tanSoft,
          const [Color(0xFFC69E83), Color(0xFF8A5F42)]);
    }
    if (goal.contains('Calm')) {
      return GoalColor(const Color(0xFF4E7A8A), p.infoSoft,
          const [Color(0xFF5E8CA0), Color(0xFF2F4A5A)]);
    }
    if (goal.contains('Vitality')) {
      return GoalColor(const Color(0xFF3F8F6B), p.goodSoft,
          const [Color(0xFF5FB088), Color(0xFF3F8F6B)]);
    }
    // Performance / default
    return GoalColor(const Color(0xFFA87B5C), p.tanSoft,
        const [Color(0xFFD9B294), Color(0xFFA87B5C)]);
  }
}
