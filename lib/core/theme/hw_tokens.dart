import 'package:flutter/material.dart';

/// The cowork-os handoff design system, ported from `hydrawav3-ui-handoff`.
///
/// Colour values are copied verbatim from `:root` and `[data-theme="dark"]` in
/// the handoff `styles.css`; radii / spacing / type / motion come from
/// `Hydrawav3_UI_Design_Principles.md` §3 and §7 (motion locked 2026-07-11:
/// Smooth easing + Brisk tempo).
///
/// Use these tokens, never magic numbers — Principles §3 makes that a pass/fail
/// gate.
class RefPalette {
  // ---- brand core -------------------------------------------------------
  final Color copper;

  /// Copper that is legible **on a surface**: `#8A5F42` in light, `#C69E83` in
  /// dark. Always prefer this over [copper] for text/icons, or dark mode fails
  /// WCAG AA.
  final Color copperInk;
  final Color copperDeep;
  final Color tan;
  final Color tanSoft;

  // ---- semantic ---------------------------------------------------------
  final Color good;
  final Color goodSoft;
  final Color mid;
  final Color midSoft;
  final Color low;
  final Color lowSoft;
  final Color info;
  final Color infoSoft;

  // ---- pad-set neutrals -------------------------------------------------
  final Color set1;
  final Color set2;
  final Color set3;

  // ---- surfaces ---------------------------------------------------------
  final Color card;
  final Color card2;
  final Color chipBg;
  final Color bg;
  final Color bg2;

  // ---- ink --------------------------------------------------------------
  final Color ink;
  final Color ink2;
  final Color ink3;

  // ---- lines ------------------------------------------------------------
  final Color line;
  final Color line2;
  final Color divider;
  final Color cardline;
  final Color ringTrack;

  // ---- gradients + elevation -------------------------------------------
  final Gradient heroGrad;
  final Gradient sunGrad;
  final Gradient moonGrad;
  final List<BoxShadow> shadow;
  final List<BoxShadow> shadowLg;

  const RefPalette({
    required this.copper,
    required this.copperInk,
    required this.copperDeep,
    required this.tan,
    required this.tanSoft,
    required this.good,
    required this.goodSoft,
    required this.mid,
    required this.midSoft,
    required this.low,
    required this.lowSoft,
    required this.info,
    required this.infoSoft,
    required this.set1,
    required this.set2,
    required this.set3,
    required this.card,
    required this.card2,
    required this.chipBg,
    required this.bg,
    required this.bg2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.divider,
    required this.cardline,
    required this.ringTrack,
    required this.heroGrad,
    required this.sunGrad,
    required this.moonGrad,
    required this.shadow,
    required this.shadowLg,
  });

