// Shared muscle-name -> GLB mesh-name resolution, used by ALL THREE offline
// viewers: `viewer.src.js` (kinetic chain), `pad_placement.src.js` (Sun/Moon
// pads) and `anatomy_scene.src.js` (the AnatomyScene port).
// Ported from the web `lib/zAnatomyModel.ts` + `lib/zAnatomyMapping.ts`.
//
// Extracted from viewer.src.js so the pad viewer can place a pad from real mesh
// geometry when a `landmark_anchor` doesn't map to a calibrated landmark. One
// copy means a name-matching fix lands in both viewers at once.
//
// Mesh naming (Terminologia Anatomica): `.l` / `.r` marks the side, multi-part
// muscles are several meshes, midline muscles carry no suffix.

import * as THREE from "three";
import { MAPPING } from "./mapping.js";
import muscleNameMap from "./muscle_name_map.json" with { type: "json" };

// ---------------------------------------------------------------------------
// muscleNameMap.json resolution (ported from Hydrawave3's muscleNameResolver.js)
//
// PRIMARY tier as of the muscleNameMap.json migration: `MAPPING` (mapping.js,
// generated from the older Hydrawav3-ai zAnatomyMapping.ts) is now a fallback
// behind this. Web's AnatomyScene.jsx already resolves through
// `resolveMuscleName` from @hydrawav3/placement-core; this is that same
// exact-match + alias-map lookup, minus the full muscleMeshMatcher fuzzy
// engine (left to the existing `fuzzyMatchMeshes` fallback below rather than
// porting a second fuzzy scorer).
//
// Model names here are SIDE-AGNOSTIC (no .l/.r) — side is resolved by
// `filterBySide`/`meshSideMap`, which this file already had for the fuzzy
// tier, so no change was needed there.
// ---------------------------------------------------------------------------

