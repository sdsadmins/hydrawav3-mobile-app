// Offline vanilla-three.js port of the web `ZAnatomyViewer` (Hydrawav3-ai).
//
// This reproduces the web kinetic-chain 3D view for the Flutter mobile app,
// bundled into `assets/3d/viewer.bundle.js` and hosted in an in-app WebView.
// It is a FORK: the muscle-name matching (MAPPING + normalize + fuzzy + side),
// the ANATOMY_COLORS/materials, camera fit, chain line and labels are ported
// near-verbatim from the web `lib/zAnatomyModel.ts`, `lib/zAnatomyMapping.ts`
// and the active `components/ai/ZAnatomyViewer.tsx`. Keep this in sync manually
// when the web viewer changes, then re-run `npm run build`.
//
// Entry point Flutter calls: window.renderPattern({ primaryMuscles,
// secondaryMuscles, stabilizingMuscles, kineticChainPathway, spinalSegments,
// hypothesisLabel }). Flags read by Flutter: window.__ready, window.__webglError.

import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

// ---------------------------------------------------------------------------
// Colors (verbatim from zAnatomyModel.ts ANATOMY_COLORS)
// ---------------------------------------------------------------------------
const COLORS = {
  primary: "#EF4444",
  secondary: "#F59E0B",
  stabilizing: "#10B981",
  chain: "#60A5FA",
  spinal: "#8B5CF6",
  ghost: "#b8a99a",
  sun: "#FBBF24",
  moon: "#6366F1",
  chainLine: "#06B6D4",
  chainGlow: "#FFFFFF",
};

const MODEL_PATH = "z-anatomy-muscles.glb"; // relative to the localhost root

// Vertebral label positions on the model (ported verbatim from the web
// ZAnatomyViewer VERTEBRA_POSITIONS). Spinal "segments" like "L4-L5" don't map
// to muscle meshes, so the Spine toggle renders these L1–S1 badges instead,
// highlighting the AI-identified segments (matches the web behavior).
const VERTEBRA_POSITIONS = {
  L1: { y: 1.08, z: -0.06 },
  L2: { y: 1.02, z: -0.06 },
  L3: { y: 0.96, z: -0.06 },
  L4: { y: 0.9, z: -0.06 },
  L5: { y: 0.84, z: -0.06 },
  S1: { y: 0.78, z: -0.06 },
};
const ALL_VERTEBRAE = ["L1", "L2", "L3", "L4", "L5", "S1"];

// ---------------------------------------------------------------------------
// Name matching + static mapping now live in the shared resolver, imported by
// this viewer and the pad-placement viewer alike.
// ---------------------------------------------------------------------------
import {
  cleanDisplayName,
  collectAllMeshNames,
  buildMeshSideMap,
  buildNormalizedLookup,
  resolveMuscleToMeshes,
} from "./muscle_resolve.js";

// ---------------------------------------------------------------------------
// Scene setup
// ---------------------------------------------------------------------------
const canvas = document.getElementById("c");
let renderer, scene, camera, controls;
let modelScene = null;
let allMeshNames = [];
let normalizedLookup = new Map();
let meshSideMap = new Map();
let overlayGroup = null; // holds chain line + labels, cleared per render
let materials = null;
// Web ZAnatomyViewer defaults: labels + chain flow line start hidden; Flutter's
// native toggle chips drive these through window.setLabels / window.setChain.
let labelsVisible = false;
let chainVisible = false;

window.__ready = false;
window.__webglError = false;

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

