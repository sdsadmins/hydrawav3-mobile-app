// Offline vanilla-three.js port of the web `AnatomyScene` 3D pad-placement view
// (Hydrawave3 `apps/web/src/components/AnatomyScene.jsx`).
//
// This renders the Sun/Moon electrode pads on the anatomy model for the Flutter
// mobile app. It is bundled into `assets/3d/pad_placement.bundle.js` and hosted
// in an in-app WebView over the bundled localhost server.
//
// Ported near-verbatim from the web:
//   - ANATOMY_LANDMARKS      (packages/placement-core/src/knowledge/anatomyCalibration.js)
//   - LOCAL_PAD_LANDMARKS    (AnatomyScene.jsx)
//   - pairedLandmarks / withMidline / resolveLandmark
//   - fitBodyObject          (model normalization — landmark coords assume it)
// The scene scaffolding (GLB+Draco load, camera fit, OrbitControls, __ready /
// __webglError flags) mirrors the sibling `viewer.src.js` so both viewers behave
// identically inside the WebView.
//
// Entry point Flutter calls: window.renderPadPlacement(markers) where `markers`
// is the backend `markers` array from POST ai-padplacement/placement-session —
// i.e. getMarkers(recommendation): [{ role:"sun"|"moon", zone, label, side,
// surface, setIndex, setTitle, setting }].
// Flags read by Flutter: window.__ready, window.__webglError.

import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

const MODEL_PATH = "z-anatomy-muscles.glb"; // relative to the localhost root

// Landmark coordinates below are expressed in the NORMALIZED model space the
// web viewer establishes in fitBodyObject(). Changing these breaks alignment.
const BODY_TARGET_HEIGHT = 4.22;
const BODY_TARGET_CENTER_Y = 0.24;

const PAD_RADIUS = 0.075;
const COLORS = {
  sun: "#F59E0B",
  moon: "#6366F1",
  skin: "#d7a67b",
};