function normKey(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

const MODEL_MESH_NAMES = muscleNameMap.modelMeshNames || [];

const EXACT_INDEX = new Map(); // normalized model name -> canonical model name
for (const name of MODEL_MESH_NAMES) EXACT_INDEX.set(normKey(name), name);

const ALIAS_INDEX = new Map(); // normalized alias key -> { modelMeshNames, confidence }
for (const [key, entry] of Object.entries(muscleNameMap.aliases || {})) {
  ALIAS_INDEX.set(normKey(key), entry);
}

/**
 * Exact model-name / alias-map lookup against muscleNameMap.json's 244
 * side-agnostic names. Returns [] (not a guess) when neither tier hits —
 * callers fall through to the legacy MAPPING tier and then the fuzzy tier.
 */
function resolveFromMuscleNameMap(name) {
  const raw = String(name || "").trim();
  if (!raw) return [];
  const key = normKey(raw);

  const exact = EXACT_INDEX.get(key);
  if (exact) return [exact];

  const alias = ALIAS_INDEX.get(key);
  if (alias && Array.isArray(alias.modelMeshNames) && alias.modelMeshNames.length) {
    return alias.modelMeshNames;
  }

  return [];
}

// Already re-exported at the bottom of this file. `mesh_anchors.js` imports it
// so the 242 perf-mesh-anchor keys are indexed through the SAME normalizer the
// mesh resolver uses — a second copy of these rules would silently drift and
// take anchor lookups down with it.
function normalizeName(name) {
  return name
    .replace(/\s*\([A-Z]\d+-[A-Z]?\d+\)\s*/gi, " ")
    .replace(/multifidi/gi, "multifidus")
    .replace(/\.(l|r)$/, "")
    .replace(/_\d+$/, "")
    .replace(/_/g, " ")
    .toLowerCase()
    .trim();
}

function cleanDisplayName(name) {
  return name
    .replace(/\.(l|r)$/, "")
    .replace(/_\d+$/, "")
    .replace(/_/g, " ")
    .replace(/ muscle$/i, "")
    .replace(/^\(/, "")
    .replace(/\)$/, "")
    .replace(
      /^(Long|Short|Lateral|Medial|Ascending|Descending|Transverse) (head|part) of /i,
      "",
    )
    .trim();
}

function fuzzyMatchMeshes(muscleName, allMeshNames) {
  const lower = muscleName.toLowerCase().trim();
  if (!lower) return [];

  const stripped = lower
    .replace(/\s*\((?!left|right|bilateral).*?\)\s*/gi, "")
    .replace(
      /\s+(shortening|lengthening|restriction|inhibition|overload|tightness|weakness|compensation|dysfunction|tension|activation|overactivation|dominance)\s*$/i,
      "",
    )
    .trim();

  const results = [];

  const extraAliases = {
    iliopsoas: ["Psoas major", "Iliacus muscle"],
    "ilio-psoas": ["Psoas major", "Iliacus muscle"],
    quads: [
      "Rectus femoris muscle",
      "Vastus lateralis muscle",
      "Vastus medialis muscle",
      "Vastus intermedius muscle",
    ],
    hams: [
      "Long head of biceps femoris",
      "Short head of biceps femoris",
      "Semitendinosus muscle",
      "Semimembranosus muscle",
    ],
    gastroc: [
      "Lateral head of gastrocnemius",
      "Medial head of gastrocnemius",
    ],
    calves: [
      "Lateral head of gastrocnemius",
      "Medial head of gastrocnemius",
      "Soleus muscle",
    ],
    "it band": ["Iliotibial tract"],
    itb: ["Iliotibial tract"],
    tfl: ["Iliotibial tract"],
    traps: [
      "Descending part of trapezius muscle",
      "Transverse part of trapezius muscle",
      "Ascending part of trapezius muscle",
    ],
    lats: ["Latissimus dorsi muscle"],
    delts: [
      "Acromial part of deltoid muscle",
      "Clavicular part of deltoid muscle",
      "Scapular spinal part of deltoid muscle",
    ],
    pecs: [
      "Sternocostal head of pectoralis major muscle",
      "Clavicular head of pectoralis major muscle",
    ],
    abs: ["Rectus abdominis muscle"],
    scm: ["Sternocleidomastoid muscle"],
  };

  const aliasMatches = extraAliases[stripped];
  if (aliasMatches) {
    for (const stem of aliasMatches) {
      const stemNorm = normalizeName(stem);
      for (const meshName of allMeshNames) {
        const meshNorm = normalizeName(meshName);
        if (meshNorm.startsWith(stemNorm) || meshNorm === stemNorm) {
          results.push(meshName);
        }
      }
    }
    if (results.length > 0) return results;
  }

  for (const meshName of allMeshNames) {
    const meshNorm = normalizeName(meshName);
    if (
      meshNorm.includes(stripped) ||
      stripped.includes(meshNorm.replace(/ muscle$/, ""))
    ) {
      results.push(meshName);
    }
  }

  if (results.length === 0 && stripped.includes(" ")) {
    const words = stripped.split(/\s+/);
    for (const meshName of allMeshNames) {
      const meshNorm = normalizeName(meshName);
      if (words.every((w) => meshNorm.includes(w))) {
        results.push(meshName);
      }
    }
  }

  return results;
}

function collectAllMeshNames(scene) {
  const names = [];
  scene.traverse((obj) => {
    if (obj.isMesh) names.push(obj.name);
  });
  return names;
}

function getMeshSide(mesh) {
  let current = mesh;
  while (current) {
    if (current.name.endsWith(".l")) return "left";
    if (current.name.endsWith(".r")) return "right";
    current = current.parent;
  }
  const worldPos = new THREE.Vector3();
  mesh.getWorldPosition(worldPos);
  if (Math.abs(worldPos.x) < 0.01) return null;
  return worldPos.x > 0 ? "left" : "right";
}

function buildMeshSideMap(scene) {
  const map = new Map();
  scene.traverse((obj) => {
    if (obj.isMesh) map.set(obj.name, getMeshSide(obj));
  });
  return map;
}

function buildNormalizedLookup(meshNames) {
  const map = new Map();
  for (const name of meshNames) {
    const norm = normalizeName(name);
    if (!map.has(norm)) map.set(norm, []);
    map.get(norm).push(name);
  }
  return map;
}

function extractSide(muscleName) {
  const lower = muscleName.toLowerCase();
  if (lower.includes("(left)") || lower.startsWith("left ")) return "left";
  if (lower.includes("(right)") || lower.startsWith("right ")) return "right";
  return null;
}

function filterBySide(meshNames, side, meshSideMap) {
  if (!side) return meshNames;
  const hasSideSuffixes = meshNames.some(
    (name) => name.endsWith(".l") || name.endsWith(".r"),
  );
  if (hasSideSuffixes) {
    const filtered = meshNames.filter((meshName) => {
      if (side === "left") return meshName.endsWith(".l");
      if (side === "right") return meshName.endsWith(".r");
      return true;
    });
    if (filtered.length > 0) return filtered;
  }
  if (meshSideMap) {
    const filtered = meshNames.filter(
      (meshName) => meshSideMap.get(meshName) === side,
    );
    if (filtered.length > 0) return filtered;
  }
  return meshNames;
}

function expandMapping(m) {
  const names = [];
  if (m.both) {
    for (const stem of m.both) {
      if (
        stem === "Diaphragm" ||
        stem === "Linea alba" ||
        stem === "Transverse arytenoid muscle"
      ) {
        names.push(stem);
      } else {
        names.push(`${stem}.l`);
        names.push(`${stem}.r`);
      }
    }
  }
  if (m.left) for (const stem of m.left) names.push(`${stem}.l`);
  if (m.right) for (const stem of m.right) names.push(`${stem}.r`);
  return names;
}

function getZAnatomyMeshNames(muscleName) {
  let lower = muscleName.toLowerCase().trim();
  let sideFromParens = null;
  const parenMatch = lower.match(/\s*\((left|right)\)\s*$/);
  if (parenMatch) {
    sideFromParens = parenMatch[1];
    lower = lower.replace(/\s*\((left|right)\)\s*$/, "").trim();
  }

  if (lower.includes("/")) {
    const parts = lower.split("/").map((p) => p.trim());
    for (const part of parts) {
      const partWithSide = sideFromParens ? `${sideFromParens} ${part}` : part;
      const mapping = MAPPING[partWithSide] || MAPPING[part];
      if (mapping) {
        if (sideFromParens === "left")
          return expandMapping({ left: mapping.both || mapping.left || [] });
        if (sideFromParens === "right")
          return expandMapping({ right: mapping.both || mapping.right || [] });
        return expandMapping(mapping);
      }
    }
  }

  if (sideFromParens) {
    const withSidePrefix = `${sideFromParens} ${lower}`;
    const mappingWithSide = MAPPING[withSidePrefix];
    if (mappingWithSide) return expandMapping(mappingWithSide);
  }

  const mapping = MAPPING[lower];
  if (mapping) {
    if (sideFromParens === "left")
      return expandMapping({ left: mapping.both || mapping.left || [] });
    if (sideFromParens === "right")
      return expandMapping({ right: mapping.both || mapping.right || [] });
    return expandMapping(mapping);
  }

  for (const [key, m] of Object.entries(MAPPING)) {
    if (lower.includes(key) || key.includes(lower)) {
      if (sideFromParens === "left")
        return expandMapping({ left: m.both || m.left || [] });
      if (sideFromParens === "right")
        return expandMapping({ right: m.both || m.right || [] });
      return expandMapping(m);
    }
  }

  const stripped = lower
    .replace(/^(left|right)\s+/, "")
    .replace(/\s+(left|right)$/, "");
  const sideFromPrefix = lower.startsWith("left")
    ? "left"
    : lower.startsWith("right")
      ? "right"
      : sideFromParens;
  const strippedMapping = MAPPING[stripped];
  if (strippedMapping) {
    if (sideFromPrefix === "left")
      return expandMapping({
        left: strippedMapping.both || strippedMapping.left || [],
      });
    if (sideFromPrefix === "right")
      return expandMapping({
        right: strippedMapping.both || strippedMapping.right || [],
      });
    return expandMapping(strippedMapping);
  }

  return [];
}

function getHighlightMeshNames(muscles) {
  const result = new Set();
  for (const m of muscles) {
    for (const name of getZAnatomyMeshNames(m)) result.add(name);
  }
  return result;
}
/// The full pipeline for one clinical muscle name: static map -> normalized
/// lookup -> side filter -> fuzzy fallback. Returns GLB mesh names.
///
/// `preferredSide` ("left" | "right" | null) applies ONLY when the name does not state a side itself.
/// The web's `sideStrict` markers depend on it: a performance pad names a plain muscle
/// ("Gluteus medius muscle") and carries its side on the MARKER, so without this a one-sided chain
/// highlights both limbs and reads as bilateral.
export function resolveMuscleToMeshes(
  name,
  allMeshNames,
  normalizedLookup,
  meshSideMap,
  preferredSide = null,
) {
  // A side written into the name always wins — it is what the author actually asked for.
  const specifiedSide = extractSide(name) || preferredSide || null;

  // Expand a set of candidate mesh-name stems (side-agnostic OR pre-suffixed)
  // against the mesh names this GLB actually has, via the normalized lookup.
  const expandAgainstScene = (staticMatches) => {
    const out = [];
    for (const staticName of staticMatches) {
      if (allMeshNames.includes(staticName)) {
        out.push(staticName);
        continue;
      }
      const actual = normalizedLookup.get(normalizeName(staticName));
      if (actual) out.push(...actual);
    }
    return out;
  };

  // Tier 1: muscleNameMap.json exact/alias match — same source of truth the
  // web resolves through (resolveMuscleName). Side-agnostic names; filterBySide
  // (already geometry-aware) picks the right .l/.r mesh below.
  let matched = filterBySide(
    expandAgainstScene(resolveFromMuscleNameMap(name)),
    specifiedSide,
    meshSideMap,
  );
  if (matched.length > 0) return matched;

  // Tier 2: legacy static MAPPING (mapping.js) — kept as a fallback for
  // anything muscleNameMap.json doesn't cover yet, rather than dropped.
  matched = filterBySide(
    expandAgainstScene(getHighlightMeshNames([name])),
    specifiedSide,
    meshSideMap,
  );
  if (matched.length > 0) return matched;

  // Tier 3: fuzzy fallback, same as before the migration.
  let fuzzy = fuzzyMatchMeshes(name, allMeshNames);
  fuzzy = filterBySide(fuzzy, specifiedSide, meshSideMap);
  return fuzzy;
}

export {
  normalizeName,
  cleanDisplayName,
  fuzzyMatchMeshes,
  collectAllMeshNames,
  getMeshSide,
  buildMeshSideMap,
  buildNormalizedLookup,
  extractSide,
  filterBySide,
  expandMapping,
  getZAnatomyMeshNames,
  getHighlightMeshNames,
};