function createHighlightMaterials() {
  const std = (color, emissiveIntensity, extra = {}) =>
    new THREE.MeshStandardMaterial({
      color,
      roughness: 0.35,
      metalness: 0.05,
      emissive: new THREE.Color(color),
      emissiveIntensity,
      side: THREE.DoubleSide,
      ...extra,
    });
  return {
    primary: std(COLORS.primary, 0.5),
    secondary: std(COLORS.secondary, 0.4),
    stabilizing: std(COLORS.stabilizing, 0.35),
    chain: std(COLORS.chain, 0.4),
    spinal: std(COLORS.spinal, 0.6, { roughness: 0.3, metalness: 0.1 }),
    ghost: new THREE.MeshStandardMaterial({
      color: COLORS.ghost,
      roughness: 0.6,
      metalness: 0,
      transparent: true,
      opacity: 0.25,
      depthWrite: false,
      side: THREE.DoubleSide,
    }),
    neutral: new THREE.MeshStandardMaterial({
      color: "#d7a67b",
      roughness: 0.45,
      metalness: 0,
      transparent: true,
      opacity: 0.85,
      side: THREE.DoubleSide,
    }),
  };
}

function fitCameraToModel(target) {
  const box = new THREE.Box3().setFromObject(target);
  const center = new THREE.Vector3();
  const size = new THREE.Vector3();
  box.getCenter(center);
  box.getSize(size);
  const maxDim = Math.max(size.x, size.y, size.z);
  const fov = camera.fov * (Math.PI / 180);
  const dist = (maxDim / (2 * Math.tan(fov / 2))) * 2.2;
  camera.position.set(center.x, center.y, center.z + dist);
  camera.lookAt(center);
  camera.updateProjectionMatrix();
  if (controls) {
    controls.target.copy(center);
    controls.update();
  }
}

function initScene() {
  renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);

  scene = new THREE.Scene();

  camera = new THREE.PerspectiveCamera(
    50,
    window.innerWidth / window.innerHeight,
    0.01,
    100,
  );
  camera.position.set(0, 0.7, 2.2);

  scene.add(new THREE.AmbientLight(0xffffff, 0.6));
  const d1 = new THREE.DirectionalLight(0xffffff, 0.8);
  d1.position.set(5, 8, 5);
  scene.add(d1);
  const d2 = new THREE.DirectionalLight(0xffffff, 0.3);
  d2.position.set(-5, 3, -5);
  scene.add(d2);
  const p1 = new THREE.PointLight(0xffffff, 0.4);
  p1.position.set(0, 2, 3);
  scene.add(p1);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enablePan = true;
  controls.enableZoom = true;
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 0.5;
  controls.maxDistance = 8;
  controls.rotateSpeed = 0.8;

  materials = createHighlightMaterials();

  window.addEventListener("resize", onResize);
  // Controls are now rendered natively in Flutter (the host screen) and drive
  // the viewer through the window.* bridge below — no in-canvas button bar.
  animate();
}

function onResize() {
  if (!renderer || !camera) return;
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
}

function animate() {
  requestAnimationFrame(animate);
  if (controls) controls.update();
  if (renderer && scene && camera) renderer.render(scene, camera);
}

function loadModel() {
  const loader = new GLTFLoader();
  const draco = new DRACOLoader();
  draco.setDecoderPath("draco/");
  draco.setDecoderConfig({ type: "wasm" });
  loader.setDRACOLoader(draco);

  loader.load(
    MODEL_PATH,
    (gltf) => {
      modelScene = gltf.scene;
      scene.add(modelScene);
      allMeshNames = collectAllMeshNames(modelScene);
      normalizedLookup = buildNormalizedLookup(allMeshNames);
      meshSideMap = buildMeshSideMap(modelScene);
      fitCameraToModel(modelScene);
      // Neutral skin until the first renderPattern call.
      applyMaterials(new Set(), new Set(), new Set(), new Set(), new Set());
      window.__ready = true;
    },
    undefined,
    (err) => {
      console.error("[viewer] GLB load failed:", err);
      window.__webglError = true;
      showError("Failed to load the 3D anatomy model.");
    },
  );
}

// ---------------------------------------------------------------------------
// Highlight pipeline
// ---------------------------------------------------------------------------
const resolveOne = (name) =>
    resolveMuscleToMeshes(name, allMeshNames, normalizedLookup, meshSideMap);

