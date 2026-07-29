// Pre-derived per-mesh anchors — the seed positions that let a pad land ON its
// own muscle instead of on a curated zone landmark near it.
//
// Port of the anchor maths in Hydrawave3/apps/web/src/anatomy/recoveryPadMarkers.js:47-141
// (the performance store flow uses the identical path).
//
// WHY THIS EXISTS. The older mobile viewer resolves a pad by unioning the
// bounding boxes of its target meshes and taking the centre. That puts "proximal
// hamstring origin" in the MIDDLE of the hamstring. `perf_mesh_anchors.json`
// ships a per-side centroid plus the muscle's long-axis endpoints, so `position`
// (proximal / mid / distal) can actually slide the pad along the muscle.
//
// The JSON is fetched at runtime rather than bundled: it is 97 KB of data that
// changes when the GLB changes, not when this code changes, and bundling it
// would mean an esbuild run every time the anchors are re-derived.
//
// Source:    Hydrawave3/apps/web/src/data/perfMeshAnchors.json (v4.2, 242 meshes)
// Generator: Hydrawave3/apps/web/scripts/derive-perf-mesh-anchors.mjs

import { normalizeName } from "./muscle_resolve.js";

// Pelvis / lower-trunk reference in the fitted scene frame, for deciding which
// end of an axial muscle is "proximal". Same constant as the web.
const CORE = [0, 0.6, 0];

let ANCHORS = {};
// Second index keyed by normalizeName(), so mobile's mesh vocabulary can still
// hit the 242 placement-core display names when the raw string misses.
let NORMALIZED = new Map();

export function anchorCount() {
  return Object.keys(ANCHORS).length;
}

/**
 * Load `perf_mesh_anchors.json` from the viewer's document root. Resolves to the
 * number of anchors loaded; resolves to 0 (never rejects) when the file is
 * absent, so a bundle running without the asset degrades to the bbox tier
 * instead of failing to boot.
 */
export async function loadMeshAnchors(url = "perf_mesh_anchors.json") {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const json = await res.json();
    ANCHORS = json.anchors || {};
    NORMALIZED = new Map();
    for (const key of Object.keys(ANCHORS)) {
      const n = normalizeName(key);
      // First writer wins: exact keys are authored, later collisions are noise.
      if (n && !NORMALIZED.has(n)) NORMALIZED.set(n, ANCHORS[key]);
    }
    return anchorCount();
  } catch (err) {
    console.warn("[anatomy] mesh anchors unavailable:", err && err.message);
    ANCHORS = {};
    NORMALIZED = new Map();
    return 0;
  }
}

function anchorFor(meshName) {
  if (!meshName) return null;
  const direct = ANCHORS[meshName];
  if (direct) return direct;
  return NORMALIZED.get(normalizeName(meshName)) || null;
}

// Recovery's position vocabulary is wider than performance's: origin/insertion/
// over-node/superior/inferior/na all collapse onto the proximal|mid|distal axis
// the anchor maths understands.
export function normPosition(value) {
  const s = String(value || "").toLowerCase();
  if (/proximal|origin|superior/.test(s)) return "proximal";
  if (/distal|insertion|inferior/.test(s)) return "distal";
  return "mid"; // mid, over-node, na, unknown
}

/**
 * The authored `plane` decides WHICH FACE of the body a pad sits on, and it is
 * the only field carrying that information: a mesh anchor is a whole-mesh
 * centroid, so it says where a muscle is, never which side to approach from.
 * The renderer raycasts INWARD along the marker normal, so returning the plane's
 * outward direction is what makes the pad land on the authored face.
 *
 * Without this a sandwich only looked right when its two meshes happened to
 * straddle the body in z — the anterior/posterior deltoid heads do not (both
 * centroids sit behind the coronal midline), so the shoulder sandwich rendered
 * as a diagonal.
 *
 * "superior"/"inferior" are deliberately NOT directional: the vertical
 * Sun-above/Moon-below relationship lives in `position` (normPosition applies
 * it) while both pads keep their real facing plane. Treating "superior" as a
 * from-above approach would push a posterior pad onto the top of the shoulder.
 */