// ---------------------------------------------------------------------------
// Shared calibrated landmarks (verbatim from placement-core anatomyCalibration)
// ---------------------------------------------------------------------------
const ANATOMY_LANDMARKS = [
  { zone: "thoracolumbar", region: "Thoracolumbar junction", view: "back", absX: 0.07, y: 1.27, z: -0.43, normalX: 0.08, normalY: 0, normalZ: -1 },
  { zone: "low_back_l23", region: "L2-L3 lumbar paraspinal", view: "back", absX: 0.12, y: 1.18, z: -0.42, normalX: 0.16, normalY: 0, normalZ: -0.99 },
  { zone: "iliac_fossa", region: "Anterior iliac fossa", view: "front", absX: 0.21, y: 0.78, z: 0.34, normalX: 0.26, normalY: 0, normalZ: 0.97 },
  { zone: "external_oblique", region: "External oblique", view: "front", absX: 0.31, y: 1.09, z: 0.28, normalX: 0.58, normalY: 0, normalZ: 0.82 },
  { zone: "lat", region: "Latissimus dorsi", view: "side", absX: 0.39, y: 1.4, z: -0.24, normalX: 0.72, normalY: 0, normalZ: -0.7 },
  { zone: "hamstring_origin", region: "Proximal hamstring origin", view: "back", absX: 0.23, y: 0.43, z: -0.35, normalX: 0.34, normalY: -0.03, normalZ: -0.94 },
  { zone: "medial_hamstring_origin", region: "Medial proximal hamstring origin", view: "back", absX: 0.17, y: 0.43, z: -0.34, normalX: 0.22, normalY: -0.03, normalZ: -0.98 },
  { zone: "lateral_ischial_tuberosity", region: "Lateral ischial tuberosity", view: "back", absX: 0.29, y: 0.44, z: -0.34, normalX: 0.48, normalY: -0.02, normalZ: -0.88 },
  { zone: "posterior_hip", region: "Posterior hip / piriformis", view: "back", absX: 0.29, y: 0.7, z: -0.39, normalX: 0.5, normalY: 0, normalZ: -0.87 },
  { zone: "posterior_ilium", region: "Posterior ilium", view: "back", absX: 0.22, y: 0.76, z: -0.38, normalX: 0.36, normalY: 0, normalZ: -0.93 },
  { zone: "piriformis_posterior_hip", region: "Piriformis / external rotators", view: "back", absX: 0.29, y: 0.69, z: -0.39, normalX: 0.5, normalY: 0, normalZ: -0.87 },
  { zone: "gluteus_medius_posterior_hip", region: "Gluteus medius posterior hip", view: "back", absX: 0.34, y: 0.78, z: -0.3, normalX: 0.58, normalY: 0, normalZ: -0.82 },
  { zone: "gluteus_maximus_upper_belly", region: "Gluteus maximus upper belly", view: "back", absX: 0.26, y: 0.56, z: -0.36, normalX: 0.52, normalY: 0, normalZ: -0.86 },
  { zone: "gluteus_maximus_tuberosity", region: "Gluteus maximus at gluteal tuberosity", view: "back", absX: 0.16, y: 0.48, z: -0.42, normalX: 0.22, normalY: 0, normalZ: -0.98 },
  { zone: "pectoralis_minor_coracoid", region: "Pectoralis minor at coracoid", view: "front", absX: 0.38, y: 1.61, z: 0.24, normalX: 0.48, normalY: 0.02, normalZ: 0.88 },
  { zone: "infraspinatus_greater_tubercle", region: "Infraspinatus to greater tubercle", view: "back", absX: 0.38, y: 1.57, z: -0.34, normalX: 0.44, normalY: 0, normalZ: -0.9 },
  { zone: "anterior_deltoid", region: "Anterior deltoid", view: "front", absX: 0.53, y: 1.72, z: 0.13, normalX: 0.74, normalY: 0.04, normalZ: 0.67 },
  { zone: "posterior_deltoid", region: "Posterior deltoid", view: "back", absX: 0.5, y: 1.68, z: -0.22, normalX: 0.64, normalY: 0.03, normalZ: -0.77 },
  { zone: "serratus_anterior_rib7", region: "Serratus anterior at rib 7", view: "side", absX: 0.48, y: 1.45, z: 0.03, normalX: 0.94, normalY: 0, normalZ: 0.34 },
  { zone: "serratus_posterior_inferior_t11_t12", region: "Serratus posterior inferior T11-T12", view: "back", absX: 0.18, y: 1.29, z: -0.41, normalX: 0.18, normalY: 0, normalZ: -0.98 },
  { zone: "splenius_capitis_c2_c3", region: "Splenius capitis at C2-C3", view: "back", absX: 0.1, y: 2.04, z: -0.23, normalX: 0.16, normalY: -0.03, normalZ: -0.99 },
  { zone: "levator", region: "Levator scapulae", view: "back", absX: 0.22, y: 1.83, z: -0.26, normalX: 0.42, normalY: 0, normalZ: -0.91 },
  { zone: "rhomboid", region: "Rhomboid / medial scapular border", view: "back", absX: 0.19, y: 1.58, z: -0.4, normalX: 0.24, normalY: 0, normalZ: -0.97 },
  { zone: "pronator_teres_medial_epicondyle", region: "Pronator teres at medial epicondyle", view: "side", absX: 0.83, y: 1.32, z: 0.08, normalX: -0.58, normalY: 0, normalZ: 0.82 },
  { zone: "triceps_olecranon", region: "Triceps insertion at olecranon", view: "side", absX: 0.83, y: 1.27, z: -0.08, normalX: -0.2, normalY: 0, normalZ: -0.98 },
  { zone: "extensor_carpi_ulnaris_forearm", region: "Extensor carpi ulnaris forearm", view: "side", absX: 1.04, y: 0.94, z: -0.1, normalX: 0.36, normalY: 0, normalZ: -0.93 },
  { zone: "anterior_distal_forearm", region: "Anterior distal forearm", view: "side", absX: 1.06, y: 0.92, z: 0.12, normalX: 0.45, normalY: 0, normalZ: 0.89 },
  { zone: "posterior_distal_forearm", region: "Posterior distal forearm", view: "side", absX: 1.04, y: 0.94, z: -0.1, normalX: 0.36, normalY: 0, normalZ: -0.93 },
  { zone: "sartorius_pes_anserine", region: "Sartorius / pes anserine medial knee", view: "front", absX: 0.13, y: -0.64, z: 0.12, normalX: -0.68, normalY: 0, normalZ: 0.73 },
  { zone: "rectus_femoris_quad_tendon", region: "Rectus femoris / quad tendon", view: "front", absX: 0.23, y: -0.46, z: 0.24, normalX: 0, normalY: 0, normalZ: 1 },
  { zone: "vastus_medialis_vmo", region: "Vastus medialis above medial patella", view: "front", absX: 0.17, y: -0.38, z: 0.19, normalX: -0.35, normalY: 0, normalZ: 0.94 },
  { zone: "vastus_lateralis_vl", region: "Vastus lateralis above lateral patella", view: "front", absX: 0.29, y: -0.36, z: 0.17, normalX: 0.56, normalY: 0, normalZ: 0.83 },
  { zone: "popliteus_posterior_knee", region: "Popliteus posterior knee", view: "back", absX: 0.22, y: -0.5, z: -0.23, normalX: 0.18, normalY: 0, normalZ: -0.98 },
  { zone: "tibialis_anterior_tuberosity", region: "Tibialis anterior at tibial tuberosity", view: "front", absX: 0.2, y: -0.66, z: 0.18, normalX: -0.22, normalY: 0, normalZ: 0.98 },
  { zone: "fibularis_longus_fibular_head", region: "Fibularis longus at fibular head", view: "front", absX: 0.33, y: -0.58, z: 0.06, normalX: 0.85, normalY: 0, normalZ: 0.52 },
  { zone: "tibialis_posterior_medial_malleolus", region: "Tibialis posterior above medial malleolus", view: "front", absX: 0.13, y: -1.57, z: 0.03, normalX: -0.88, normalY: 0, normalZ: 0.48 },
  { zone: "fibularis_longus_lateral_malleolus", region: "Fibularis longus above lateral malleolus", view: "front", absX: 0.34, y: -1.56, z: 0.03, normalX: 0.88, normalY: 0, normalZ: 0.48 },
  { zone: "tibialis_anterior_medial_cuneiform", region: "Tibialis anterior at medial cuneiform", view: "side", absX: 0.23, y: -1.78, z: 0.19, normalX: 0, normalY: 0.22, normalZ: 0.98 },
  { zone: "flexor_digitorum_brevis_arch", region: "Flexor digitorum brevis plantar arch", view: "side", absX: 0.23, y: -1.84, z: -0.05, normalX: 0, normalY: -0.46, normalZ: -0.89 },
];