function buildSet(muscles, meshToGroup, color) {
  const set = new Set();
  for (const name of muscles || []) {
    const matched = resolveOne(name);
    for (const meshName of matched) {
      set.add(meshName);
      if (!meshToGroup.has(meshName)) {
        meshToGroup.set(meshName, { groupName: name, color });
      }
    }
  }
  return set;
}

function applyMaterials(pSet, sSet, stSet, cSet, spSet, meshToGroup, primaryMuscles) {
  const hasAnyHighlight =
    pSet.size > 0 || sSet.size > 0 || stSet.size > 0 || cSet.size > 0 || spSet.size > 0;

  const labels = [];
  const addedLabels = new Set();

  modelScene.traverse((obj) => {
    if (!obj.isMesh) return;
    const name = obj.name;
    let mat;
    let color = null;
    if (pSet.has(name)) {
      mat = materials.primary;
      color = COLORS.primary;
    } else if (sSet.has(name)) {
      mat = materials.secondary;
      color = COLORS.secondary;
    } else if (stSet.has(name)) {
      mat = materials.stabilizing;
      color = COLORS.stabilizing;
    } else if (cSet.has(name)) {
      mat = materials.chain;
      color = COLORS.chain;
    } else if (spSet.has(name)) {
      mat = materials.spinal;
      color = COLORS.spinal;
    } else if (hasAnyHighlight) {
      mat = materials.ghost;
    } else {
      mat = materials.neutral;
    }
    obj.material = mat;

    if (color && meshToGroup) {
      const groupInfo = meshToGroup.get(name);
      const displayName = groupInfo?.groupName
        ? groupInfo.groupName
            .replace(/\s*\((?!left|right|bilateral)[^)]*\)/gi, "")
            .trim()
        : cleanDisplayName(name);
      const key = displayName.toLowerCase();
      if (displayName && !addedLabels.has(key)) {
        addedLabels.add(key);
        const box = new THREE.Box3().setFromObject(obj);
        const center = new THREE.Vector3();
        box.getCenter(center);
        labels.push({ name: displayName, position: center, color });
      }
    }
  });

  // Order labels by the primaryMuscles pathway order (matches web).
  if (primaryMuscles && primaryMuscles.length) {
    const cleanClinical = (n) =>
      n
        .replace(/\s*\((?!left|right|bilateral)[^)]*\)/gi, "")
        .trim()
        .toLowerCase();
    const orderMap = new Map();
    primaryMuscles.forEach((m, i) => orderMap.set(cleanClinical(m), i));
    labels.sort(
      (a, b) =>
        (orderMap.get(cleanClinical(a.name)) ?? 999) -
        (orderMap.get(cleanClinical(b.name)) ?? 999),
    );
  }

  return labels;
}