export function planeNormal(plane, side) {
  // Right-side structures sit at -x in the fitted scene frame, so "lateral"
  // points -x on the right.
  const lateralSign = side === "left" ? 1 : -1;
  switch (String(plane || "").toLowerCase()) {
    case "anterior":
      return { normal: [0, 0, 1], view: "front" };
    case "posterior":
      return { normal: [0, 0, -1], view: "back" };
    case "medial":
      return { normal: [-lateralSign, 0, 0], view: "side" };
    case "lateral":
      return { normal: [lateralSign, 0, 0], view: "side" };
    // The foot's two faces, matching the curated dorsal_foot / plantar_foot
    // landmark normals.
    case "dorsal":
      return { normal: [0, 0.25, 0.97], view: "front" };
    case "plantar":
      return { normal: [0, -0.45, -0.89], view: "back" };
    default:
      return null;
  }
}

function lerp3(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

export function pointAlongMesh(extent, centerPt, position) {
  if (position === "mid" || !extent || !Array.isArray(extent.ends) || extent.ends.length !== 2) {
    return centerPt;
  }
  const [e0, e1] = extent.ends;
  const isLimb = Math.abs(centerPt[0]) > 0.3 || centerPt[1] < 0;
  let proximal;
  let distal;
  if (isLimb) {
    // On a limb, "proximal" is simply the higher end.
    [proximal, distal] = e0[1] >= e1[1] ? [e0, e1] : [e1, e0];
  } else {
    // On the trunk, it is the end nearer the pelvis reference.
    const d2 = (p) => (p[0] - CORE[0]) ** 2 + (p[1] - CORE[1]) ** 2 + (p[2] - CORE[2]) ** 2;
    [proximal, distal] = d2(e0) <= d2(e1) ? [e0, e1] : [e1, e0];
  }
  return position === "proximal" ? lerp3(proximal, distal, 0.25) : lerp3(proximal, distal, 0.75);
}

/**
 * Seed position for a pad: the average anchor of its target meshes on the pad's
 * side, offset along the muscle by `position`. The caller raycast-snaps it onto
 * the real surface from there.
 *
 * Returns `{position, normal, view, hits, total}` or null when no target mesh
 * has an anchor. `hits`/`total` feed the anchorsHit/anchorsTotal diagnostics —
 * a silent drop to the bbox tier is the failure mode this port most needs to be
 * able to see.
 */
export function padAnchorOverride({ muscles, position: rawPosition, plane }, side) {
  const position = normPosition(rawPosition);
  const other = side === "left" ? "right" : "left";
  const points = [];
  const list = Array.isArray(muscles) ? muscles : [];
  for (const mesh of list) {
    const anchor = anchorFor(mesh);
    if (!anchor) continue;
    const key = anchor[side]
      ? side
      : anchor.midline
        ? "midline"
        : anchor.center
          ? "center"
          : anchor[other]
            ? other
            : null;
    if (!key) continue;
    points.push(pointAlongMesh(anchor.extents && anchor.extents[key], anchor[key], position));
  }
  if (!points.length) return null;
  const sum = points.reduce((acc, p) => [acc[0] + p[0], acc[1] + p[1], acc[2] + p[2]], [0, 0, 0]);
  const centre = [sum[0] / points.length, sum[1] / points.length, sum[2] / points.length];

  // The authored plane wins when it names a real face; otherwise fall back to
  // the radial normal.
  const planed = planeNormal(plane, side);
  if (planed) {
    return {
      position: centre,
      normal: planed.normal,
      view: planed.view,
      hits: points.length,
      total: list.length,
    };
  }
  const radius = Math.hypot(centre[0], centre[2]);
  const normal =
    radius > 0.05 ? [centre[0] / radius, 0, centre[2] / radius] : [0, 0, centre[2] <= 0 ? -1 : 1];
  return {
    position: centre,
    normal,
    view: centre[2] < 0 ? "back" : "front",
    hits: points.length,
    total: list.length,
  };
}
