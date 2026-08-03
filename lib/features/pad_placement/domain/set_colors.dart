import 'dart:ui' show Color;

/// Per-set palette, the Flutter port of Hydrawave3
/// `apps/web/src/anatomy/setColors.js`.
///
/// Kept in its own tiny module for the same reason the web does — no widgets, no
/// theme, no 3D — so the set list, the legend, the chips and the AnatomyScene
/// stage can all import it and cannot drift apart. "Matching set colours" only
/// means something if every surface agrees.
///
/// Okabe-Ito: 8 visually distinct, colourblind-friendly hues.
///
/// ORDER IS PRODUCT-SPECIFIED, not aesthetic — the Jul 25 CEO review asked for
/// Set 1 yellow, Set 2 blue, Set 3 green, and for each set's Sun→Moon connecting
/// line to take that set's colour. `setIndex` is 0-BASED in both marker builders,
/// so index 0 is Set 1. Sets 4+ keep the remaining Okabe-Ito hues; nothing in the
/// corpus authors more than 3 sets today, so those are headroom.
///
/// Deliberately NOT `RefPalette.set1/2/3`, which is a theme token used elsewhere
/// and has no reason to follow the 3D viewer.
const List<Color> kAnatomySetColors = [
  Color(0xFFF0E442), // Set 1 — yellow
  Color(0xFF0072B2), // Set 2 — blue
  Color(0xFF009E73), // Set 3 — green
  Color(0xFFD55E00), // Set 4 — vermillion
  Color(0xFF56B4E9), // Set 5 — sky blue
  Color(0xFFCC79A7), // Set 6 — reddish purple
  Color(0xFFE69F00), // Set 7 — orange
  Color(0xFF999999), // Set 8 — grey
];

/// The colour for a 0-based set index, wrapping like the web's `perfSetColor`.
Color anatomySetColor(int setIndex) {
  final n = kAnatomySetColors.length;
  return kAnatomySetColors[((setIndex % n) + n) % n];
}
