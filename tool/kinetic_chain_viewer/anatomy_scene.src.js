// The high-fidelity AnatomyScene port — Sun/Moon pad placement on the Z-Anatomy
// model, for the Performance pad map and the Recovery 3D placement screen.
//
// Bundled to `assets/3d/anatomy_scene.bundle.js`, hosted by `anatomy_scene.html`
// over the app's localhost server, driven from `AnatomySceneView` (Dart).
//
// ── Relationship to `pad_placement.src.js` ─────────────────────────────────
// That file is the FIRST, simpler port and is deliberately untouched: it stays
// on disk as the per-screen rollback path behind `anatomy_scene_flag.dart`.
// This file is a much closer port of
// Hydrawave3/apps/web/src/components/AnatomyScene.jsx and adds, versus that one:
//
//   • per-mesh anatomy materials (11 colour families) — which is what makes
//     real X-ray dimming and per-mesh highlight possible at all
//   • `transparentBody` X-ray, `focusSetIndex` + `dimUnselected` focus mode
//   • Okabe-Ito per-set colours, `colorBySet` badge encoding
//   • labelled Sun→Moon parabolic set arcs (`showSetLinks`)
//   • muscle-highlight ellipses and badge cluster ring-packing
//   • pre-derived mesh anchors, so "proximal hamstring origin" lands at the TOP
//     of the hamstring rather than at its centroid
//   • tap-to-select (the touch replacement for the web's hover)
//
// and fixes three defects carried by the older viewer:
//
//   1. pads used `depthTest:false`, so a pad on the back showed THROUGH the
//      torso. Web parity is `depthTest:true` + polygonOffset.
//   2. pads were a 0.15-diameter circle; the web pad is a 0.13 square plane.
//   3. the surface-snap raycast was unbounded and whole-scene, so an arm
//      crossing the ray captured the pad. Web parity is origin +normal*0.55,
//      far 1.15, target-meshes-first, reject hits >0.08 away.
//
// ── Deliberate deviations from the web ─────────────────────────────────────
//   • Transparent canvas + `setBackground()`, and NO floor disc: the mobile
//     chrome is light, and the web's opaque 0x0e1316 + grey floor reads as a
//     smudge on it.
//   • Unmapped pads draw NOTHING and are reported on `window.__unmapped`. The
//     web silently falls back to `low_back_l23`; the mobile screens badge the
//     row instead, which is honest and already wired.
//   • `nearestBodySurfaceInMeshes` (O(all vertices) per unresolved marker) and
//     `resolvedMeshCentroid` (~150 verts x 8 meshes on EVERY refresh) are not
//     ported — seconds-scale jank in an Android WebView. Their jobs are done by
//     the anchor table and a cheap bounding-box tier instead.
//   • React chrome (toolbar, guide panel, muscle legend) stays in Flutter.
//   • The imperative `host.__hydraScene` handle becomes `window.*` calls,
//     because only JSON crosses the evaluateJavascript bridge.
//
// Bridge in : renderAnatomyMarkers, setViewOptions, setActiveMarkers, setLabels,
//             setHighlight, setView, setBodyTapMode, setBackground, focusCamera,
//             zoomIn, zoomOut, resetView, getViewerState
// Flags out : __ready, __webglError, __unmapped, __viewerVersion
// Events out: flutter_inappwebview.callHandler('anatomyEvent', {...})

import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

import {
  DEFAULT_LANDMARK,
  resolveLandmark,
} from "./anatomy_landmarks.js";
import { perfSetColor, perfSetColorCss } from "./set_colors.js";
import {
  anchorCount,
  loadMeshAnchors,
  padAnchorOverride,
} from "./mesh_anchors.js";
import {
  buildMeshSideMap,
  buildNormalizedLookup,
  collectAllMeshNames,
  resolveMuscleToMeshes,
} from "./muscle_resolve.js";

// Bumped whenever the bridge contract changes. AnatomySceneView reads it and
// logs a mismatch, so a stale bundle (someone pulled the Dart change without
// re-running `npm run build:anatomy`) surfaces as one line instead of a blank
// WebView nobody is watching.
const VIEWER_VERSION = "anatomy-scene-v1";

const MODEL_PATH = "z-anatomy-muscles.glb"; // relative to the localhost root
const DRACO_DECODER_PATH = "draco/";

// The landmark tables are expressed in the space this normalization establishes.
// Identical to the web; changing either breaks every pad position.
const BODY_TARGET_HEIGHT = 4.22;
const BODY_TARGET_CENTER_Y = 0.24;

const PAD_SIZE = 0.13;
const BADGE_CLUSTER_DISTANCE = PAD_SIZE * 1.45;

// Role colours — identical to the web so a Sun muscle is the same red in both
// clients. Set identity is NOT encoded here; it lives on the arc and the badge.
//
// These are now the ONLY colours painted onto the body. The mint
// `HIGHLIGHT_COLOR` (0x9af5d2) that used to serve as the badge-mode Moon tint is
// gone with the branch that used it — one role, one colour, every pad style.
const PERF_SUN_COLOR = 0xff3b30; // red
const PERF_MOON_COLOR = 0x2f80ff; // blue
const PERF_SUN_EMISSIVE = 0x4d0f0b;
const PERF_MOON_EMISSIVE = 0x0a2246;

// X-ray budget. Dimming every one of the ~244 meshes means depth-sorting them
// all every frame, which is where a mid-range Android WebView actually stutters.
// Only meshes within this radius of the marker cluster are dimmed; the rest stay
// opaque, which cuts transparent draws by roughly 80% and is visually
// indistinguishable because the far ones are not between the camera and a pad.
const XRAY_RADIUS = 1.2;

// ---------------------------------------------------------------------------
// Module state
// ---------------------------------------------------------------------------

let renderer;
let scene;
let camera;
let controls;
let markerGroup;
let bodyRoot = null;
let canvas;

let allMeshNames = [];
let normalizedLookup = null;
let meshSideMap = null;
let meshByName = new Map();

let anchorsReady = false;
let anchorsHit = 0;
let anchorsTotal = 0;

let highlightedMuscles = [];
let activeMarkers = [];
let labelsVisible = true;
let bodyTapMode = false;
let currentView = "front";
let hasAutoFocused = false;

// One options object, mirroring the web's single `viewOptsRef`. The Dart side
// sends all of it in one `setViewOptions` call rather than six separate
// evaluateJavascript round-trips.
const viewOpts = {
  padStyle: "badge", // 'badge' | 'muscle'
  colorBySet: false,
  showSetLinks: false,
  transparentBody: false,
  focusSetIndex: null,
  dimUnselected: false,
};

window.__ready = false;
window.__webglError = false;
window.__markers = [];
window.__unmapped = [];
window.__viewerVersion = VIEWER_VERSION;

// ---------------------------------------------------------------------------
// Boot guards
// ---------------------------------------------------------------------------

function hasWebGL() {
  try {
    const c = document.createElement("canvas");
    return !!(
      window.WebGLRenderingContext &&
      (c.getContext("webgl2") || c.getContext("webgl"))
    );
  } catch (e) {
    return false;
  }
}

function showError(message) {
  const el = document.getElementById("err");
  if (!el) return;
  el.textContent = message;
  el.style.display = "flex";
}

// ---------------------------------------------------------------------------
// Model normalization + per-mesh anatomy materials
// ---------------------------------------------------------------------------

function fitBodyObject(object) {
  const box = new THREE.Box3().setFromObject(object);
  const size = new THREE.Vector3();
  const center = new THREE.Vector3();
  box.getSize(size);
  box.getCenter(center);

  const scale = BODY_TARGET_HEIGHT / Math.max(size.y, 0.001);
  object.scale.setScalar(scale);
  object.position.set(
    -center.x * scale,
    BODY_TARGET_CENTER_Y - center.y * scale,
    -center.z * scale,
  );
}