// ---------------------------------------------------------------------------
// Landmark helpers (verbatim from AnatomyScene.jsx)
// ---------------------------------------------------------------------------
const DEFAULT_LANDMARK = {
  position: [0, 1, 0.35],
  normal: [0, 0, 1],
  region: "General",
  view: "front",
  mapped: false,
};

function landmark(position, normal, cue, view = "front", region = "General") {
  return { position, normal, cue, view, region, mapped: true };
}

function mirrorNormal(normal) {
  return [-normal[0], normal[1], normal[2]];
}

function pairedLandmarks(absX, y, z, rightNormal, cue, view, region) {
  return {
    right: landmark([absX, y, z], rightNormal, `Right ${cue}`, view, region),
    left: landmark([-absX, y, z], mirrorNormal(rightNormal), `Left ${cue}`, view, region),
  };
}

function withMidline(pair, midline) {
  return { ...pair, midline };
}

function sharedPadLandmarks() {
  return Object.fromEntries(
    ANATOMY_LANDMARKS.map((item) => [
      item.zone,
      pairedLandmarks(
        item.absX,
        item.y,
        item.z,
        [item.normalX, item.normalY, item.normalZ],
        item.region,
        item.view,
        item.region,
      ),
    ]),
  );
}

const LOCAL_PAD_LANDMARKS = {
  low_back_l23: withMidline(
    pairedLandmarks(0.13, 1.18, -0.41, [0.18, 0, -0.98], "side of the spine at the L2-L3 low-back level", "back", "Low back"),
    landmark([0, 1.18, -0.43], [0, 0, -1], "Centerline at L2-L3", "back", "Low back"),
  ),
  iliac_fossa: pairedLandmarks(0.23, 0.8, 0.34, [0.25, 0, 0.97], "front hip crease, just inside the bony hip point", "front", "Front hip"),
  glute: pairedLandmarks(0.22, 0.54, -0.42, [0.28, 0, -0.96], "main glute muscle belly", "back", "Glute"),
  hamstring_origin: pairedLandmarks(0.18, 0.42, -0.34, [0.22, -0.03, -0.98], "upper hamstring origin at the gluteal fold", "back", "Upper hamstring"),
  posterior_hip: pairedLandmarks(0.28, 0.71, -0.38, [0.48, 0, -0.88], "deep back hip area", "back", "Posterior hip"),
  anterior_hip: pairedLandmarks(0.3, 0.78, 0.3, [0.48, 0, 0.88], "front outer hip near the TFL/hip-flexor line", "front", "Anterior hip"),
  thoracolumbar: pairedLandmarks(0.07, 1.27, -0.43, [0.08, 0, -1], "thoracolumbar junction beside the spine", "back", "Thoracolumbar"),
  lat: pairedLandmarks(0.39, 1.4, -0.24, [0.72, 0, -0.7], "mid to lower lat on the back-side ribcage", "side", "Lat"),
  external_oblique: pairedLandmarks(0.3, 1.08, 0.29, [0.58, 0, 0.82], "front-side core between ribs and hip", "front", "Oblique"),
  serratus: pairedLandmarks(0.47, 1.48, 0.09, [0.93, 0, 0.36], "side ribs under the shoulder blade", "side", "Serratus"),
  anterior_deltoid: pairedLandmarks(0.54, 1.82, 0.18, [0.72, 0, 0.69], "front shoulder cap", "front", "Shoulder"),
  posterior_deltoid: pairedLandmarks(0.54, 1.78, -0.22, [0.66, 0, -0.75], "back shoulder cap", "back", "Shoulder"),
  teres_superior: pairedLandmarks(0.45, 1.62, -0.31, [0.58, 0, -0.81], "upper rotator-cuff line near the armpit fold", "back", "Rotator cuff"),
  teres_inferior: pairedLandmarks(0.42, 1.5, -0.34, [0.52, 0, -0.85], "lower rotator-cuff line near the armpit fold", "back", "Rotator cuff"),
  occipital: pairedLandmarks(0.08, 2.16, -0.18, [0.14, -0.08, -0.99], "base of skull just off the centerline", "back", "Upper neck"),
  c6_c7: withMidline(
    pairedLandmarks(0.04, 1.93, -0.26, [0.1, 0, -1], "base of neck beside the C6-C7 junction", "back", "Lower neck"),
    landmark([0, 1.93, -0.27], [0, 0, -1], "Base of neck at the C6-C7 bump", "back", "Lower neck"),
  ),
  levator: pairedLandmarks(0.23, 1.82, -0.25, [0.45, 0, -0.89], "upper inside shoulder blade", "back", "Levator"),
  rhomboid: pairedLandmarks(0.2, 1.59, -0.39, [0.28, 0, -0.96], "between the spine and inner shoulder blade", "back", "Rhomboid"),
  mid_trap: pairedLandmarks(0.12, 1.52, -0.4, [0.18, 0, -0.98], "middle back between the shoulder blades", "back", "Mid trapezius"),
  upper_trap: pairedLandmarks(0.31, 1.86, -0.15, [0.6, 0.12, -0.79], "top of shoulder slope near the neck", "back", "Upper trapezius"),
  medial_knee_superior: pairedLandmarks(0.13, -0.49, 0.12, [-0.68, 0, 0.73], "inside knee, just above the joint line", "front", "Knee"),
  medial_knee_inferior: pairedLandmarks(0.13, -0.64, 0.12, [-0.68, 0, 0.73], "inside knee, just below the joint line", "front", "Knee"),
  lateral_knee_superior: pairedLandmarks(0.32, -0.49, 0.09, [0.72, 0, 0.69], "outside knee, just above the joint line", "front", "Knee"),
  lateral_knee_inferior: pairedLandmarks(0.32, -0.64, 0.09, [0.72, 0, 0.69], "outside knee, just below the joint line", "front", "Knee"),
  above_patella: pairedLandmarks(0.23, -0.48, 0.24, [0, 0, 1], "quad tendon directly above the kneecap", "front", "Knee"),
  below_patella: pairedLandmarks(0.23, -0.66, 0.23, [0, 0, 1], "patellar tendon directly below the kneecap", "front", "Knee"),
  below_patella_right: {
    right: landmark([0.3, -0.65, 0.22], [0.25, 0, 0.97], "Right knee outer half just below the kneecap", "front", "Knee"),
    left: landmark([-0.16, -0.65, 0.22], [0.18, 0, 0.98], "Left knee inner half just below the kneecap", "front", "Knee"),
  },
  below_patella_left: {
    right: landmark([0.16, -0.65, 0.22], [-0.18, 0, 0.98], "Right knee inner half just below the kneecap", "front", "Knee"),
    left: landmark([-0.3, -0.65, 0.22], [-0.25, 0, 0.97], "Left knee outer half just below the kneecap", "front", "Knee"),
  },
  posterior_knee_above_fossa: pairedLandmarks(0.23, -0.52, -0.22, [0.18, 0, -0.98], "back of knee above the crease", "back", "Posterior knee"),
  anterior_medial_elbow: pairedLandmarks(0.84, 1.33, 0.1, [-0.6, 0, 0.8], "inside-front elbow crease", "side", "Elbow"),
  posterior_medial_elbow: pairedLandmarks(0.84, 1.33, -0.12, [-0.58, 0, -0.82], "inside-back elbow", "side", "Elbow"),
  anterior_lateral_elbow: pairedLandmarks(0.96, 1.33, 0.1, [0.7, 0, 0.71], "outside-front elbow", "side", "Elbow"),
  posterior_lateral_elbow: pairedLandmarks(0.96, 1.33, -0.12, [0.68, 0, -0.73], "outside-back elbow", "side", "Elbow"),
  anterior_distal_forearm: pairedLandmarks(1.06, 0.92, 0.12, [0.45, 0, 0.89], "palm-side lower forearm above the wrist", "side", "Forearm"),
  posterior_distal_forearm: pairedLandmarks(1.06, 0.92, -0.1, [0.44, 0, -0.9], "back-side lower forearm above the wrist", "side", "Forearm"),
  medial_malleolus: pairedLandmarks(0.13, -1.62, 0.04, [-0.86, 0, 0.5], "inside ankle above the ankle bone", "front", "Ankle"),
  lateral_malleolus: pairedLandmarks(0.34, -1.62, 0.03, [0.86, 0, 0.5], "outside ankle above the ankle bone", "front", "Ankle"),
  plantar_foot: pairedLandmarks(0.23, -1.83, -0.05, [0, -0.45, -0.89], "bottom of foot through the arch area", "side", "Foot"),
  dorsal_foot: pairedLandmarks(0.23, -1.8, 0.2, [0, 0.25, 0.97], "top of foot over the midfoot", "side", "Foot"),
};