// ---------------------------------------------------------------------------
// Overlays: cyan kinetic-chain line + numbered sprite labels
// ---------------------------------------------------------------------------
function makeLabelSprite(number, text, color) {
  const dpr = 2;
  const padX = 10 * dpr;
  const fontPx = 22 * dpr;
  const cnv = document.createElement("canvas");
  const ctx = cnv.getContext("2d");
  ctx.font = `600 ${fontPx}px system-ui, -apple-system, sans-serif`;
  const label = text.toUpperCase();
  const badgeW = fontPx * 1.4;
  const textW = ctx.measureText(label).width;
  const w = padX * 2 + badgeW + 8 * dpr + textW;
  const h = fontPx + 12 * dpr;
  cnv.width = w;
  cnv.height = h;

  // pill background
  ctx.fillStyle = "rgba(255,255,255,0.95)";
  roundRect(ctx, 0, 0, w, h, 8 * dpr);
  ctx.fill();
  ctx.lineWidth = 1.5 * dpr;
  ctx.strokeStyle = color;
  roundRect(ctx, 0, 0, w, h, 8 * dpr);
  ctx.stroke();

  // number badge
  const cx = padX + badgeW / 2;
  const cy = h / 2;
  ctx.beginPath();
  ctx.arc(cx, cy, badgeW / 2, 0, Math.PI * 2);
  ctx.fillStyle = COLORS.chainLine;
  ctx.fill();
  ctx.fillStyle = "#ffffff";
  ctx.font = `700 ${fontPx * 0.8}px system-ui, -apple-system, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(String(number), cx, cy + 1);

  // label text
  ctx.fillStyle = color;
  ctx.font = `600 ${fontPx}px system-ui, -apple-system, sans-serif`;
  ctx.textAlign = "left";
  ctx.textBaseline = "middle";
  ctx.fillText(label, padX + badgeW + 8 * dpr, cy + 1);

  const tex = new THREE.CanvasTexture(cnv);
  tex.anisotropy = 4;
  const sprite = new THREE.Sprite(
    new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false }),
  );
  // Scale sprite to a small world size preserving aspect ratio.
  const worldH = 0.09;
  sprite.scale.set((worldH * w) / h, worldH, 1);
  sprite.renderOrder = 999;
  return sprite;
}

// Small square vertebra badge (L1..S1). Highlighted segments use the purple
// spinal color; the rest render as gray reference markers (matches the web).
function makeVertebraSprite(label, highlighted) {
  const dpr = 2;
  const size = 30 * dpr;
  const cnv = document.createElement("canvas");
  cnv.width = size;
  cnv.height = size;
  const ctx = cnv.getContext("2d");

  ctx.fillStyle = highlighted ? COLORS.spinal : "rgba(180,180,180,0.95)";
  roundRect(ctx, 1, 1, size - 2, size - 2, 6 * dpr);
  ctx.fill();
  ctx.lineWidth = 1.5 * dpr;
  ctx.strokeStyle = highlighted ? "#ffffff" : "#888888";
  roundRect(ctx, 1, 1, size - 2, size - 2, 6 * dpr);
  ctx.stroke();

  ctx.fillStyle = "#ffffff";
  ctx.font = `700 ${13 * dpr}px system-ui, -apple-system, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, size / 2, size / 2 + 1);

  const tex = new THREE.CanvasTexture(cnv);
  tex.anisotropy = 4;
  const sprite = new THREE.Sprite(
    new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false }),
  );
  const worldH = highlighted ? 0.07 : 0.055;
  sprite.scale.set(worldH, worldH, 1);
  sprite.renderOrder = 999;
  return sprite;
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function buildOverlays(labels, spineInfo) {
  const group = new THREE.Group();

  const points = labels.map((l) => l.position.clone());

  // Vertebral badges (L1–S1) — shown when the Spine toggle is on. All six are
  // drawn as reference; the AI-identified segments render highlighted (purple).
  if (spineInfo && spineInfo.visible) {
    const segs = (spineInfo.segments || []).map((s) => String(s).toUpperCase());
    for (const v of ALL_VERTEBRAE) {
      const pos = VERTEBRA_POSITIONS[v];
      if (!pos) continue;
      const highlighted = segs.some((s) => s.includes(v));
      const badge = makeVertebraSprite(v, highlighted);
      badge.position.set(0.12, pos.y, pos.z);
      badge.userData.kind = "spine";
      group.add(badge);
    }
  }

  // Chain line: white glow underlay + cyan main line.
  if (points.length > 1) {
    const geom = new THREE.BufferGeometry().setFromPoints(points);
    const glow = new THREE.Line(
      geom,
      new THREE.LineBasicMaterial({
        color: COLORS.chainGlow,
        transparent: true,
        opacity: 0.5,
        // Draw over the body meshes — otherwise the flow line is occluded by
        // the ghost/neutral skin and toggling Chain looks like a no-op.
        depthTest: false,
      }),
    );
    glow.renderOrder = 990;
    glow.userData.kind = "chain";
    group.add(glow);
    const line = new THREE.Line(
      geom.clone(),
      new THREE.LineBasicMaterial({
        color: COLORS.chainLine,
        depthTest: false,
      }),
    );
    line.renderOrder = 991;
    line.userData.kind = "chain";
    group.add(line);
  }

  labels.forEach((lbl, i) => {
    const p = lbl.position;
    const offsetDir = p.x >= 0 ? 1 : -1;
    const labelPos = new THREE.Vector3(
      p.x + 0.45 * offsetDir,
      p.y,
      p.z + 0.1,
    );

    // leader line label→muscle
    const leaderGeom = new THREE.BufferGeometry().setFromPoints([
      p.clone(),
      labelPos,
    ]);
    const leader = new THREE.Line(
      leaderGeom,
      new THREE.LineBasicMaterial({
        color: lbl.color,
        transparent: true,
        opacity: 0.8,
        depthTest: false,
      }),
    );
    leader.renderOrder = 992;
    leader.userData.kind = "leader";
    group.add(leader);

    // marker sphere at the muscle
    const marker = new THREE.Mesh(
      new THREE.SphereGeometry(0.015, 12, 12),
      new THREE.MeshBasicMaterial({
        color: COLORS.chainLine,
        transparent: true,
        opacity: 0.7,
        depthTest: false,
      }),
    );
    marker.position.copy(p);
    marker.renderOrder = 993;
    marker.userData.kind = "marker";
    group.add(marker);

    // numbered label sprite
    const sprite = makeLabelSprite(i + 1, lbl.name, lbl.color);
    sprite.position.copy(labelPos);
    sprite.userData.kind = "label";
    group.add(sprite);
  });

  return group;
}

