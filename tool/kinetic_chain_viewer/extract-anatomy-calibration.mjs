// Regenerates `anatomy_calibration.js` from the web monorepo's
// `packages/placement-core/src/knowledge/anatomyCalibration.js`.
//
// Same pattern (and same reason) as the `mapping.js` extraction documented in
// README.md: the mobile viewer must ship the landmark table offline, but
// hand-transcribing 39 entries x 11 numeric fields is a transcription-error
// factory. Re-run this whenever the web calibration changes.
//
//   node extract-anatomy-calibration.mjs
//
// The `matcher` regexes are kept verbatim — they are valid JS literals and the
// muscle-name fallback path uses them.

import fs from "node:fs";
import path from "node:path";

const SRC = path.resolve(
  "../../../Hydrawave3/packages/placement-core/src/knowledge/anatomyCalibration.js",
);
const OUT = "anatomy_calibration.js";

const lines = fs.readFileSync(SRC, "utf8").split(/\r?\n/);

const versionLine = lines.find((l) =>
  l.includes("ANATOMY_LANDMARK_MAP_VERSION"),
);
if (!versionLine) throw new Error("ANATOMY_LANDMARK_MAP_VERSION not found");

const start = lines.findIndex((l) => l.includes("export const ANATOMY_LANDMARKS = ["));
if (start < 0) throw new Error("ANATOMY_LANDMARKS not found");

let end = -1;
for (let i = start + 1; i < lines.length; i++) {
  if (/^\];\s*$/.test(lines[i])) {
    end = i;
    break;
  }
}
if (end < 0) throw new Error("unterminated ANATOMY_LANDMARKS array");

const body = lines.slice(start, end + 1).join("\n");
const count = (body.match(/^\s{4}key:/gm) || []).length;

fs.writeFileSync(
  OUT,
  `// AUTO-GENERATED — do not edit by hand.
// Source: Hydrawave3/packages/placement-core/src/knowledge/anatomyCalibration.js
// Regenerate: node extract-anatomy-calibration.mjs
//
// ${count} calibrated landmarks shared with the web AnatomyScene. The GLB and its
// normalization (BODY_TARGET_HEIGHT 4.22 / BODY_TARGET_CENTER_Y 0.24) are
// identical on both sides, so these coordinates transfer without adjustment.

${versionLine}

${body}
`,
);

console.log(`wrote ${OUT} — ${count} landmarks`);