const PAD_LANDMARKS = { ...LOCAL_PAD_LANDMARKS, ...sharedPadLandmarks() };

function resolveLandmark(marker) {
  const override = marker.landmarkOverride;
  if (Array.isArray(override?.position) && Array.isArray(override?.normal)) {
    return {
      ...DEFAULT_LANDMARK,
      position: override.position,
      normal: override.normal,
      region: override.region || marker.zone || DEFAULT_LANDMARK.region,
      mapped: true,
    };
  }
  const zone = PAD_LANDMARKS[marker.zone] || PAD_LANDMARKS.low_back_l23;
  return {
    ...DEFAULT_LANDMARK,
    ...(zone[marker.side] || zone.midline || zone.right || DEFAULT_LANDMARK),
  };
}

// ---------------------------------------------------------------------------
// Scene state
// ---------------------------------------------------------------------------
const canvas = document.getElementById("c");
let renderer, scene, camera, controls;
let modelScene = null;
let padGroup = null; // holds every pad + badge, cleared per render
let labelsVisible = true;
const raycaster = new THREE.Raycaster();

window.__ready = false;
window.__webglError = false;
window.__markers = [];

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

// Normalize the model into the coordinate space the landmark table assumes.
// (verbatim from the web fitBodyObject — pads misalign without this)
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

