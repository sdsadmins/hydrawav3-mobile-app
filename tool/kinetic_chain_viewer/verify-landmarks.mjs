// Guards the landmark tables against transcription drift.
//
//   node verify-landmarks.mjs
//
// Three checks:
//   1. Our hand-ported LOCAL_PAD_LANDMARKS block is character-identical (modulo
//      whitespace) to the web's AnatomyScene.jsx block. Catches every numeric typo.
//   2. The merged PAD_LANDMARKS union has the expected shape: 65 unique zones,
//      every entry left/right paired, left mirrored from right, all finite.
//   3. The 13 keys defined in BOTH tables resolve to the shared calibration
//      values, not the local ones — i.e. spread order is still shared-wins.
//
// Run this after regenerating anatomy_calibration.js or editing anatomy_landmarks.js.

import fs from "node:fs";
import path from "node:path";
import { PAD_LANDMARKS } from "./anatomy_landmarks.js";
import { ANATOMY_LANDMARKS } from "./anatomy_calibration.js";

const WEB = path.resolve(
  "../../../Hydrawave3/apps/web/src/components/AnatomyScene.jsx",
);

let failures = 0;
const fail = (msg) => {
  console.error(`  FAIL  ${msg}`);
  failures++;
};

// ── 1 · LOCAL_PAD_LANDMARKS matches the web verbatim ────────────────────────

function localBlock(source) {
  const start = source.indexOf("const LOCAL_PAD_LANDMARKS = {");
  if (start < 0) return null;
  const end = source.indexOf("\n};", start);
  if (end < 0) return null;
  return source
    .slice(start, end)
    .replace(/const LOCAL_PAD_LANDMARKS = \{/, "")
    .replace(/\s+/g, " ")
    .trim();
}

if (!fs.existsSync(WEB)) {
  console.warn(`  SKIP  web reference not found at ${WEB}`);
} else {
  const ours = localBlock(fs.readFileSync("anatomy_landmarks.js", "utf8"));
  const theirs = localBlock(fs.readFileSync(WEB, "utf8"));
  if (!ours || !theirs) {
    fail("could not extract a LOCAL_PAD_LANDMARKS block from one of the files");
  } else if (ours !== theirs) {
    // Report the first divergence so the diff is actionable rather than "they differ".
    let i = 0;
    while (i < ours.length && i < theirs.length && ours[i] === theirs[i]) i++;
    fail(
      `LOCAL_PAD_LANDMARKS diverges from the web at char ${i}\n` +
        `        ours:  ...${ours.slice(Math.max(0, i - 40), i + 60)}\n` +
        `        web:   ...${theirs.slice(Math.max(0, i - 40), i + 60)}`,
    );
  } else {
    console.log("  ok    LOCAL_PAD_LANDMARKS matches AnatomyScene.jsx verbatim");
  }
}

// ── 2 · Union shape ─────────────────────────────────────────────────────────

const EXPECTED_ZONES = 65;
const keys = Object.keys(PAD_LANDMARKS);
if (keys.length !== EXPECTED_ZONES) {
  fail(`expected ${EXPECTED_ZONES} unique zones, got ${keys.length}`);
} else {
  console.log(`  ok    ${keys.length} unique zones`);
}

const finite3 = (v) =>
  Array.isArray(v) && v.length === 3 && v.every((n) => Number.isFinite(n));

// A handful of local entries are deliberately asymmetric (below_patella_right /
// _left encode "outer half" vs "inner half", which is not a mirror). Everything
// built through pairedLandmarks() must mirror exactly.
const ASYMMETRIC = new Set(["below_patella_right", "below_patella_left"]);

for (const key of keys) {
  const zone = PAD_LANDMARKS[key];
  for (const side of ["right", "left"]) {
    const lm = zone[side];
    if (!lm) {
      fail(`${key}.${side} missing`);
      continue;
    }
    if (!finite3(lm.position)) fail(`${key}.${side}.position is not 3 finite numbers`);
    if (!finite3(lm.normal)) fail(`${key}.${side}.normal is not 3 finite numbers`);
  }
  if (zone.midline && !finite3(zone.midline.position)) {
    fail(`${key}.midline.position is not 3 finite numbers`);
  }
  if (ASYMMETRIC.has(key)) continue;
  const r = zone.right;
  const l = zone.left;
  if (!r || !l) continue;
  const mirrored =
    l.position[0] === -r.position[0] &&
    l.position[1] === r.position[1] &&
    l.position[2] === r.position[2] &&
    l.normal[0] === -r.normal[0] &&
    l.normal[1] === r.normal[1] &&
    l.normal[2] === r.normal[2];
  if (!mirrored) {
    fail(
      `${key} left is not the mirror of right ` +
        `(R ${JSON.stringify(r.position)} / L ${JSON.stringify(l.position)})`,
    );
  }
}
if (!failures) console.log("  ok    every zone is paired, finite and mirrored");

// ── 3 · Shared calibration wins over local on overlapping keys ──────────────

const sharedZones = new Set(ANATOMY_LANDMARKS.map((l) => l.zone));
let overlaps = 0;
for (const item of ANATOMY_LANDMARKS) {
  const zone = PAD_LANDMARKS[item.zone];
  if (!zone) {
    fail(`calibration zone "${item.zone}" is missing from PAD_LANDMARKS`);
    continue;
  }
  const [x, y, z] = zone.right.position;
  if (x !== item.absX || y !== item.y || z !== item.z) {
    fail(
      `zone "${item.zone}" did not take the shared calibration value ` +
        `(expected [${item.absX}, ${item.y}, ${item.z}], got [${x}, ${y}, ${z}])`,
    );
  }
  overlaps++;
}
if (!failures) {
  console.log(
    `  ok    all ${overlaps} shared calibration zones win over the local table`,
  );
}
console.log(
  `        (${sharedZones.size} shared + ${keys.length - sharedZones.size} local-only = ${keys.length})`,
);

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nlandmarks verified");