// ---------------------------------------------------------------------------
// On-screen controls (themed to the app palette: tan accent on dark chrome)
// ---------------------------------------------------------------------------
function zoomBy(factor) {
  if (!camera || !controls) return;
  const dir = camera.position.clone().sub(controls.target);
  let len = dir.length() * factor;
  len = Math.min(controls.maxDistance, Math.max(controls.minDistance, len));
  dir.setLength(len);
  camera.position.copy(controls.target).add(dir);
  controls.update();
}

function setKindVisible(kinds, visible) {
  if (!overlayGroup) return;
  overlayGroup.traverse((o) => {
    if (o.userData && kinds.includes(o.userData.kind)) o.visible = visible;
  });
}

function buildControls() {
  const TAN = "#C59D84"; // app accent (--tanDark)
  const DARK = "rgba(19,42,53,0.92)"; // app --darkTeal chrome
  const bar = document.createElement("div");
  bar.style.cssText =
    "position:absolute;left:0;right:0;bottom:calc(env(safe-area-inset-bottom,0px) + 14px);" +
    "display:flex;gap:8px;justify-content:center;flex-wrap:wrap;padding:0 12px;z-index:10;pointer-events:none;";

  function setActive(btn, on) {
    btn.style.background = on ? TAN : DARK;
    btn.style.color = on ? "#1A1A1A" : "#F9F5F1";
  }
  function mk(label, onClick) {
    const b = document.createElement("button");
    b.textContent = label;
    b.style.cssText =
      "pointer-events:auto;border:none;cursor:pointer;padding:9px 14px;border-radius:14px;" +
      "font:900 10px system-ui,-apple-system,sans-serif;letter-spacing:0.8px;text-transform:uppercase;" +
      "box-shadow:0 3px 8px rgba(0,0,0,0.35);min-width:40px;";
    setActive(b, true);
    b.addEventListener("click", (e) => {
      e.preventDefault();
      onClick(b, setActive);
    });
    bar.appendChild(b);
    return b;
  }

  mk("Reset", () => {
    if (modelScene) fitCameraToModel(modelScene);
  });
  mk("−", () => zoomBy(1.15)); // zoom out
  mk("+", () => zoomBy(0.87)); // zoom in
  mk("Labels", (b, sa) => {
    labelsVisible = !labelsVisible;
    setKindVisible(["label", "leader", "marker"], labelsVisible);
    sa(b, labelsVisible);
  });
  mk("Chain", (b, sa) => {
    chainVisible = !chainVisible;
    setKindVisible(["chain"], chainVisible);
    sa(b, chainVisible);
  });

  document.body.appendChild(bar);
}