function fitCameraToModel(target) {
  const box = new THREE.Box3().setFromObject(target);
  const center = new THREE.Vector3();
  const size = new THREE.Vector3();
  box.getCenter(center);
  box.getSize(size);
  const maxDim = Math.max(size.x, size.y, size.z);
  const fov = camera.fov * (Math.PI / 180);
  const dist = (maxDim / (2 * Math.tan(fov / 2))) * 1.35;
  camera.position.set(center.x, center.y, center.z + dist);
  camera.lookAt(center);
  camera.updateProjectionMatrix();
  if (controls) {
    controls.target.copy(center);
    controls.update();
  }
}

function initScene() {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);

  scene = new THREE.Scene();

  camera = new THREE.PerspectiveCamera(
    50,
    window.innerWidth / window.innerHeight,
    0.01,
    200,
  );
  camera.position.set(0, 0.7, 6);

  scene.add(new THREE.AmbientLight(0xffffff, 0.75));
  const d1 = new THREE.DirectionalLight(0xffffff, 0.8);
  d1.position.set(5, 8, 5);
  scene.add(d1);
  const d2 = new THREE.DirectionalLight(0xffffff, 0.35);
  d2.position.set(-5, 3, -5);
  scene.add(d2);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enablePan = true;
  controls.enableZoom = true;
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 0.8;
  controls.maxDistance = 30;
  controls.rotateSpeed = 0.8;

  padGroup = new THREE.Group();
  scene.add(padGroup);

  window.addEventListener("resize", onResize);
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