  /// `--sun-grad: linear-gradient(135deg,#E0B896,#B5825F)` — identical in both
  /// themes (dark overrides no gradient token).
  static const _sunGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0B896), Color(0xFFB5825F)],
  );

  /// `--moon-grad: linear-gradient(135deg,#3D5260,#1F2B33)`.
  static const _moonGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3D5260), Color(0xFF1F2B33)],
  );

  static RefPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const RefPalette light = RefPalette(
    copper: Color(0xFFC69E83),
    copperInk: Color(0xFF8A5F42),
    copperDeep: Color(0xFFA87B5C),
    tan: Color(0xFFDDCABF),
    tanSoft: Color(0xFFF2E9E2),
    good: Color(0xFF3F8F6B),
    goodSoft: Color(0xFFE3F0E9),
    mid: Color(0xFFD99A4E),
    midSoft: Color(0xFFF7ECDC),
    low: Color(0xFFC2604E),
    lowSoft: Color(0xFFF6E3DF),
    info: Color(0xFF4E7A8A),
    infoSoft: Color(0xFFE3EDF1),
    set1: Color(0xFF71838F),
    set2: Color(0xFF84936F),
    set3: Color(0xFF9A8B7A),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFFBF8F5),
    chipBg: Color(0xFFFFFFFF),
    bg: Color(0xFFF6F2EE),
    bg2: Color(0xFFEFE9E3),
    ink: Color(0xFF1A1A1A),
    ink2: Color(0xFF5C5650),
    ink3: Color(0xFF948B82),
    line: Color.fromRGBO(26, 26, 26, 0.09),
    line2: Color.fromRGBO(26, 26, 26, 0.05),
    divider: Color.fromRGBO(198, 158, 131, 0.45),
    cardline: Color.fromRGBO(198, 158, 131, 0.55),
    ringTrack: Color(0xFFEAE2DA),
    heroGrad: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF243541), Color(0xFF1F2B33), Color(0xFF192A35)],
      stops: [0.0, 0.55, 1.0],
    ),
    sunGrad: _sunGrad,
    moonGrad: _moonGrad,
    shadow: [
      BoxShadow(color: Color(0x0D1F2B33), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x121F2B33), blurRadius: 24, offset: Offset(0, 8)),
    ],
    shadowLg: [
      BoxShadow(color: Color(0x141F2B33), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x241F2B33), blurRadius: 48, offset: Offset(0, 18)),
    ],
  );

  static const RefPalette dark = RefPalette(
    copper: Color(0xFFC69E83),
    // dark: every `--copper-ink` usage swaps to `--copper` (styles.css :87,
    // :123, :180, :196, :202, :375, :401, :590).
    copperInk: Color(0xFFC69E83),
    copperDeep: Color(0xFFA87B5C),
    tan: Color(0xFFDDCABF),
    tanSoft: Color(0xFF2A3238),
    good: Color(0xFF3F8F6B),
    goodSoft: Color(0xFF22352C),
    mid: Color(0xFFD99A4E),
    midSoft: Color(0xFF3A3222),
    low: Color(0xFFC2604E),
    lowSoft: Color(0xFF3A2823),
    info: Color(0xFF4E7A8A),
    infoSoft: Color(0xFF223038),
    set1: Color(0xFF71838F),
    set2: Color(0xFF84936F),
    set3: Color(0xFF9A8B7A),
    card: Color(0xFF1C252B),
    card2: Color(0xFF212C33),
    chipBg: Color(0xFF232E35),
    bg: Color(0xFF101518),
    bg2: Color(0xFF151C21),
    ink: Color(0xFFF4EFEA),
    ink2: Color(0xFFC0B7AE),
    ink3: Color(0xFF877E75),
    line: Color.fromRGBO(244, 239, 234, 0.10),
    line2: Color.fromRGBO(244, 239, 234, 0.05),
    divider: Color.fromRGBO(198, 158, 131, 0.34),
    cardline: Color.fromRGBO(198, 158, 131, 0.32),
    ringTrack: Color(0xFF2A353C),
    heroGrad: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF2A3D4A), Color(0xFF1F2B33), Color(0xFF141F26)],
      stops: [0.0, 0.55, 1.0],
    ),
    sunGrad: _sunGrad,
    moonGrad: _moonGrad,
    shadow: [
      BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    shadowLg: [
      BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x73000000), blurRadius: 48, offset: Offset(0, 18)),
    ],
  );
}

/// Radius ladder — Principles §3. Cards use [lg].
class HwRadius {
  HwRadius._();
  static const double xl = 22;
  static const double lg = 18;
  static const double md = 15;
  static const double sm = 11;
  static const double xs = 8;
  static const double pill = 999;
}

/// 4-based spacing scale — Principles §3.
class HwSpace {
  HwSpace._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
}

/// Type scale — Principles §3. Display numerals (32/38/46/56/64) are
/// intentional hero literals and the only permitted exceptions.
class HwType {
  HwType._();
  static const double eyebrow = 11;
  static const double cap = 12;
  static const double sm = 13;
  static const double base = 14;
  static const double md = 15;
  static const double lg = 17;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Motion tokens — Principles §7, locked 2026-07-11 (Smooth + Brisk).
///
/// To retune the app's feel, edit these; never hand-tune a single widget.
class HwMotion {
  HwMotion._();

  /// Smooth — eased both ends. Drives every ordinary transition.
  static const Curve ease = Cubic(.65, 0, .35, 1);

  /// Tactile overshoot. Press states and tile bounce only.
  static const Curve spring = Cubic(.34, 1.56, .64, 1);

  static const Duration t1 = Duration(milliseconds: 120);
  static const Duration t2 = Duration(milliseconds: 160);
  static const Duration t3 = Duration(milliseconds: 220);
  static const Duration t4 = Duration(milliseconds: 300);

  /// Device-card copper fill sweep — deliberately slower so the wipe reads.
  static const Duration fill = Duration(milliseconds: 400);

  /// Tap squeeze applied to every tappable surface.
  static const double press = .96;

  /// Delay between cards as a screen assembles.
  static const Duration stagger = Duration(milliseconds: 28);
}

/// `goalColor(goal)` from app.js — the protocol chip's text colour + soft fill +
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
