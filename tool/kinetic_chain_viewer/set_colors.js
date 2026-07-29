// Port of Hydrawave3/apps/web/src/anatomy/setColors.js — the per-set palette.
//
// Okabe-Ito: 8 visually distinct, colourblind-friendly hues.
//
// ORDER IS PRODUCT-SPECIFIED, not aesthetic: Set 1 Yellow, Set 2 Blue, Set 3
// Green, and the Sun-Moon connecting arc of each set takes that set's colour.
// `setIndex` is 0-BASED in every marker builder on both platforms, so index 0
// is Set 1. Sets 4+ are headroom — nothing in the corpus authors more than 3.
//
// The Flutter side must agree: `kAnatomySetColors` in the pad map screen mirrors
// this array, because "matching set colours" only means anything if the legend,
// the chips and the 3D badges all say the same thing.

export const SET_COLORS = [
  0xf0e442, // Set 1 — yellow
  0x0072b2, // Set 2 — blue
  0x009e73, // Set 3 — green
  0xd55e00, // Set 4 — vermillion
  0x56b4e9, // Set 5 — sky blue
  0xcc79a7, // Set 6 — reddish purple
  0xe69f00, // Set 7 — orange
  0x999999, // Set 8 — grey
];

export function perfSetColor(setIndex) {
  const n = SET_COLORS.length;
  return SET_COLORS[(((Number(setIndex) || 0) % n) + n) % n];
}

export function perfSetColorCss(setIndex) {
  return `#${perfSetColor(setIndex).toString(16).padStart(6, "0")}`;
}