function applySkin(root) {
  const skin = new THREE.MeshStandardMaterial({
    color: COLORS.skin,
    roughness: 0.5,
    metalness: 0,
    transparent: true,
    opacity: 0.92,
    side: THREE.DoubleSide,
  });
  root.traverse((o) => {
    if (o.isMesh) o.material = skin;
  });
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
      fitBodyObject(modelScene);
      applySkin(modelScene);
      scene.add(modelScene);
      fitCameraToModel(modelScene);
      window.__ready = true;
      // Render anything Flutter injected before the model finished parsing.
      if (window.__markers && window.__markers.length) {
        renderMarkers(window.__markers);
      }
    },
    undefined,
    (err) => {
      console.error("[padPlacement] GLB load failed:", err);
      window.__webglError = true;
      showError("Failed to load the 3D anatomy model.");
    },
  );
}

// ---------------------------------------------------------------------------
// Pad textures (canvas-drawn Sun / Moon decals)
// ---------------------------------------------------------------------------
function makePadTexture(role) {
  const size = 256;
  const c = document.createElement("canvas");
  c.width = c.height = size;
  const ctx = c.getContext("2d");
  const cx = size / 2;
  const cy = size / 2;
  const r = size * 0.34;
  const color = role === "sun" ? COLORS.sun : COLORS.moon;

  // Soft outer glow so the pad reads against the skin material.
  const glow = ctx.createRadialGradient(cx, cy, r * 0.6, cx, cy, size * 0.5);
  glow.addColorStop(0, role === "sun" ? "rgba(245,158,11,0.55)" : "rgba(99,102,241,0.55)");
  glow.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, size, size);

  if (role === "sun") {
    // Rays
    ctx.strokeStyle = color;
    ctx.lineWidth = size * 0.035;
    ctx.lineCap = "round";
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(a) * r * 1.18, cy + Math.sin(a) * r * 1.18);
      ctx.lineTo(cx + Math.cos(a) * r * 1.42, cy + Math.sin(a) * r * 1.42);
      ctx.stroke();
    }
  }

  // Disc
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.lineWidth = size * 0.045;
  ctx.strokeStyle = "#ffffff";
  ctx.stroke();

  if (role === "moon") {
    // Crescent: punch a circle out of the disc.
    ctx.globalCompositeOperation = "destination-out";
    ctx.beginPath();
    ctx.arc(cx + r * 0.42, cy - r * 0.18, r * 0.78, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = "source-over";
  }

  const tex = new THREE.CanvasTexture(c);
  tex.anisotropy = 4;
  return tex;
}