function normalizeAnatomyText(value) {
  return String(value || "")
    .toLowerCase()
    // Split ALL separators (spaces, underscores, dots) into words FIRST. GLB
    // node names are underscore-joined ("Rectus_femoris_muscle") and an
    // underscore is a \w char, so the filler-word removals below only fire once
    // the text is space-delimited — otherwise "muscle"/"head"/"of" stay glued
    // into node names, the exact match fails, and every pad takes the fuzzy path.
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\brt?\b|\blt?\b/g, " ")
    .replace(/\bmuscle\b|\bhead\b|\bpart\b|\bof\b|\bthe\b|\band\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function anatomyFamilyForName(name) {
  const text = normalizeAnatomyText(name);
  if (/ligament/.test(text)) return "ligament";
  if (/tendon|aponeurosis|ring/.test(text)) return "tendon";
  if (/cartilage/.test(text)) return "cartilage";
  if (/hyoid|pharyngeal|arytenoid|crico|thyroid|tongue|digastric|stylo|mylo|genio/.test(text)) return "neckDeep";
  if (/capitis|colli|scalen|sternocleidomastoid|splenius|levator scapulae/.test(text)) return "neck";
  if (/deltoid|teres|infraspinatus|supraspinatus|subscapular|pectoralis|serratus|rhomboid|trapezius|latissimus/.test(text)) return "shoulder";
  if (/biceps|triceps|pronator|supinator|carpi|brach|flexor|extensor|palmar/.test(text)) return "arm";
  if (/glute|piriformis|psoas|iliacus|obturator|gemellus|quadratus femoris/.test(text)) return "hip";
  if (/femoris|vastus|sartorius|semitendinosus|semimembranosus|tibialis|fibularis|gastrocnemius|soleus|popliteus|adductor|peroneal/.test(text)) return "leg";
  if (/abdom|oblique|rectus|transversus|quadratus lumborum|serratus posterior|diaphragm/.test(text)) return "trunk";
  return "default";
}

const ANATOMY_PALETTE = {
  ligament: 0xc7b27f,
  tendon: 0xd8cbb6,
  cartilage: 0x8fb3b2,
  neckDeep: 0x8f6f78,
  neck: 0xb66f76,
  shoulder: 0xb86f67,
  arm: 0xb97963,
  hip: 0xaa6f63,
  leg: 0xb9855b,
  trunk: 0xbd7c61,
  default: 0xb57a68,
};

// ELEVEN SHARED MATERIALS, NOT 244.
//
// The web gives every mesh its own material. Doing that here would be ~244
// MeshStandardMaterials up front on a phone. Instead each colour family gets one
// shared material, and a mesh's material is cloned lazily the first time that
// mesh has to diverge from its family (highlight tint or X-ray dim) — see
// `ensureOwnMaterial`. At rest: 11 materials. In full X-ray: at most 244.
//
// Draw calls and shader programs are unaffected either way (the geometries were
// always separate, and the materials share defines so three.js compiles one
// program). The `__hlOwner` / `__dimOwner` guards, which are merely defensive in
// the web, are LOAD-BEARING here precisely because materials start out shared.
const familyMaterials = new Map();

function familyMaterial(family) {
  let material = familyMaterials.get(family);
  if (material) return material;
  const color = ANATOMY_PALETTE[family] || ANATOMY_PALETTE.default;
  material = new THREE.MeshStandardMaterial({
    color,
    roughness: family === "tendon" || family === "ligament" ? 0.9 : 0.84,
    metalness: 0,
    side: THREE.DoubleSide,
  });
  material.userData.baseColor = color;
  material.userData.baseEmissive = 0x060303;
  material.userData.baseEmissiveIntensity = 0.04;
  material.userData.anatomyFamily = family;
  material.emissive = new THREE.Color(material.userData.baseEmissive);
  material.emissiveIntensity = material.userData.baseEmissiveIntensity;
  familyMaterials.set(family, material);
  return material;
}

/**
 * Give `mesh` a material it exclusively owns, cloning off the shared family
 * material the first time. Idempotent — a mesh that already owns its material
 * keeps it, so repeated highlight/dim cycles never clone twice.
 */
function ensureOwnMaterial(mesh) {
  const m = mesh.material;
  if (!m || Array.isArray(m)) return m;
  if (m.userData.__ownerUuid === mesh.uuid) return m;
  const clone = m.clone();
  clone.userData = { ...m.userData, __ownerUuid: mesh.uuid, __dimCached: false };
  mesh.material = clone;
  clonedMaterialCount += 1;
  return clone;
}

let clonedMaterialCount = 0;

function prepareLoadedBody(object, name = "muscle_anatomy_glb") {
  object.name = name;
  object.traverse((child) => {
    if (!child.isMesh) return;
    if (child.geometry && !child.geometry.attributes.normal) {
      child.geometry.computeVertexNormals();
    }
    child.userData.anatomyName = child.name || child.parent?.name || "";
    const original = Array.isArray(child.material) ? child.material[0] : child.material;
    child.material = familyMaterial(
      anatomyFamilyForName(`${child.userData.anatomyName} ${original?.name || ""}`),
    );
    child.castShadow = false;
    child.receiveShadow = false;
  });
  fitBodyObject(object);
  return object;
}

// ---------------------------------------------------------------------------
// Canvas textures
// ---------------------------------------------------------------------------

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function makePadContactTexture(role) {
  const canvasEl = document.createElement("canvas");
  canvasEl.width = 384;
  canvasEl.height = 384;
  const ctx = canvasEl.getContext("2d");
  ctx.clearRect(0, 0, canvasEl.width, canvasEl.height);

  const isSun = role === "sun";
  const inner = isSun ? "#ffe17d" : "#bfe7ff";
  const edge = isSun ? "#ff8b3d" : "#57a8ff";

  ctx.save();
  ctx.shadowColor = isSun ? "rgba(255, 106, 33, 0.34)" : "rgba(35, 135, 255, 0.34)";
  ctx.shadowBlur = 18;
  ctx.fillStyle = isSun ? "rgba(255, 106, 33, 0.34)" : "rgba(35, 135, 255, 0.34)";
  roundRect(ctx, 54, 54, 276, 276, 42);
  ctx.fill();
  ctx.restore();

  ctx.lineWidth = 15;
  ctx.strokeStyle = edge;
  roundRect(ctx, 58, 58, 268, 268, 38);
  ctx.stroke();

  ctx.fillStyle = isSun ? "rgba(255, 106, 33, 0.16)" : "rgba(35, 135, 255, 0.16)";
  roundRect(ctx, 70, 70, 244, 244, 30);
  ctx.fill();

  // Plain role-coloured centre dot — role still reads via colour (orange/blue)
  // and the S1/M1 badge, without drawing a literal sun-ray or moon-crescent
  // shape on the patch.
  ctx.fillStyle = isSun ? "rgba(255, 207, 89, 0.72)" : "rgba(166, 220, 255, 0.72)";
  ctx.beginPath();
  ctx.arc(192, 192, 42, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = inner;
  ctx.beginPath();
  ctx.arc(192, 192, 25, 0, Math.PI * 2);
  ctx.fill();

  const texture = new THREE.CanvasTexture(canvasEl);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}

function markerSetNumber(marker) {
  return Number.isFinite(marker.setIndex) ? marker.setIndex + 1 : 1;
}

function markerRoleLabel(marker) {
  return marker.role === "sun" ? "Sun" : "Moon";
}

// Badge text. Default is the compact "S#/M#" code; the performance flow opts
// into the full "Sun"/"Moon" words via `padLabelStyle: "word"`. Per-marker, so
// a recovery marker (which never sets it) keeps the compact badge.
function padBadgeText(marker) {
  if (marker.padLabelStyle === "word") return markerRoleLabel(marker);
  return `${marker.role === "sun" ? "S" : "M"}${markerSetNumber(marker)}`;
}

function makePadBadgeTexture(marker, opts = {}) {
  const canvasEl = document.createElement("canvas");
  canvasEl.width = 192;
  canvasEl.height = 192;
  const ctx = canvasEl.getContext("2d");
  const isSun = marker.role === "sun";
  const label = padBadgeText(marker);
  ctx.clearRect(0, 0, canvasEl.width, canvasEl.height);

  if (opts.colorBySet) {
    // Set-coded colour; Sun vs Moon distinguished by FORM (Sun = solid disc,
    // Moon = ring) so the hue stays a per-set identity rather than a role one.
    const hex = perfSetColorCss(marker.setIndex);
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.34)";
    ctx.shadowBlur = 18;
    ctx.fillStyle = isSun ? hex : "rgba(12,16,18,0.82)";
    ctx.beginPath();
    ctx.arc(96, 96, 70, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
    ctx.lineWidth = isSun ? 8 : 16;
    ctx.strokeStyle = hex;
    ctx.beginPath();
    ctx.arc(96, 96, 70, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = isSun ? "#12100a" : hex;
    ctx.font = `900 ${label.length > 2 ? 44 : 58}px Arial`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(label, 96, 101);
    const setTexture = new THREE.CanvasTexture(canvasEl);
    setTexture.colorSpace = THREE.SRGBColorSpace;
    setTexture.anisotropy = 4;
    return setTexture;
  }

  const edge = isSun ? "#ff8b3d" : "#57a8ff";
  const fill = isSun ? "#fff1d0" : "#e2f1ff";
  const ink = isSun ? "#9f3d10" : "#155eaf";

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,.34)";
  ctx.shadowBlur = 18;
  ctx.fillStyle = fill;
  ctx.beginPath();
  ctx.arc(96, 96, 70, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  ctx.lineWidth = 12;
  ctx.strokeStyle = edge;
  ctx.beginPath();
  ctx.arc(96, 96, 70, 0, Math.PI * 2);
  ctx.stroke();

  ctx.fillStyle = ink;
  // Shrink the font for the longer "Sun"/"Moon" words so they fit the circle.
  ctx.font = `900 ${label.length > 2 ? 44 : 58}px Arial`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, 96, 101);

  const texture = new THREE.CanvasTexture(canvasEl);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}

// Camera-facing "Set N · Role" pill: dark plate, per-set colour accent, white text.
function makeSetLabelTexture(text, accentCss) {
  const canvasEl = document.createElement("canvas");
  canvasEl.width = 512;
  canvasEl.height = 128;
  const ctx = canvasEl.getContext("2d");
  ctx.clearRect(0, 0, canvasEl.width, canvasEl.height);
  ctx.fillStyle = "rgba(10,14,16,0.84)";
  roundRect(ctx, 6, 30, 500, 68, 22);
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = "rgba(255,255,255,0.18)";
  ctx.stroke();
  ctx.fillStyle = accentCss;
  roundRect(ctx, 16, 42, 12, 44, 6);
  ctx.fill();
  ctx.fillStyle = "#f4f8fa";
  ctx.font = "700 42px Arial";
  ctx.textAlign = "left";
  ctx.textBaseline = "middle";
  ctx.fillText(text, 44, 65);
  const texture = new THREE.CanvasTexture(canvasEl);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}

// ---------------------------------------------------------------------------
// Muscle name -> mesh resolution
// ---------------------------------------------------------------------------

// Alias keys match as WHOLE WORDS, never raw substrings — a short key otherwise
// bleeds into unrelated names (the 3-letter "lat" matched "lateral" inside
// "Vastus lateralis" and wrongly injected "latissimus dorsi", which is why there
// is no "lat" key here; "latissimus"/"lats" cover the real shorthand).
const MUSCLE_ALIAS_TERMS = {
  "external oblique": ["external abdominal oblique"],
  latissimus: ["latissimus dorsi"],
  lats: ["latissimus dorsi"],
  iliopsoas: ["psoas major", "iliacus"],
  psoas: ["psoas major"],
  piriformis: ["piriformis"],
  semitendinosus: ["semitendinosus"],
  "biceps femoris": ["biceps femoris"],
  hamstring: ["semitendinosus", "biceps femoris"],
  "gluteus maximus": ["gluteus maximus"],
  "gluteus medius": ["gluteus medius"],
  pectoralis: ["pectoralis minor", "pectoralis major"],
  "pectoralis minor": ["pectoralis minor"],
  infraspinatus: ["infraspinatus"],
  deltoid: ["deltoid"],
  "anterior deltoid": ["clavicular deltoid", "clavicular part deltoid"],
  "posterior deltoid": ["scapular spinal deltoid", "scapular spinal part deltoid"],
  serratus: ["serratus anterior", "serratus posterior"],
  "serratus anterior": ["serratus anterior"],
  rhomboid: ["rhomboid major", "rhomboid minor"],
  splenius: ["splenius capitis", "splenius colli"],
  levator: ["levator scapulae"],
  "pronator teres": ["pronator teres"],
  triceps: ["triceps brachii"],
  "tibialis anterior": ["tibialis anterior"],
  "tibialis posterior": ["tibialis posterior"],
  fibularis: ["fibularis longus", "fibularis brevis", "fibularis tertius"],
  "fibularis longus": ["fibularis longus"],
  "flexor digitorum brevis": ["flexor digitorum brevis"],
  "vastus medialis": ["vastus medialis"],
  "vastus lateralis": ["vastus lateralis"],
  "rectus femoris": ["rectus femoris"],
};

/**
 * The names to search the model for.
 *
 * `marker.label` MUST be the muscle name, not the written cue — the Dart
 * adapter maps `targetMuscles[0]` -> `label` and the mobile pad cue -> `cue`
 * for exactly this reason. A sentence here resolves to nothing and the pad
 * silently drops a tier.
 */
function markerMuscleSearchTerms(marker) {
  const base = [
    marker?.exactPlacement?.muscle,
    marker?.muscle,
    marker?.label,
    marker?.simple,
    marker?.landmarkAnchor,
  ]
    .filter(Boolean)
    .flatMap((value) => {
      const normalized = normalizeAnatomyText(value);
      const aliases = Object.entries(MUSCLE_ALIAS_TERMS)
        .filter(([key]) =>
          new RegExp(`\\b${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(normalized),
        )
        .flatMap(([, terms]) => terms);
      return [normalized, ...aliases.map(normalizeAnatomyText)];
    })
    .filter((value) => value.length >= 4);
  return Array.from(new Set(base));
}

function muscleMeshScore(meshName, terms, marker) {
  const name = normalizeAnatomyText(meshName);
  if (!name || !terms.length) return 0;
  const side = marker?.side === "left" ? " l" : marker?.side === "right" ? " r" : "";
  let best = 0;
  for (const term of terms) {
    if (!term) continue;
    if (name === term) best = Math.max(best, 1);
    else if (name.includes(term) || term.includes(name)) best = Math.max(best, 0.82);
    else {
      const tokens = term.split(" ").filter((token) => token.length > 2);
      const hits = tokens.filter((token) => name.includes(token)).length;
      if (tokens.length) best = Math.max(best, (hits / tokens.length) * 0.62);
    }
  }
  if (side && normalizeAnatomyText(meshName).endsWith(side.trim())) best += 0.08;
  return best;
}

function markerMuscleNames(marker) {
  if (Array.isArray(marker?.muscles) && marker.muscles.length) return marker.muscles;
  // `targetMuscles` is the older mobile mapper's field name. Accepted defensively
  // so a marker that bypassed the Dart adapter still resolves.
  if (Array.isArray(marker?.targetMuscles) && marker.targetMuscles.length) {
    return marker.targetMuscles;
  }
  const single = marker?.exactPlacement?.muscle || marker?.muscle || marker?.label;
  return single ? [single] : [];
}

/** Exact/alias resolution through the SHARED resolver, mapped to scene meshes. */
function resolvedModelMeshMatches(marker) {
  if (!bodyRoot) return [];
  const out = [];
  const seen = new Set();
  for (const name of markerMuscleNames(marker)) {
    const meshNames = resolveMuscleToMeshes(
      name,
      allMeshNames,
      normalizedLookup,
      meshSideMap,
      marker?.sideStrict ? marker.side : undefined,
    );
    for (const meshName of meshNames) {
      const mesh = meshByName.get(meshName);
      if (mesh && !seen.has(mesh.uuid)) {
        seen.add(mesh.uuid);
        out.push(mesh);
      }
    }
  }
  return out;
}

function targetMuscleMeshes(marker) {
  if (!bodyRoot) return [];
  const resolved = resolvedModelMeshMatches(marker);
  if (resolved.length) {
    if (marker) marker.__meshPath = "exact";
    return resolved.slice(0, 8);
  }
  const terms = markerMuscleSearchTerms(marker);
  if (!terms.length) {
    if (marker) marker.__meshPath = "none";
    return [];
  }
  const matches = [];
  bodyRoot.traverse((child) => {
    if (!child.isMesh || child.userData?.skipPadProjection) return;
    const score = muscleMeshScore(child.userData?.anatomyName || child.name, terms, marker);
    if (score >= 0.58) matches.push({ mesh: child, score });
  });
  if (marker) marker.__meshPath = matches.length ? "fuzzy" : "none";
  return matches
    .sort((a, b) => b.score - a.score)
    .slice(0, 8)
    .map((item) => item.mesh);
}

// Clinically deep/internal targets. A pad for these belongs on the nearest
// EXTERNAL surface via the landmark registry, never snapped onto an internal
// GLB mesh — otherwise the psoas pad ends up inside the abdomen.
function shouldUseTargetMuscleProjection(marker) {
  const text = markerMuscleSearchTerms(marker).join(" ");
  return !/psoas|iliacus|iliopsoas|piriformis|quadratus lumborum|diaphragm|transversus/.test(text);
}

const __meshCentroidCache = new WeakMap();
function meshWorldCentroid(mesh) {
  let c = __meshCentroidCache.get(mesh);
  if (c) return c;
  c = new THREE.Vector3();
  if (mesh.geometry) {
    if (!mesh.geometry.boundingBox) mesh.geometry.computeBoundingBox();
    mesh.geometry.boundingBox.getCenter(c);
    mesh.updateWorldMatrix(true, false);
    c.applyMatrix4(mesh.matrixWorld);
  }
  __meshCentroidCache.set(mesh, c);
  return c;
}

// ---------------------------------------------------------------------------
// Seed resolution — the five tiers
// ---------------------------------------------------------------------------

function vectorFrom(values, fallback) {
  const vector = new THREE.Vector3(...(values || fallback));
  if (vector.lengthSq() < 0.0001) vector.set(...fallback);
  return vector.normalize();
}

/**
 * Tier 3 — bounding-box seed from the marker's own resolved meshes.
 *
 * This is the cheap stand-in for the web's `resolvedMeshCentroid`, which samples
 * ~150 vertices across up to 8 meshes on EVERY refresh. Geometry bounding boxes
 * are computed once by three.js and cached, so this is effectively free, and
 * with the anchor table above it (tier 2) it only runs for muscles the 242-key
 * table misses.
 */
function bboxSeed(marker) {
  const meshes = targetMuscleMeshes(marker);
  if (!meshes.length) return null;
  const box = new THREE.Box3();
  for (const mesh of meshes) box.expandByObject(mesh);
  if (box.isEmpty()) return null;
  const centre = new THREE.Vector3();
  const size = new THREE.Vector3();
  box.getCenter(centre);
  box.getSize(size);

  // `positionAlongMuscle` still shifts along the muscle's vertical extent, which
  // is the same idea as the anchor table's `ends` lerp, just coarser.
  const offset = Number(marker.muscleOffset) || 0;
  if (offset) centre.y += offset * size.y * 0.5;

  const radius = Math.hypot(centre.x, centre.z);
  const normal =
    radius > 0.05
      ? new THREE.Vector3(centre.x / radius, 0, centre.z / radius)
      : new THREE.Vector3(0, 0, centre.z <= 0 ? -1 : 1);
  return { position: centre, normal, view: centre.z < 0 ? "back" : "front" };
}

/**
 * Where a pad wants to be, before the surface snap. Tiers, highest first:
 *
 *   1. `landmarkOverride` supplied on the marker — used verbatim.
 *   2. Pre-derived mesh anchors, offset along the muscle by `musclePosition`.
 *   3. A curated zone landmark + `refineLandmark` micro-offsets.
 *   4. A bounding-box centre over the marker's resolved meshes.
 *   5. Nothing — the caller reports it on `__unmapped` and draws no pad.
 *
 * Anchors sit ABOVE the curated zone deliberately: that mirrors the web, where
 * the marker builders bake anchors into `landmarkOverride` and so win tier 1.
 * The curated zone still wins over the bbox, because it is practitioner-
 * calibrated and the bbox is a guess.
 */
function seedLandmark(marker) {
  const base = resolveLandmark(marker); // tiers 1 and 3
  if (!base.fallback) {
    // An explicit override, or a real curated zone. Anchors may still improve a
    // curated zone when the marker names its own muscles (a recovery marker that
    // carries target muscles), which is what the web does too.
    if (marker.landmarkOverride) return base;
    const anchored = anchorSeed(marker);
    if (anchored) return { ...base, ...anchored, fallback: false };
    return base;
  }

  const anchored = anchorSeed(marker);
  if (anchored) return { ...base, ...anchored, fallback: false };

  const bbox = bboxSeed(marker);
  if (bbox) {
    return {
      ...base,
      position: bbox.position.toArray(),
      normal: bbox.normal.toArray(),
      view: bbox.view,
      fallback: false,
    };
  }
  return base; // still fallback:true -> unmapped
}

function anchorSeed(marker) {
  if (!anchorsReady) return null;
  const muscles = markerMuscleNames(marker);
  if (!muscles.length) return null;
  anchorsTotal += 1;
  const override = padAnchorOverride(
    {
      muscles,
      position: marker.exactPlacement?.musclePosition || marker.positionAlongMuscle,
      plane: marker.exactPlacement?.plane || marker.plane,
    },
    marker.side === "left" ? "left" : "right",
  );
  if (!override) return null;
  anchorsHit += 1;
  return {
    position: override.position,
    normal: override.normal,
    view: override.view,
  };
}

function surfaceNormalFromHit(hit, desiredNormal) {
  if (!hit?.face?.normal) return desiredNormal.clone();
  const normalMatrix = new THREE.Matrix3().getNormalMatrix(hit.object.matrixWorld);
  const surfaceNormal = hit.face.normal.clone().applyMatrix3(normalMatrix).normalize();
  if (surfaceNormal.dot(desiredNormal) < 0) surfaceNormal.multiplyScalar(-1);
  return surfaceNormal;
}

function selectProjectionHit(hits, desired, desiredNormal, maxDistanceSq) {
  let best = null;
  for (const hit of hits) {
    if (!hit.object?.isMesh || hit.object.userData?.skipPadProjection) continue;
    const surfaceNormal = surfaceNormalFromHit(hit, desiredNormal);
    const distanceSq = hit.point.distanceToSquared(desired);
    // Reject far occluders — an arm or the torso crossing the ray path. Leaving
    // the pad at its seed is safer than snapping it onto an unrelated mesh.
    if (distanceSq > maxDistanceSq) continue;
    const alignmentPenalty = Math.max(0, 0.92 - surfaceNormal.dot(desiredNormal)) * 0.08;
    const score = distanceSq + alignmentPenalty;
    if (!best || score < best.score) best = { ...hit, surfaceNormal, score };
  }
  return best;
}

/**
 * Snap a seed onto the real body surface.
 *
 * Ray budget is the web's, and it matters: origin is pushed OUT along the
 * normal by 0.55 and the ray is capped at 1.15, target meshes are tried before
 * the whole body, and hits further than 0.08 from the seed are rejected. The
 * older mobile viewer fired an unbounded whole-scene ray from +normal*1.2 and
 * took the first hit, which is how a crossing arm captured a pad.
 */
function projectSeed(landmark, marker) {
  const desired = new THREE.Vector3(...landmark.position);
  const desiredNormal = vectorFrom(landmark.normal, DEFAULT_LANDMARK.normal);
  if (!bodyRoot) {
    return { position: desired, normal: desiredNormal, snapped: false, hitObject: null };
  }

  bodyRoot.updateWorldMatrix(true, true);
  const origin = desired.clone().addScaledVector(desiredNormal, 0.55);
  const inward = desiredNormal.clone().multiplyScalar(-1);
  const raycaster = new THREE.Raycaster(origin, inward, 0, 1.15);
  const targetMeshes = shouldUseTargetMuscleProjection(marker) ? targetMuscleMeshes(marker) : [];
  const targetHits = targetMeshes.length ? raycaster.intersectObjects(targetMeshes, true) : [];
  const hits = targetHits.length ? targetHits : raycaster.intersectObject(bodyRoot, true);
  const hit = selectProjectionHit(hits, desired, desiredNormal, 0.08);

  if (hit) {
    const normal = hit.surfaceNormal || desiredNormal;
    return {
      position: hit.point.clone().addScaledVector(normal, 0.004),
      normal,
      snapped: true,
      hitObject: hit.object,
    };
  }

  // One relaxed retry instead of the web's O(all vertices) nearest-vertex scan:
  // a longer ray with no distance reject. If that misses too, the seed itself is
  // already on or very near the body, so use it rather than burning frames.
  const relaxed = new THREE.Raycaster(
    desired.clone().addScaledVector(desiredNormal, 1.2),
    inward,
    0,
    2.5,
  );
  const relaxedHit = selectProjectionHit(
    relaxed.intersectObject(bodyRoot, true),
    desired,
    desiredNormal,
    Infinity,
  );
  if (relaxedHit) {
    const normal = relaxedHit.surfaceNormal || desiredNormal;
    return {
      position: relaxedHit.point.clone().addScaledVector(normal, 0.004),
      normal,
      snapped: true,
      hitObject: relaxedHit.object,
    };
  }

  return { position: desired, normal: desiredNormal, snapped: false, hitObject: null };
}

// ---------------------------------------------------------------------------
// Marker geometry
// ---------------------------------------------------------------------------

function orientToNormal(object, normal) {
  object.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), normal);
}

function markerIdentity(marker) {
  return [
    marker.setIndex ?? 0,
    marker.role,
    marker.zone,
    marker.side,
    marker.landmarkKey,
    marker.label,
  ].join("|");
}

function markerClusterKey(marker) {
  return [
    marker.visualAnchorId,
    marker.landmarkKey,
    marker.exactPlacement?.landmarkAnchor,
    marker.exactPlacement?.muscle,
    marker.zone,
    marker.side,
  ]
    .filter(Boolean)
    .join("|");
}

function highlightSize(marker) {
  const highlight = marker.exactPlacement?.highlight || {};
  const region = String(marker.exactPlacement?.region || marker.zone || "").toLowerCase();
  const defaultRadius = /thoracolumbar|lumbar|lat|oblique|back/.test(region)
    ? 0.2
    : /hip|glute|hamstring/.test(region)
      ? 0.18
      : /shoulder|deltoid|teres|infraspinatus|pectoralis/.test(region)
        ? 0.15
        : /foot|ankle/.test(region)
          ? 0.13
          : 0.14;
  return {
    x: Number(highlight.radiusX || defaultRadius * 1.25),
    y: Number(highlight.radiusY || defaultRadius * 0.82),
  };
}

function addMuscleHighlight(group, marker, position, normal, opts) {
  const size = highlightSize(marker);
  // Same rule as the mesh tint: the halo sits ON the body, so it carries role
  // and nothing else. Sun red / Moon blue, whatever the pad style or the focused
  // set — see the note in setMeshMaterialHighlight.
  const color = marker.role === "sun" ? PERF_SUN_COLOR : PERF_MOON_COLOR;
  const mesh = new THREE.Mesh(
    new THREE.CircleGeometry(1, 64),
    new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity: 0.42,
      depthTest: false,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.NormalBlending,
      polygonOffset: true,
      polygonOffsetFactor: -10,
      polygonOffsetUnits: -10,
    }),
  );
  mesh.scale.set(size.x, size.y, 1);
  mesh.position.copy(position).addScaledVector(normal, 0.003);
  orientToNormal(mesh, normal);
  mesh.renderOrder = 18;
  mesh.visible = false;
  mesh.userData = { type: "muscle-highlight", marker, markerIdentity: markerIdentity(marker) };
  group.add(mesh);
}

function addFallbackPad(group, marker, position, normal) {
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(PAD_SIZE, PAD_SIZE),
    new THREE.MeshBasicMaterial({
      map: makePadContactTexture(marker.role),
      transparent: true,
      // depthTest TRUE is the occlusion fix: a pad on the back of the body is
      // hidden by the torso when the camera faces front, exactly as in the web.
      // The old viewer used false, so every pad showed through.
      depthTest: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -8,
      polygonOffsetUnits: -8,
      side: THREE.DoubleSide,
    }),
  );
  mesh.position.copy(position).addScaledVector(normal, 0.006);
  orientToNormal(mesh, normal);
  mesh.renderOrder = 20;
  mesh.userData = { type: "pad", marker, markerIdentity: markerIdentity(marker) };
  group.add(mesh);
}

function tangentForNormal(normal) {
  const up = new THREE.Vector3(0, 1, 0);
  const tangent = new THREE.Vector3().crossVectors(up, normal);
  if (tangent.lengthSq() < 0.0001) tangent.set(1, 0, 0);
  return tangent.normalize();
}

function bitangentForNormal(normal, tangent) {
  const bitangent = new THREE.Vector3().crossVectors(normal, tangent);
  if (bitangent.lengthSq() < 0.0001) bitangent.set(0, 1, 0);
  return bitangent.normalize();
}

// Badges for pads that landed on top of each other get packed into rings of six
// around the shared point, so a bilateral set of four does not render as one
// illegible stack.
function badgeOffsetForLayout(normal, marker, layout = {}) {
  const tangent = tangentForNormal(normal);
  const bitangent = bitangentForNormal(normal, tangent);
  const clusterSize = Number(layout.clusterSize || layout.clusterCount || 1);

  if (clusterSize <= 1) {
    const lane = Number(marker.setIndex || 0);
    const roleSign = marker.role === "sun" ? 1 : -1;
    return tangent.multiplyScalar(roleSign * (0.07 + Math.min(lane, 4) * 0.02));
  }

  const ring = Number(layout.clusterRing || 0);
  const index = Number(layout.clusterIndex || 0);
  const ringCount = Math.max(1, Number(layout.clusterCount || clusterSize));
  const ringOffset = ring % 2 ? Math.PI / ringCount : 0;
  const angle = -Math.PI / 2 + (index / ringCount) * Math.PI * 2 + ringOffset;
  const radius = Math.min(0.24, 0.095 + ringCount * 0.012 + ring * 0.045);
  return tangent
    .multiplyScalar(Math.cos(angle) * radius)
    .add(bitangent.multiplyScalar(Math.sin(angle) * radius));
}

function addPadBadge(group, marker, position, normal, layout, opts) {
  const sprite = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map: makePadBadgeTexture(marker, opts),
      transparent: true,
      depthTest: false,
      depthWrite: false,
    }),
  );
  sprite.position
    .copy(position)
    .addScaledVector(normal, 0.052)
    .add(badgeOffsetForLayout(normal, marker, layout));
  const scale = layout.clusterSize > 1 ? 0.094 : 0.105;
  sprite.scale.set(scale, scale, 1);
  sprite.renderOrder = 42;
  sprite.visible = labelsVisible;
  sprite.userData = { type: "pad-badge", marker, markerIdentity: markerIdentity(marker) };
  group.add(sprite);
}

function resolveMarkerPlacements(markers) {
  const unmapped = [];
  const resolved = [];

  markers.forEach((marker, order) => {
    const seed = seedLandmark(marker);
    if (seed.fallback) {
      // No tier could place it. Draw nothing and tell Flutter, so the written
      // cue is badged rather than a pad being invented somewhere plausible.
      unmapped.push(`${marker.setIndex ?? 0}:${marker.role}`);
      return;
    }
    const projected = projectSeed(seed, marker);
    resolved.push({
      marker,
      order,
      seed,
      position: projected.position,
      normal: projected.normal,
      clusterKey: markerClusterKey(marker),
      layout: { clusterIndex: 0, clusterCount: 1, clusterRing: 0, clusterSize: 1 },
    });
  });

  const clusters = [];
  resolved.forEach((item) => {
    const cluster = clusters.find((candidate) => {
      const keyMatch = item.clusterKey && candidate.keys.has(item.clusterKey);
      const closeMatch = candidate.center.distanceTo(item.position) <= BADGE_CLUSTER_DISTANCE;
      return keyMatch || closeMatch;
    });
    const target = cluster || { items: [], keys: new Set(), center: item.position.clone() };
    if (!cluster) clusters.push(target);
    target.items.push(item);
    if (item.clusterKey) target.keys.add(item.clusterKey);
    target.center.set(0, 0, 0);
    target.items.forEach((clusterItem) => target.center.add(clusterItem.position));
    target.center.divideScalar(target.items.length);
  });

  clusters.forEach((cluster) => {
    const ordered = [...cluster.items].sort((a, b) => {
      const setDiff = Number(a.marker.setIndex || 0) - Number(b.marker.setIndex || 0);
      if (setDiff) return setDiff;
      if (a.marker.role !== b.marker.role) return a.marker.role === "sun" ? -1 : 1;
      return a.order - b.order;
    });
    const clusterSize = ordered.length;
    ordered.forEach((item, index) => {
      item.layout = {
        clusterIndex: index % 6,
        clusterCount: Math.min(6, clusterSize - Math.floor(index / 6) * 6),
        clusterRing: Math.floor(index / 6),
        clusterSize,
      };
    });
  });

  window.__unmapped = unmapped;
  return resolved;
}

function addMarker(group, placement, opts) {
  const { marker, position, normal } = placement;
  // Muscle style: the target muscle mesh IS the indicator (coloured by role in
  // applyHighlights), so no disc, no patch, no badge. Set identity moves to the
  // labelled arc.
  if (opts.padStyle === "muscle") return;
  // The Sun/Moon-coloured skin halo (addMuscleHighlight) is Muscle Mode's own
  // look and was leaking into every other style too — the exact "half the body
  // still tinted like Muscle Mode after switching off" bug. The square S1/M1
  // badge chip (addPadBadge) is dropped too — badge/dot style now shows only
  // the plain contact patch, no colour and no text tag on the skin.
  addFallbackPad(group, marker, position, normal);
}

// ---------------------------------------------------------------------------
// Set arcs
// ---------------------------------------------------------------------------

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

/**
 * One labelled PARABOLIC ARC per set, bowing AROUND the body from the Sun pad to
 * the Moon pad. The bezier control point is pushed radially OUTWARD from the
 * body's vertical axis, so an anterior/posterior pair arcs around the side
 * rather than cutting straight through the torso.
 */
function addSetArcs(group, placements) {
  const bySet = new Map();
  for (const p of placements) {
    const si = Number(p.marker.setIndex) || 0;
    let e = bySet.get(si);
    if (!e) {
      e = { setIndex: si, setRole: p.marker.setRole || "" };
      bySet.set(si, e);
    }
    e[p.marker.role] = p.position;
    e[`${p.marker.role}N`] = p.normal;
    if (!e.setRole && p.marker.setRole) e.setRole = p.marker.setRole;
  }

  const labels = [];
  for (const e of bySet.values()) {
    if (!e.sun || !e.moon) continue; // a set with one resolved pad draws no arc
    const sun = e.sun.clone();
    const moon = e.moon.clone();
    const mid = sun.clone().add(moon).multiplyScalar(0.5);
    const sep = sun.distanceTo(moon);

    const radial = new THREE.Vector3(mid.x, 0, mid.z);
    const avgN = (e.sunN || new THREE.Vector3()).clone().add(e.moonN || new THREE.Vector3());
    let outward;
    if (radial.length() > 0.12) outward = radial.normalize();
    else if (avgN.length() > 0.1) outward = avgN.normalize();
    else outward = new THREE.Vector3(Math.sign(sun.x + moon.x) || 1, 0, 0);

    const push = clamp(sep * 1.15 + 0.18, 0.4, 1.05);
    const control = mid.clone().addScaledVector(outward, push);
    const curve = new THREE.QuadraticBezierCurve3(sun, control, moon);

    const arcColor = perfSetColor(e.setIndex);
    const tube = new THREE.Mesh(
      new THREE.TubeGeometry(curve, 44, 0.008, 8, false),
      new THREE.MeshBasicMaterial({
        color: arcColor,
        transparent: true,
        opacity: 0.55,
        depthTest: false,
        depthWrite: false,
      }),
    );
    tube.renderOrder = 26; // above the body, so it reads where it passes behind
    tube.userData = { type: "set-arc", setIndex: e.setIndex };
    group.add(tube);

    const roleWord = e.setRole ? e.setRole.charAt(0).toUpperCase() + e.setRole.slice(1) : "";
    labels.push({
      pos: curve.getPoint(0.5).addScaledVector(outward, 0.06),
      text: `Set ${e.setIndex + 1}${roleWord ? ` · ${roleWord}` : ""}`,
      accent: perfSetColorCss(e.setIndex),
    });
  }

  // De-collide: push apart any two labels closer than a label footprint. Sets
  // are usually far apart vertically, so this only fires on a close pair.
  const minDist = 0.42;
  for (let iter = 0; iter < 5; iter += 1) {
    for (let i = 0; i < labels.length; i += 1) {
      for (let j = i + 1; j < labels.length; j += 1) {
        const d = labels[i].pos.distanceTo(labels[j].pos);
        if (d > 1e-4 && d < minDist) {
          const dir = labels[j].pos.clone().sub(labels[i].pos).normalize();
          const shift = (minDist - d) / 2;
          labels[i].pos.addScaledVector(dir, -shift);
          labels[j].pos.addScaledVector(dir, shift);
        }
      }
    }
  }

  for (const label of labels) {
    const sprite = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map: makeSetLabelTexture(label.text, label.accent),
        transparent: true,
        depthTest: false,
        depthWrite: false,
      }),
    );
    sprite.position.copy(label.pos);
    sprite.scale.set(0.62, 0.62 * (128 / 512), 1);
    sprite.renderOrder = 46;
    sprite.visible = labelsVisible;
    sprite.userData = { type: "set-arc-label" };
    group.add(sprite);
  }
}

// ---------------------------------------------------------------------------
// Highlight + X-ray
// ---------------------------------------------------------------------------

function setMeshMaterialHighlight(mesh, active, marker, opts, strong) {
  const material = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
  if (!material?.color) return;
  // Sun/Moon anatomy tint is a Muscle Mode thing only. Unchecking Muscle Mode
  // means "just show me the chain" — the pin/badge markers carry the
  // placement instead, so the body mesh itself must stay at rest colour
  // rather than a dimmer version of the same red/blue tint.
  if (active && opts.padStyle === "muscle") {
    let color;
    let emissive;
    let intensity;
    // ROLE COLOUR ALWAYS WINS — Sun red, Moon blue — while in Muscle Mode.
    //
    // The muscle mesh answers exactly one question: is this pad the Sun or the
    // Moon. Anything else painted onto it is a second variable on the same
    // channel, and the anatomy is the last place that can carry one: a muscle
    // that changes colour reads as a different finding about the body, not as a
    // different selection in the UI.
    //
    // Two encodings used to sit here and both were wrong on this surface.
    // `colorBySet` repainted the SAME pad a different colour depending on which
    // set was focused, so Sun/Moon stopped being readable. The badge-mode
    // fallback used a third pair (amber/mint) that agreed with neither, so the
    // same placement changed colour merely by toggling Muscle Mode.
    //
    // Set identity is carried by the labelled arc, the chips and the legend —
    // three places that are free to use the palette because none of them is the
    // body. `colorBySet` and `perfSetColor` remain live for the arcs.
    //
    // Exactly two colours, never a third: a mesh belongs to whichever role
    // claimed it first (see `setActiveAnatomyMeshHighlight`) — no blending.
    // A mesh a chain's Sun and Moon both name (a shared-muscle "sandwich" pad
    // geometry) is a DATA/mapping question — see `mapping.js`'s
    // "lateral/medial head of gastrocnemius" entries — not something this
    // renderer should paper over with a mixed colour.
    color = marker?.role === "sun" ? PERF_SUN_COLOR : PERF_MOON_COLOR;
    emissive = marker?.role === "sun" ? PERF_SUN_EMISSIVE : PERF_MOON_EMISSIVE;
    intensity = strong ? 0.72 : 0.5;
    material.color.setHex(color);
    if (material.emissive) material.emissive.setHex(emissive);
    if ("emissiveIntensity" in material) material.emissiveIntensity = intensity;
  } else if (material.userData?.baseColor) {
    material.color.setHex(material.userData.baseColor);
    if (material.emissive) material.emissive.setHex(material.userData.baseEmissive || 0x060303);
    if ("emissiveIntensity" in material) {
      material.emissiveIntensity = material.userData.baseEmissiveIntensity ?? 0.04;
    }
  }
}

/**
 * Fade a mesh for X-ray. Caches transparent/opacity/depthWrite the first time it
 * dims so a later un-dim restores EXACTLY, and clears the cache flag on restore
 * so re-running is idempotent and cannot drift.
 */
function setMeshDim(mesh, dim) {
  const material = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
  if (!material) return;
  if (dim) {
    if (!material.userData.__dimCached) {
      material.userData.__dimTransparent = material.transparent;
      material.userData.__dimOpacity = material.opacity;
      material.userData.__dimDepthWrite = material.depthWrite;
      material.userData.__dimCached = true;
    }
    material.transparent = true;
    material.opacity = 0.2;
    material.depthWrite = false;
  } else if (material.userData.__dimCached) {
    material.transparent = material.userData.__dimTransparent;
    material.opacity = material.userData.__dimOpacity;
    material.depthWrite = material.userData.__dimDepthWrite;
    material.userData.__dimCached = false;
  }
}

let dimmedMeshCount = 0;

function setActiveAnatomyMeshHighlight(markerList, opts, strong, dim) {
  if (!bodyRoot) return;
  const list = Array.isArray(markerList) ? markerList.filter(Boolean) : [];
  // First marker in list order to name a mesh owns it — exactly web's
  // algorithm (`AnatomyScene.jsx`'s `setActiveAnatomyMeshHighlight`), no
  // special-casing. A mesh two markers of the same set both name (a
  // shared-muscle "sandwich" pad geometry, e.g. calf) is a mapping/data
  // question — see `mapping.js`'s "lateral/medial head of gastrocnemius"
  // entries, which give each pad its OWN single mesh so this collision
  // shouldn't arise for a properly-authored pair in the first place.
  const meshToMarker = new Map();
  for (const marker of list) {
    for (const mesh of targetMuscleMeshes(marker).slice(0, 6)) {
      if (!meshToMarker.has(mesh)) meshToMarker.set(mesh, marker);
    }
  }

  dimmedMeshCount = 0;
  // The target muscle is coloured (Muscle Mode's Sun/Moon tint) and must stay
  // vivid whether the rest of the body is solid or X-rayed — that's the ONE
  // thing exempt from the fade. Every other mesh fades across the WHOLE body
  // when `dim` (transparentBody) is on, not just a patch near the pads: this
  // toggle is meant to X-ray the entire body, target muscle aside.
  bodyRoot.traverse((child) => {
    if (!child.isMesh || child.userData?.skipPadProjection) return;
    const marker = meshToMarker.get(child);
    const wantDim = dim && !marker;
    const needsOwnMaterial = Boolean(marker) || wantDim;
    const alreadyOwned = child.material?.userData?.__ownerUuid === child.uuid;

    // Only clone when this mesh must actually diverge from its shared family
    // material — that is what keeps the resting cost at 11 materials.
    if (needsOwnMaterial && !alreadyOwned) ensureOwnMaterial(child);

    if (needsOwnMaterial || alreadyOwned) {
      setMeshMaterialHighlight(child, Boolean(marker), marker || undefined, opts, strong);
      setMeshDim(child, wantDim);
    }
    if (wantDim) dimmedMeshCount += 1;
  });
}

function applyHighlights() {
  // Every path below mutates materials or visibility, so ask for a frame once
  // here rather than at each of the returns.
  requestRender();
  if (viewOpts.padStyle === "muscle") {
    // Every marker's target muscles are coloured by role; selection and focus do
    // not change that (identity lives on the arc). When transparentBody is on,
    // non-target meshes fade so the coloured muscles show through — targets are
    // never dimmed, so they stay vivid in both modes.
    setActiveAnatomyMeshHighlight(
      window.__markers || [],
      viewOpts,
      false,
      Boolean(viewOpts.transparentBody),
    );
    return;
  }

  const list = activeMarkers.length ? activeMarkers : [];
  const focus = Boolean(viewOpts.dimUnselected) && viewOpts.focusSetIndex != null && list.length > 0;
  const ids = new Set(list.map(markerIdentity));

  if (markerGroup) {
    markerGroup.traverse((child) => {
      if (child.userData?.type !== "muscle-highlight") return;
      const visible = ids.has(child.userData.markerIdentity);
      child.visible = visible;
      if (viewOpts.dimUnselected && child.material) {
        child.material.opacity = visible && focus ? 0.62 : 0.42;
      }
    });
  }

  // Flat highlight list (the pad map's "Muscles" toggle) applies only when there
  // is no per-marker selection to express — otherwise the two would fight.
  if (!list.length && highlightedMuscles.length) {
    applyFlatHighlight();
    return;
  }
  setActiveAnatomyMeshHighlight(
    list,
    viewOpts,
    focus,
    focus || Boolean(viewOpts.transparentBody),
  );
}

function applyFlatHighlight() {
  if (!bodyRoot) return;
  const wanted = new Set();
  for (const name of highlightedMuscles) {
    for (const meshName of resolveMuscleToMeshes(
      name,
      allMeshNames,
      normalizedLookup,
      meshSideMap,
    )) {
      const mesh = meshByName.get(meshName);
      if (mesh) wanted.add(mesh.uuid);
    }
  }
  bodyRoot.traverse((child) => {
    if (!child.isMesh) return;
    const active = wanted.has(child.uuid);
    const alreadyOwned = child.material?.userData?.__ownerUuid === child.uuid;
    if (active && !alreadyOwned) ensureOwnMaterial(child);
    if (active || alreadyOwned) {
      setMeshMaterialHighlight(child, active, active ? { role: "moon" } : undefined, viewOpts, false);
      setMeshDim(child, false);
    }
  });
}

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------

function disposeObject(object) {
  object.traverse((child) => {
    if (child.geometry) child.geometry.dispose();
    if (child.material) {
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((material) => {
        if (material.map) material.map.dispose();
        material.dispose();
      });
    }
  });
}

function clearMarkerGroup(group) {
  [...group.children].forEach((child) => {
    group.remove(child);
    disposeObject(child);
  });
}

// ── Frame budget ───────────────────────────────────────────────────────────
//
// Renderer settings match the web exactly (antialias on, pixel ratio capped at
// 2). The ONE deviation is render-on-demand, and it is deliberately invisible:
// nothing in this scene animates by itself, so the web's continuous 60fps loop
// spends a full frame budget redrawing ~244 meshes into an identical image. We
// draw only when the camera actually moved or something changed; at rest the
// cost is one empty rAF callback.
//
// Resolution is NOT lowered during interaction. That was tried and reverted:
// changing pixel ratio reallocates the drawing buffer, which risks a hitch at
// the exact moment a gesture starts, and rotation feel is web parity here.
const MAX_PIXEL_RATIO = 2;

let needsRender = true;

function requestRender() {
  needsRender = true;
}

function initScene() {
  renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
    powerPreference: "high-performance",
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, MAX_PIXEL_RATIO));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 0.82;

  scene = new THREE.Scene();
  // No scene.background and no floor disc, unlike the web: the canvas is
  // transparent so the Flutter card colour shows through. setBackground() lets
  // a screen opt into an opaque colour.

  camera = new THREE.PerspectiveCamera(
    48,
    window.innerWidth / window.innerHeight,
    0.1,
    100,
  );
  camera.position.set(0, 0.55, 5.1);

  // EXACTLY the web's OrbitControls configuration (AnatomyScene.jsx:2112-2116).
  // These four lines are the ONLY properties it sets — rotateSpeed, zoomSpeed,
  // panSpeed, dampingFactor and `touches` are all left at their three.js
  // defaults (1.0 / 1.0 / 1.0 / 0.05 / ONE:ROTATE, TWO:DOLLY_PAN).
  //
  // Do not "tune" these. An earlier attempt set rotateSpeed 0.55 and
  // dampingFactor 0.12, which halved the rotation rate and more than doubled the
  // damping — the model read as barely rotating at all. Rotation feel is web
  // parity, not a preference.
  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.target.set(0, 0.55, 0);
  controls.minDistance = 2.9;
  controls.maxDistance = 7.0;

  // Render-on-demand wiring: any camera change asks for exactly one more frame.
  controls.addEventListener("change", requestRender);

  scene.add(new THREE.HemisphereLight(0xffffff, 0x1e2930, 1.35));
  const key = new THREE.DirectionalLight(0xffffff, 1.25);
  key.position.set(2.4, 3.4, 4);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x75bfff, 0.55);
  rim.position.set(-3, 2, -4);
  scene.add(rim);

  markerGroup = new THREE.Group();
  scene.add(markerGroup);

  window.addEventListener("resize", onResize);
  // Tap detection is pointerdown + pointerup with a movement threshold, NOT
  // pointerdown alone: on a touch screen every orbit gesture starts with a
  // pointerdown, so firing the pick there both stole the gesture and ran a
  // whole-body raycast at the start of every drag.
  canvas.addEventListener("pointerdown", onPointerDown);
  canvas.addEventListener("pointerup", onPointerUp);
  canvas.addEventListener("pointercancel", (event) => {
    activePointers.delete(event.pointerId);
    tapCandidate = null;
  });
  animate();
}

function onResize() {
  if (!renderer || !camera) return;
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  requestRender();
}

function animate() {
  requestAnimationFrame(animate);
  if (!renderer || !scene || !camera) return;
  // `update()` returns true while the camera is still moving (including damping
  // settling after a release), so the loop keeps drawing exactly as long as
  // something is actually changing and then goes quiet.
  const moving = controls ? controls.update() : false;
  if (!moving && !needsRender) return;
  needsRender = false;
  renderer.render(scene, camera);
}

function loadModel() {
  const loader = new GLTFLoader();
  const draco = new DRACOLoader();
  draco.setDecoderPath(DRACO_DECODER_PATH);
  draco.setDecoderConfig({ type: "wasm" });
  loader.setDRACOLoader(draco);

  loader.load(
    MODEL_PATH,
    (gltf) => {
      bodyRoot = prepareLoadedBody(gltf.scene);
      scene.add(bodyRoot);

      allMeshNames = collectAllMeshNames(bodyRoot);
      normalizedLookup = buildNormalizedLookup(allMeshNames);
      meshSideMap = buildMeshSideMap(bodyRoot);
      meshByName = new Map();
      bodyRoot.traverse((o) => {
        if (o.isMesh && !meshByName.has(o.name)) meshByName.set(o.name, o);
      });

      window.__ready = true;
      // Render anything Flutter injected before the model finished parsing.
      renderMarkers(window.__markers || []);
    },
    undefined,
    (err) => {
      console.error("[anatomy] GLB load failed:", err);
      // No procedural fallback body, unlike the web: the Flutter screens already
      // render a complete written pad list beside the stage, which is more
      // useful than a schematic mannequin with pads on it.
      window.__webglError = true;
      window.__ready = true;
      showError("Failed to load the 3D anatomy model.");
    },
  );
}

// ---------------------------------------------------------------------------
// Camera helpers
// ---------------------------------------------------------------------------

// ABSOLUTE camera positions, exactly as the web's `setView` uses
// (AnatomyScene.jsx:2334-2343). Not direction-preserving: the web snaps to a
// fixed spot and resets the target, so pressing "Back" always frames the body
// the same way regardless of how far you had zoomed or orbited.
//
// `left` / `right` are mobile-only — this app's switcher offers four views where
// the web offers three. They mirror the web's single `side` position.
const VIEW_POSITIONS = {
  front: [0, 0.55, 5.1],
  back: [0, 0.55, -5.1],
  side: [4.8, 0.55, 1.0],
  right: [4.8, 0.55, 1.0],
  left: [-4.8, 0.55, 1.0],
};

function applyView(view) {
  if (!camera || !controls) return;
  const pos = VIEW_POSITIONS[view] || VIEW_POSITIONS.front;
  camera.position.set(pos[0], pos[1], pos[2]);
  controls.target.set(0, 0.55, 0);
  controls.update();
}

/** Frame the resolved markers, inferring front / back / side from their views. */
function focusCameraOnMarkers() {
  const placements = lastPlacements;
  if (!placements.length || !camera || !controls) return;
  const box = new THREE.Box3();
  placements.forEach((p) => box.expandByPoint(p.position));
  const center = new THREE.Vector3();
  const size = new THREE.Vector3();
  box.getCenter(center);
  box.getSize(size);

  const views = placements.map((p) => p.seed.view);
  const counts = views.reduce((acc, v) => ({ ...acc, [v]: (acc[v] || 0) + 1 }), {});
  const mixedFrontBack = views.includes("front") && views.includes("back");
  const lateral =
    views.includes("side") ||
    (mixedFrontBack && Math.abs((counts.front || 0) - (counts.back || 0)) <= 1);

  const radius = Math.max(size.x, size.y, size.z, 0.82);
  const distance = clamp(radius * 2.4 + 2.0, 3.0, 6.6);
  const direction = new THREE.Vector3(0, 0, 1);
  if ((counts.back || 0) > (counts.front || 0) && !views.includes("side")) {
    direction.set(0, 0, -1);
  } else if (lateral) {
    direction.set(1, 0.05, 0.22).normalize();
  }

  controls.target.copy(center);
  camera.position.copy(center).addScaledVector(direction, distance);
  camera.position.y += 0.08;
  controls.update();
}

// ---------------------------------------------------------------------------
// Tap handling (the touch replacement for the web's hover)
// ---------------------------------------------------------------------------

function emit(payload) {
  try {
    window.flutter_inappwebview?.callHandler("anatomyEvent", payload);
  } catch (e) {
    // No host handler registered (e.g. opened in a plain browser) — ignore.
  }
}

// A press only counts as a tap if the finger barely moved and lifted quickly.
// Anything else is an orbit or a pinch and must be left alone.
const TAP_SLOP_PX = 10;
const TAP_MAX_MS = 500;
let tapCandidate = null;
// A Set rather than a counter: a pointercancel or a pointerup the WebView never
// delivers would leave a counter permanently above zero and silently disable
// tapping for the rest of the session.
const activePointers = new Set();

function onPointerDown(event) {
  activePointers.add(event.pointerId);
  // A second finger means a pinch, never a tap.
  if (activePointers.size > 1) {
    tapCandidate = null;
    return;
  }
  tapCandidate = { x: event.clientX, y: event.clientY, at: performance.now() };
}

function onPointerUp(event) {
  const candidate = tapCandidate;
  activePointers.delete(event.pointerId);
  tapCandidate = null;
  if (!candidate) return;
  const movedSq =
    (event.clientX - candidate.x) ** 2 + (event.clientY - candidate.y) ** 2;
  if (movedSq > TAP_SLOP_PX ** 2) return;
  if (performance.now() - candidate.at > TAP_MAX_MS) return;
  handleTap(event);
}

function handleTap(event) {
  if (!camera || !scene) return;
  const rect = canvas.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((event.clientX - rect.left) / rect.width) * 2 - 1,
    -((event.clientY - rect.top) / rect.height) * 2 + 1,
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);

  // Pads and badges first — they are what a finger is aiming at.
  const padHits = raycaster.intersectObjects(markerGroup.children, true);
  for (const hit of padHits) {
    const type = hit.object.userData?.type;
    if (type === "pad" || type === "pad-badge" || type === "muscle-highlight") {
      const marker = hit.object.userData.marker;
      emit({ type: "pick", marker });
      return;
    }
  }

  if (!bodyRoot) return;
  const bodyHits = raycaster.intersectObject(bodyRoot, true);
  const bodyHit = bodyHits.find((h) => h.object?.isMesh);
  if (!bodyHit) {
    emit({ type: "pick", marker: null });
    return;
  }

  if (bodyTapMode) {
    emit({
      type: "bodyTap",
      point: bodyHit.point.toArray(),
      meshName: bodyHit.object.userData?.anatomyName || bodyHit.object.name || "",
    });
    return;
  }

  // Tapping a coloured muscle names it — the touch equivalent of the web's
  // hover readout. Only meshes this render actually highlighted are reported,
  // so tapping plain anatomy stays silent rather than guessing.
  const info = muscleTapMap.get(bodyHit.object.uuid);
  if (info) {
    emit({
      type: "muscle",
      name: info.name,
      role: info.role,
      setIndex: info.setIndex,
    });
  }
}

let muscleTapMap = new Map();

function rebuildMuscleTapMap(markers) {
  const map = new Map();
  if (bodyRoot) {
    for (const marker of markers) {
      const meshes = targetMuscleMeshes(marker);
      const names = markerMuscleNames(marker);
      meshes.forEach((mesh, i) => {
        if (map.has(mesh.uuid)) return;
        map.set(mesh.uuid, {
          // Prefer the mesh's own anatomical name so the readout always matches
          // what was actually coloured, rather than a re-derived guess.
          name: mesh.userData?.anatomyName || names[i] || marker.muscle || marker.label || "",
          role: marker.role,
          setIndex: marker.setIndex,
        });
      });
    }
  }
  muscleTapMap = map;
}

// ---------------------------------------------------------------------------
// Render entry
// ---------------------------------------------------------------------------

let lastPlacements = [];

function renderMarkers(markers) {
  if (!window.__ready || !markerGroup) return;
  anchorsHit = 0;
  anchorsTotal = 0;

  clearMarkerGroup(markerGroup);
  const placements = resolveMarkerPlacements(markers);
  lastPlacements = placements;
  placements.forEach((placement) => addMarker(markerGroup, placement, viewOpts));
  if (viewOpts.showSetLinks) addSetArcs(markerGroup, placements);
  rebuildMuscleTapMap(markers);
  applyHighlights();
  requestRender();

  if (anchorsTotal) {
    console.log(`[anatomy] anchors ${anchorsHit}/${anchorsTotal} (${anchorCount()} in table)`);
  }
}

function setLabelVisibility(on) {
  labelsVisible = !!on;
  requestRender();
  if (!markerGroup) return;
  markerGroup.traverse((child) => {
    const type = child.userData?.type;
    if (type === "pad-badge" || type === "set-arc-label") child.visible = labelsVisible;
  });
}

// ---------------------------------------------------------------------------
// Bridge
// ---------------------------------------------------------------------------

window.renderAnatomyMarkers = function renderAnatomyMarkers(markers) {
  window.__markers = Array.isArray(markers) ? markers : [];
  renderMarkers(window.__markers);
};

/**
 * All six render-affecting options in one call, mirroring the web's single
 * `viewOptsRef`. Six separate bridge calls would each cost an evaluateJavascript
 * round-trip AND could render an intermediate state between them.
 */
window.setViewOptions = function setViewOptions(next) {
  if (!next || typeof next !== "object") return;
  let needsRebuild = false;
  for (const key of ["padStyle", "colorBySet", "showSetLinks"]) {
    if (key in next && viewOpts[key] !== next[key]) {
      viewOpts[key] = next[key];
      needsRebuild = true; // these change the geometry that gets built
    }
  }
  for (const key of ["transparentBody", "focusSetIndex", "dimUnselected"]) {
    if (key in next) viewOpts[key] = next[key];
  }
  if (needsRebuild) renderMarkers(window.__markers || []);
  else applyHighlights();
};

window.setActiveMarkers = function setActiveMarkers(markers) {
  activeMarkers = Array.isArray(markers) ? markers : [];
  applyHighlights();
};

window.setLabels = function setLabels(on) {
  setLabelVisibility(on);
};

window.setHighlight = function setHighlight(muscles) {
  highlightedMuscles = Array.isArray(muscles) ? muscles : [];
  applyHighlights();
};

window.setView = function setView(view) {
  currentView = String(view || "front");
  applyView(currentView);
};

window.setBodyTapMode = function setBodyTapMode(on) {
  bodyTapMode = !!on;
};

window.setBackground = function setBackground(css) {
  if (!scene) return;
  if (css) {
    scene.background = new THREE.Color(css);
    document.body.style.background = css;
  } else {
    scene.background = null;
    document.body.style.background = "transparent";
  }
  requestRender();
};

window.focusCamera = function focusCamera() {
  focusCameraOnMarkers();
  hasAutoFocused = true;
};

window.zoomIn = function zoomIn() {
  if (!camera || !controls) return;
  const dir = camera.position.clone().sub(controls.target);
  camera.position.copy(controls.target).addScaledVector(dir, 0.87);
  controls.update();
};

window.zoomOut = function zoomOut() {
  if (!camera || !controls) return;
  const dir = camera.position.clone().sub(controls.target);
  camera.position.copy(controls.target).addScaledVector(dir, 1.15);
  controls.update();
};

window.resetView = function resetView() {
  // Same as the web's front view — its reset button just calls setView("front").
  applyView("front");
};

/**
 * Diagnostics, asserted from Dart after injection. There is no JS test harness
 * here, so this IS the JS-side test surface — in particular `anchorsHit` vs
 * `anchorsTotal`, because a silent drop from the anchor tier to the bounding-box
 * tier looks identical on screen but places pads noticeably worse.
 */
window.getViewerState = function getViewerState() {
  return JSON.stringify({
    version: VIEWER_VERSION,
    ready: window.__ready,
    webglError: window.__webglError,
    view: currentView,
    padStyle: viewOpts.padStyle,
    colorBySet: viewOpts.colorBySet,
    showSetLinks: viewOpts.showSetLinks,
    transparentBody: viewOpts.transparentBody,
    focusSetIndex: viewOpts.focusSetIndex,
    dimUnselected: viewOpts.dimUnselected,
    labelsVisible,
    markers: (window.__markers || []).length,
    placed: lastPlacements.length,
    unmapped: window.__unmapped || [],
    anchorsHit,
    anchorsTotal,
    anchorsTable: anchorCount(),
    meshesDimmed: dimmedMeshCount,
    meshesCloned: clonedMaterialCount,
    autoFocused: hasAutoFocused,
  });
};

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

function boot() {
  canvas = document.getElementById("c");
  if (!hasWebGL()) {
    window.__webglError = true;
    window.__ready = true;
    showError("3D is not supported on this device.");
    return;
  }
  try {
    initScene();
  } catch (err) {
    console.error("[anatomy] scene init failed:", err);
    window.__webglError = true;
    window.__ready = true;
    showError("Couldn't start the 3D viewer.");
    return;
  }
  // Anchors and the GLB load in parallel; anchors are much smaller and land
  // first, so the first render already has them.
  loadMeshAnchors().then((count) => {
    anchorsReady = count > 0;
    if (anchorsReady && window.__ready) renderMarkers(window.__markers || []);
  });
  loadModel();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