// ---------------------------------------------------------------------------
// Public entry + bridge — called by Flutter (native chrome owns the controls)
// ---------------------------------------------------------------------------
// The last full payload and the muscle-group visibility flags. Flutter's toggle
// chips flip these via the bridge below and we re-highlight from the same data,
// mirroring the web ZAnatomyViewer's `visiblePrimary = showPrimary ? ... : []`.
window.__payload = null;
window.__vis = { primary: true, secondary: true, stabilizing: true, spinal: false };

// Re-highlight the model from window.__payload honoring window.__vis. Emptying a
// group's muscle list drops it back to the ghost material (same as the web).
function renderCurrent() {
  if (!modelScene || !window.__payload) return;
  const data = window.__payload;
  const vis = window.__vis;
  const primaryMuscles = data.primaryMuscles || [];
  const meshToGroup = new Map();

  const pSet = buildSet(
    vis.primary ? primaryMuscles : [],
    meshToGroup,
    COLORS.primary,
  );
  const sSet = buildSet(
    vis.secondary ? data.secondaryMuscles : [],
    meshToGroup,
    COLORS.secondary,
  );
  const stSet = buildSet(
    vis.stabilizing ? data.stabilizingMuscles : [],
    meshToGroup,
    COLORS.stabilizing,
  );
  // No separate "chain" mesh group: kineticChainPathway === primaryMuscles, so
  // coloring it here would recolor the primary meshes blue whenever Primary is
  // toggled off. The cyan chain FLOW LINE is drawn from the highlighted label
  // centroids (in primaryMuscles order) and is toggled via window.setChain.
  const cSet = new Set();
  const spSet = buildSet(
    vis.spinal ? data.spinalSegments : [],
    meshToGroup,
    COLORS.spinal,
  );

  // Always pass the real primaryMuscles for label pathway ordering.
  const labels = applyMaterials(
    pSet,
    sSet,
    stSet,
    cSet,
    spSet,
    meshToGroup,
    primaryMuscles,
  );

  if (overlayGroup) {
    scene.remove(overlayGroup);
    overlayGroup.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) {
        if (o.material.map) o.material.map.dispose();
        o.material.dispose();
      }
    });
    overlayGroup = null;
  }
  overlayGroup = buildOverlays(labels, {
    segments: data.spinalSegments || [],
    visible: !!vis.spinal,
  });
  scene.add(overlayGroup);
  // Preserve the current Labels/Chain toggle state across re-renders.
  setKindVisible(["label", "leader", "marker"], labelsVisible);
  setKindVisible(["chain"], chainVisible);
}

window.renderPattern = function (payload) {
  if (!modelScene) return; // not ready yet; Flutter polls __ready first
  window.__payload = payload || {};
  window.__vis = { primary: true, secondary: true, stabilizing: true, spinal: false };
  renderCurrent();
};

// --- Bridge: Flutter calls these via evaluateJavascript ---------------------
// All are no-ops until the model is ready (mirrors renderPattern's guard).
window.setGroupVisibility = function (v) {
  if (!window.__payload) return;
  Object.assign(window.__vis, v || {});
  renderCurrent();
};

window.setLabels = function (on) {
  labelsVisible = !!on;
  setKindVisible(["label", "leader", "marker"], labelsVisible);
};

window.setChain = function (on) {
  chainVisible = !!on;
  setKindVisible(["chain"], chainVisible);
};

window.zoomIn = function () {
  zoomBy(0.87);
};

window.zoomOut = function () {
  zoomBy(1.15);
};

window.resetView = function () {
  if (modelScene) fitCameraToModel(modelScene);
};

function showError(msg) {
  const el = document.getElementById("err");
  if (el) {
    el.textContent = msg;
    el.style.display = "flex";
  }
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
if (!hasWebGL()) {
  window.__webglError = true;
  window.__ready = true; // let Flutter proceed to its fallback UI
  showError("3D is not supported on this device.");
} else {
  initScene();
  loadModel();
}