function makeBadgeTexture(text, role) {
  const w = 256;
  const h = 128;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d");
  const color = role === "sun" ? COLORS.sun : COLORS.moon;
  const r = 26;
  ctx.beginPath();
  ctx.moveTo(r, 0);
  ctx.arcTo(w, 0, w, h, r);
  ctx.arcTo(w, h, 0, h, r);
  ctx.arcTo(0, h, 0, 0, r);
  ctx.arcTo(0, 0, w, 0, r);
  ctx.closePath();
  ctx.fillStyle = color;
  ctx.fill();
  ctx.lineWidth = 8;
  ctx.strokeStyle = "#ffffff";
  ctx.stroke();
  ctx.fillStyle = "#ffffff";
  ctx.font = "bold 68px system-ui, -apple-system, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, w / 2, h / 2 + 2);
  return new THREE.CanvasTexture(c);
}

const padTextures = {};
function padTexture(role) {
  if (!padTextures[role]) padTextures[role] = makePadTexture(role);
  return padTextures[role];
}

// ---------------------------------------------------------------------------
// Marker placement
// ---------------------------------------------------------------------------
// Raycast the landmark onto the actual model surface so the pad sits on the
// body rather than floating at the nominal coordinate (web: projectedLandmark).
function snapToSurface(position, normal) {
  if (!modelScene) return position;
  const n = new THREE.Vector3(normal[0], normal[1], normal[2]).normalize();
  const origin = new THREE.Vector3(position[0], position[1], position[2])
    .addScaledVector(n, 1.2);
  raycaster.set(origin, n.clone().negate());
  const hits = raycaster.intersectObject(modelScene, true);
  if (hits.length) return [hits[0].point.x, hits[0].point.y, hits[0].point.z];
  return position;
}

function orientToNormal(object, normal) {
  const n = new THREE.Vector3(normal[0], normal[1], normal[2]).normalize();
  const q = new THREE.Quaternion().setFromUnitVectors(
    new THREE.Vector3(0, 0, 1),
    n,
  );
  object.quaternion.copy(q);
}

