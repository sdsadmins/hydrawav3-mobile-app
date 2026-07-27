// Shared muscle-name -> GLB mesh-name resolution, used by BOTH offline viewers:
// `viewer.src.js` (kinetic chain) and `pad_placement.src.js` (Sun/Moon pads).
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
export function resolveMuscleToMeshes(
  name,
  allMeshNames,
  normalizedLookup,
  meshSideMap,
) {
  const specifiedSide = extractSide(name);
  const staticMatches = getHighlightMeshNames([name]);
  let matched = [];
  for (const staticName of staticMatches) {
    if (allMeshNames.includes(staticName)) {
      matched.push(staticName);
      continue;
    }
    const actual = normalizedLookup.get(normalizeName(staticName));
    if (actual) matched.push(...actual);
  }
  matched = filterBySide(matched, specifiedSide, meshSideMap);
  if (matched.length > 0) return matched;
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