function addPad(marker) {
  const lm = resolveLandmark(marker);
  const role = marker.role === "moon" ? "moon" : "sun";
  const snapped = snapToSurface(lm.position, lm.normal);
  const n = new THREE.Vector3(lm.normal[0], lm.normal[1], lm.normal[2]).normalize();

  // Pad decal — a disc lifted just off the surface along the normal.
  const pad = new THREE.Mesh(
    new THREE.CircleGeometry(PAD_RADIUS, 48),
    new THREE.MeshBasicMaterial({
      map: padTexture(role),
      transparent: true,
      depthTest: false,
      side: THREE.DoubleSide,
    }),
  );
  pad.position.set(snapped[0], snapped[1], snapped[2]).addScaledVector(n, 0.02);
  orientToNormal(pad, lm.normal);
  pad.renderOrder = 10;
  pad.userData.kind = "pad";
  padGroup.add(pad);

  // Badge — S1 / M1 (role initial + set number), billboarded above the pad.
  const setNo = Number.isFinite(marker.setIndex) ? marker.setIndex + 1 : 1;
  const text = `${role === "sun" ? "S" : "M"}${setNo}`;
  const badge = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map: makeBadgeTexture(text, role),
      transparent: true,
      depthTest: false,
    }),
  );
  badge.position
    .set(snapped[0], snapped[1], snapped[2])
    .addScaledVector(n, 0.1);
  badge.position.y += PAD_RADIUS * 1.9;
  badge.scale.set(0.22, 0.11, 1);
  badge.renderOrder = 11;
  badge.userData.kind = "badge";
  badge.visible = labelsVisible;
  padGroup.add(badge);
}

function clearPads() {
  if (!padGroup) return;
  for (let i = padGroup.children.length - 1; i >= 0; i--) {
    const child = padGroup.children[i];
    if (child.material?.map) child.material.map.dispose?.();
    child.material?.dispose?.();
    child.geometry?.dispose?.();
    padGroup.remove(child);
  }
}

function renderMarkers(markers) {
  if (!padGroup) return;
  clearPads();
  (markers || []).forEach((m) => {
    try {
      addPad(m);
    } catch (e) {
      console.error("[padPlacement] marker failed:", m, e);
    }
  });
}

function zoomBy(factor) {
  if (!camera || !controls) return;
  const dir = camera.position.clone().sub(controls.target);
  const len = THREE.MathUtils.clamp(
    dir.length() * factor,
    controls.minDistance,
    controls.maxDistance,
  );
  camera.position.copy(controls.target).add(dir.setLength(len));
  controls.update();
}

function showError(msg) {
  const el = document.getElementById("err");
  if (el) {
    el.textContent = msg;
    el.style.display = "flex";
  }
}

// --- Bridge: Flutter calls these via evaluateJavascript ---------------------
window.renderPadPlacement = function (markers) {
  window.__markers = Array.isArray(markers) ? markers : [];
  if (!window.__ready || !modelScene) return; // loadModel() replays it
  renderMarkers(window.__markers);
};

window.setLabels = function (on) {
  labelsVisible = !!on;
  if (!padGroup) return;
  padGroup.children.forEach((c) => {
    if (c.userData.kind === "badge") c.visible = labelsVisible;
  });
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

// Rotate the camera to a canonical view so the user can jump front/back.
window.setView = function (view) {
  if (!modelScene || !controls) return;
  const t = controls.target.clone();
  const dist = camera.position.distanceTo(t);
  const map = {
    front: [0, 0, 1],
    back: [0, 0, -1],
    left: [-1, 0, 0],
    right: [1, 0, 0],
  };
  const v = map[view] || map.front;
  camera.position.set(t.x + v[0] * dist, t.y + v[1] * dist, t.z + v[2] * dist);
  camera.lookAt(t);
  controls.update();
};

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
