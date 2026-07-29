// Curated pad landmarks + label-driven refinement.
//
// Verbatim port of Hydrawave3/apps/web/src/components/AnatomyScene.jsx:39-397.
// THIS FILE IS CANONICAL for the mobile side. The older `pad_placement.src.js`
// carries its own trimmed copy of the same tables (it dropped `cue` prose and
// midline support); the duplication is deliberate — extracting the tables out of
// that file would force a rebuild of `pad_placement.bundle.js`, and the whole
// point of the second viewer is that the first one stays untouched as a
// rollback path. Coordinates are numerically identical across all three copies;
// `verify-landmarks.mjs` asserts that.
//
// The 39 shared entries come from `anatomy_calibration.js` (auto-generated from
// placement-core). The 39 local entries below are AnatomyScene-only. Merged,
// with local losing to shared on the 13 overlapping keys, that is 65 unique
// zones — matching the web exactly.

import { ANATOMY_LANDMARKS } from "./anatomy_calibration.js";

export const DEFAULT_LANDMARK = {
  position: [0, 1, 0.35],
  normal: [0, 0, 1],
  cue: "Fallback front torso point. Review the source zone mapping.",
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

export function sideSign(side) {
  return side === "left" ? -1 : 1;
}

function sharedPadLandmarks() {
  return Object.fromEntries(
    ANATOMY_LANDMARKS.map((item) => {
      const pair = pairedLandmarks(
        item.absX,
        item.y,
        item.z,
        [item.normalX, item.normalY, item.normalZ],
        item.cue || item.region,
        item.view,
        item.region,
      );
      if (item.midline) {
        return [
          item.zone,
          withMidline(
            pair,
            landmark(
              [0, item.y, item.z],
              [0, item.normalY, item.normalZ],
              item.cue || item.region,
              item.view,
              item.region,
            ),
          ),
        ];
      }
      return [item.zone, pair];
    }),
  );
}

const LOCAL_PAD_LANDMARKS = {
  low_back_l23: withMidline(
    pairedLandmarks(0.13, 1.18, -0.41, [0.18, 0, -0.98], "side of the spine at the L2-L3 low-back level", "back", "Low back"),
    landmark([0, 1.18, -0.43], [0, 0, -1], "Centerline at L2-L3; place paired pads equally beside the spine", "back", "Low back"),
  ),
  iliac_fossa: pairedLandmarks(0.23, 0.8, 0.34, [0.25, 0, 0.97], "front hip crease, just inside the bony hip point", "front", "Front hip"),
  glute: pairedLandmarks(0.22, 0.54, -0.42, [0.28, 0, -0.96], "main glute muscle belly, below the back of the hip bone", "back", "Glute"),
  hamstring_origin: pairedLandmarks(0.18, 0.42, -0.34, [0.22, -0.03, -0.98], "upper hamstring origin at the gluteal fold directly under the sit bone", "back", "Upper hamstring"),
  posterior_hip: pairedLandmarks(0.28, 0.71, -0.38, [0.48, 0, -0.88], "deep back hip area between sacrum and outer hip", "back", "Posterior hip"),
  anterior_hip: pairedLandmarks(0.3, 0.78, 0.3, [0.48, 0, 0.88], "front outer hip near the TFL/hip-flexor line", "front", "Anterior hip"),
  thoracolumbar: pairedLandmarks(0.07, 1.27, -0.43, [0.08, 0, -1], "reference PDF thoracolumbar junction: one to two finger widths beside the spine at the lower-rib / upper-waist line", "back", "Thoracolumbar"),
  lat: pairedLandmarks(0.39, 1.4, -0.24, [0.72, 0, -0.7], "mid to lower lat on the back-side ribcage", "side", "Lat"),
  external_oblique: pairedLandmarks(0.3, 1.08, 0.29, [0.58, 0, 0.82], "front-side core muscle between ribs and hip", "front", "Oblique"),
  serratus: pairedLandmarks(0.47, 1.48, 0.09, [0.93, 0, 0.36], "side ribs under the shoulder blade", "side", "Serratus"),
  anterior_deltoid: pairedLandmarks(0.54, 1.82, 0.18, [0.72, 0, 0.69], "front shoulder cap where pec meets deltoid", "front", "Shoulder"),
  posterior_deltoid: pairedLandmarks(0.54, 1.78, -0.22, [0.66, 0, -0.75], "back shoulder cap behind the shoulder joint", "back", "Shoulder"),
  teres_superior: pairedLandmarks(0.45, 1.62, -0.31, [0.58, 0, -0.81], "upper back shoulder rotator-cuff line near the armpit fold", "back", "Rotator cuff"),
  teres_inferior: pairedLandmarks(0.42, 1.5, -0.34, [0.52, 0, -0.85], "lower back shoulder rotator-cuff line near the armpit fold", "back", "Rotator cuff"),
  occipital: pairedLandmarks(0.08, 2.16, -0.18, [0.14, -0.08, -0.99], "base of skull just off the centerline", "back", "Upper neck"),
  c6_c7: withMidline(
    pairedLandmarks(0.04, 1.93, -0.26, [0.1, 0, -1], "base of neck beside the C6-C7 junction", "back", "Lower neck"),
    landmark([0, 1.93, -0.27], [0, 0, -1], "Base of neck at the C6-C7 bump", "back", "Lower neck"),
  ),
  levator: pairedLandmarks(0.23, 1.82, -0.25, [0.45, 0, -0.89], "upper inside shoulder blade where neck meets shoulder", "back", "Levator"),
  rhomboid: pairedLandmarks(0.2, 1.59, -0.39, [0.28, 0, -0.96], "muscle between the spine and inner shoulder blade", "back", "Rhomboid"),
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
  posterior_knee_above_fossa: pairedLandmarks(0.23, -0.52, -0.22, [0.18, 0, -0.98], "back of knee above the crease; avoid the center of the knee crease", "back", "Posterior knee"),
  anterior_medial_elbow: pairedLandmarks(0.84, 1.33, 0.1, [-0.6, 0, 0.8], "inside-front elbow crease near the flexor tendon", "side", "Elbow"),
  posterior_medial_elbow: pairedLandmarks(0.84, 1.33, -0.12, [-0.58, 0, -0.82], "inside-back elbow beside the elbow point", "side", "Elbow"),
  anterior_lateral_elbow: pairedLandmarks(0.96, 1.33, 0.1, [0.7, 0, 0.71], "outside-front elbow near the extensor tendon", "side", "Elbow"),
  posterior_lateral_elbow: pairedLandmarks(0.96, 1.33, -0.12, [0.68, 0, -0.73], "outside-back elbow beside the elbow point", "side", "Elbow"),
  anterior_distal_forearm: pairedLandmarks(1.06, 0.92, 0.12, [0.45, 0, 0.89], "palm-side lower forearm above the wrist", "side", "Forearm"),
  posterior_distal_forearm: pairedLandmarks(1.06, 0.92, -0.1, [0.44, 0, -0.9], "back-side lower forearm above the wrist", "side", "Forearm"),
  medial_malleolus: pairedLandmarks(0.13, -1.62, 0.04, [-0.86, 0, 0.5], "inside ankle above the ankle bone", "front", "Ankle"),
  lateral_malleolus: pairedLandmarks(0.34, -1.62, 0.03, [0.86, 0, 0.5], "outside ankle above the ankle bone", "front", "Ankle"),
  plantar_foot: pairedLandmarks(0.23, -1.83, -0.05, [0, -0.45, -0.89], "bottom of foot through the arch area", "side", "Foot"),
  dorsal_foot: pairedLandmarks(0.23, -1.8, 0.2, [0, 0.25, 0.97], "top of foot over the midfoot", "side", "Foot"),
};

export const PAD_LANDMARKS = {
  ...LOCAL_PAD_LANDMARKS,
  ...sharedPadLandmarks(),
};

/**
 * Curated-zone resolution. Returns `{position, normal, cue, view, region,
 * mapped, fallback}`.
 *
 * `fallback: true` marks a marker with no curated landmark for its zone (e.g. a
 * performance pad, whose zone is a synthetic `perf-sun-0` key). The caller
 * reseeds those from anchors or muscle geometry instead of leaving every one of
 * them stacked on the low_back_l23 default.
 */
export function resolveLandmark(marker) {
  const override = marker.landmarkOverride;
  if (Array.isArray(override?.position) && Array.isArray(override?.normal)) {
    return {
      ...DEFAULT_LANDMARK,
      position: override.position,
      normal: override.normal,
      cue: override.cue || marker.label || DEFAULT_LANDMARK.cue,
      view: override.view || marker.surface || DEFAULT_LANDMARK.view,
      region: override.region || marker.zone || DEFAULT_LANDMARK.region,
      mapped: true,
      fallback: false,
    };
  }

  // `landmarkZone` is the mobile adapter's carrier for pad_marker_mapper's
  // `resolveZone()` output: `zone` itself is the synthetic per-set key, so the
  // curated lookup has to consult the real landmark key separately.
  const zoneKey = PAD_LANDMARKS[marker.zone]
    ? marker.zone
    : marker.landmarkZone;
  const known = PAD_LANDMARKS[zoneKey];
  const zone = known || PAD_LANDMARKS.low_back_l23;
  const base = {
    ...DEFAULT_LANDMARK,
    ...(zone[marker.side] || zone.midline || zone.right || DEFAULT_LANDMARK),
    fallback: !known,
  };
  return refineLandmark({ ...marker, zone: zoneKey }, base);
}

function refined(base, position, normal, cue) {
  return {
    ...base,
    position,
    normal,
    cue,
  };
}

/**
 * Label-driven micro-offsets within a curated zone: 32 zone branches / 47
 * refinements. This is what moves "VMO" off the generic medial-knee point and
 * onto the muscle above the kneecap.
 *
 * NOTE `marker.label` here must be the MUSCLE NAME, not the written cue. The
 * mobile adapter maps `targetMuscles[0]` -> `label` and the mobile pad cue ->
 * `cue` precisely so `has()` matches against anatomy terms rather than prose.
 */
export function refineLandmark(marker, base) {
  const label = String(marker.label || "").toLowerCase();
  const sign = sideSign(marker.side);
  const has = (...terms) => terms.some((term) => label.includes(term));

  if (marker.zone === "low_back_l23") {
    if (has("lumbar erector", "lumbar")) {
      return refined(base, [sign * 0.12, 1.14, -0.4], [sign * 0.16, 0, -0.99], `${base.cue}; bias over the lumbar erector column beside the spine`);
    }
    if (has("l2-l3", "l2", "l3")) {
      return refined(base, [sign * 0.12, 1.18, -0.42], [sign * 0.16, 0, -0.99], `${base.cue}; align at the documented L2-L3 level`);
    }
  }

  if (marker.zone === "iliac_fossa") {
    if (has("iliopsoas", "psoas", "hip flexor", "front inner hip")) {
      return refined(base, [sign * 0.18, 0.82, 0.35], [sign * 0.2, 0, 0.98], `${base.cue}; bias medially into the iliopsoas/front hip-flexor pocket`);
    }
    if (has("iliacus", "iliac fossa")) {
      return refined(base, [sign * 0.21, 0.78, 0.34], [sign * 0.26, 0, 0.97], `${base.cue}; bias over the iliac fossa inside the front hip bone`);
    }
  }

  if (marker.zone === "glute") {
    if (has("lateral glute", "glute max belly", "right glute max", "left glute max")) {
      return refined(base, [sign * 0.26, 0.56, -0.36], [sign * 0.52, 0, -0.86], `${base.cue}; bias to the outer glute muscle belly`);
    }
    if (has("insertion")) {
      return refined(base, [sign * 0.16, 0.48, -0.42], [sign * 0.22, 0, -0.98], `${base.cue}; bias lower toward the glute insertion fold`);
    }
  }

  if (marker.zone === "hamstring_origin") {
    if (has("medial")) {
      return refined(base, [sign * 0.14, 0.41, -0.34], [sign * 0.14, -0.03, -0.99], `${base.cue}; bias slightly inward at the medial sit-bone / proximal hamstring origin`);
    }
    if (has("lateral", "ischial", "sit bone")) {
      return refined(base, [sign * 0.23, 0.43, -0.35], [sign * 0.34, -0.03, -0.94], `${base.cue}; bias outward at the lateral ischial tuberosity / sit-bone line`);
    }
  }

  if (marker.zone === "posterior_hip") {
    if (has("piriformis", "external rotator")) {
      return refined(base, [sign * 0.29, 0.7, -0.39], [sign * 0.5, 0, -0.87], `${base.cue}; bias over the deep external-rotator pocket`);
    }
    if (has("glute medius")) {
      return refined(base, [sign * 0.32, 0.79, -0.29], [sign * 0.58, 0, -0.82], `${base.cue}; bias high and lateral over glute medius`);
    }
    if (has("ilium", "deep low-back side muscle", "ql")) {
      return refined(base, [sign * 0.25, 0.86, -0.31], [sign * 0.44, 0, -0.9], `${base.cue}; bias toward the posterior iliac crest / QL attachment line`);
    }
  }

  if (marker.zone === "anterior_hip") {
    if (has("tfl", "front outer hip")) {
      return refined(base, [sign * 0.34, 0.8, 0.27], [sign * 0.62, 0, 0.78], `${base.cue}; bias outward on the TFL/front outer hip line`);
    }
    if (has("hip flexor")) {
      return refined(base, [sign * 0.24, 0.82, 0.33], [sign * 0.35, 0, 0.94], `${base.cue}; bias toward the front hip-flexor line`);
    }
  }

  if (marker.zone === "thoracolumbar") {
    if (has("thoracolumbar junction", "thoracolumbar erector", "t12", "l1", "lower rib", "upper lumbar")) {
      return refined(base, [sign * 0.07, 1.27, -0.43], [sign * 0.08, 0, -1], `${base.cue}; exact thoracolumbar junction: paired just beside the spine at the lower-rib / upper-waist line`);
    }
  }

  if (marker.zone === "lat") {
    if (has("low-back tissue sheet", "thoracolumbar fascia")) {
      return refined(base, [sign * 0.34, 1.23, -0.31], [sign * 0.66, 0, -0.75], `${base.cue}; bias lower toward the lat/thoracolumbar fascia sheet`);
    }
    if (has("lat")) {
      return refined(base, [sign * 0.4, 1.38, -0.25], [sign * 0.72, 0, -0.7], `${base.cue}; bias over the latissimus dorsi muscle belly`);
    }
  }

  if (marker.zone === "external_oblique") {
    if (has("rectus")) {
      return refined(base, [sign * 0.2, 1.08, 0.33], [sign * 0.35, 0, 0.94], `${base.cue}; bias between rectus abdominis and external oblique`);
    }
    return refined(base, [sign * 0.31, 1.09, 0.28], [sign * 0.58, 0, 0.82], `${base.cue}; bias over the external oblique muscle belly`);
  }

  if (marker.zone === "anterior_deltoid") {
    if (has("pec")) {
      return refined(base, [sign * 0.43, 1.62, 0.16], [sign * 0.58, 0.04, 0.82], `${base.cue}; bias to the upper pec/front-shoulder fold`);
    }
    if (has("anterior deltoid")) {
      return refined(base, [sign * 0.53, 1.72, 0.13], [sign * 0.74, 0.04, 0.67], `${base.cue}; bias over the front shoulder cap`);
    }
  }

  if (marker.zone === "posterior_deltoid" && has("posterior deltoid")) {
    return refined(base, [sign * 0.5, 1.68, -0.22], [sign * 0.64, 0.03, -0.77], `${base.cue}; bias over the back shoulder cap`);
  }

  if (marker.zone === "teres_superior") {
    return refined(base, [sign * 0.43, 1.62, -0.31], [sign * 0.56, 0, -0.83], `${base.cue}; bias to the upper teres/rotator-cuff line below the rear shoulder`);
  }

  if (marker.zone === "teres_inferior") {
    if (has("infraspinatus")) {
      return refined(base, [sign * 0.34, 1.57, -0.36], [sign * 0.4, 0, -0.92], `${base.cue}; bias medially over infraspinatus on the back shoulder blade`);
    }
    if (has("teres", "rotator cuff")) {
      return refined(base, [sign * 0.43, 1.5, -0.35], [sign * 0.54, 0, -0.84], `${base.cue}; bias to the lower teres border near the posterior armpit fold`);
    }
  }

  if (marker.zone === "upper_trap" && has("supraspinatus", "top rotator cuff")) {
    return refined(base, [sign * 0.42, 1.8, -0.18], [sign * 0.58, 0.1, -0.81], `${base.cue}; bias laterally over supraspinatus/top rotator-cuff fossa rather than the neck trap`);
  }

  if (marker.zone === "levator" && has("levator")) {
    return refined(base, [sign * 0.22, 1.83, -0.26], [sign * 0.42, 0, -0.91], `${base.cue}; bias at the upper medial scapula where levator scapulae attaches`);
  }

  if (marker.zone === "rhomboid" && has("rhomboid")) {
    return refined(base, [sign * 0.19, 1.58, -0.4], [sign * 0.24, 0, -0.97], `${base.cue}; bias on the rhomboid between spine and medial scapula border`);
  }

  if (marker.zone === "serratus" && has("serratus")) {
    return refined(base, [sign * 0.48, 1.45, 0.03], [sign * 0.94, 0, 0.34], `${base.cue}; bias on serratus anterior over the side ribs under the scapula`);
  }

  if (marker.zone === "medial_knee_superior") {
    if (has("quad", "vmo", "inside quad")) {
      return refined(base, [sign * 0.17, -0.38, 0.19], [sign * -0.35, 0, 0.94], `${base.cue}; bias higher over VMO / medial quadriceps above the kneecap`);
    }
    if (has("mcl")) {
      return refined(base, [sign * 0.13, -0.5, 0.12], [sign * -0.7, 0, 0.72], `${base.cue}; bias on the medial collateral ligament joint-line area`);
    }
  }

  if (marker.zone === "lateral_knee_superior") {
    if (has("quad", "vl", "outside quad")) {
      return refined(base, [sign * 0.29, -0.36, 0.17], [sign * 0.56, 0, 0.83], `${base.cue}; bias higher over vastus lateralis / outside quadriceps`);
    }
    if (has("lcl")) {
      return refined(base, [sign * 0.31, -0.5, 0.09], [sign * 0.74, 0, 0.67], `${base.cue}; bias on the lateral collateral ligament joint-line area`);
    }
  }

  if (marker.zone === "medial_knee_inferior") {
    if (has("anterior tibialis", "tibialis")) {
      return refined(base, [sign * 0.18, -0.68, 0.18], [sign * -0.28, 0, 0.96], `${base.cue}; bias just below the knee on proximal anterior tibialis`);
    }
    if (has("mcl")) {
      return refined(base, [sign * 0.13, -0.61, 0.12], [sign * -0.7, 0, 0.72], `${base.cue}; bias on the lower medial collateral ligament line`);
    }
  }

  if (marker.zone === "lateral_knee_inferior") {
    if (has("fibular head", "peroneal")) {
      return refined(base, [sign * 0.33, -0.58, 0.06], [sign * 0.85, 0, 0.52], `${base.cue}; bias on the fibular head / peroneal origin area`);
    }
    if (has("lcl", "lateral stabilizer")) {
      return refined(base, [sign * 0.31, -0.61, 0.09], [sign * 0.75, 0, 0.66], `${base.cue}; bias on the lower lateral collateral ligament line`);
    }
  }

  if (marker.zone === "above_patella" && has("quad tendon")) {
    return refined(base, [sign * 0.23, -0.46, 0.24], [0, 0, 1], `${base.cue}; center on the quadriceps tendon above the kneecap`);
  }

  if (marker.zone === "below_patella" && has("patellar tendon")) {
    return refined(base, [sign * 0.23, -0.65, 0.24], [0, 0, 1], `${base.cue}; center on the patellar tendon below the kneecap`);
  }

  if (marker.zone === "posterior_knee_above_fossa" && has("popliteal", "posterior knee")) {
    return refined(base, [sign * 0.22, -0.5, -0.23], [sign * 0.18, 0, -0.98], `${base.cue}; stay above the popliteal crease, not in the center of the fossa`);
  }

  if (marker.zone === "anterior_medial_elbow" && has("flexor", "pronator", "ucl", "medial elbow")) {
    return refined(base, [sign * 0.83, 1.32, 0.08], [sign * -0.58, 0, 0.82], `${base.cue}; bias over the flexor-pronator origin / UCL side`);
  }

  if (marker.zone === "posterior_medial_elbow" && has("olecranon", "triceps", "posterior elbow")) {
    return refined(base, [sign * 0.83, 1.27, -0.08], [sign * -0.2, 0, -0.98], `${base.cue}; bias over the olecranon/triceps side of the elbow point`);
  }

  if (marker.zone === "anterior_distal_forearm" && has("flexor", "pronation", "palmar")) {
    return refined(base, [sign * 1.02, 0.93, 0.11], [sign * 0.34, 0, 0.94], `${base.cue}; bias over the lower forearm flexor/pronation mass`);
  }

  if (marker.zone === "posterior_distal_forearm" && has("supinator", "extensor", "dorsal")) {
    return refined(base, [sign * 1.04, 0.94, -0.1], [sign * 0.36, 0, -0.93], `${base.cue}; bias over the lower forearm extensor/supinator mass`);
  }

  if (marker.zone === "medial_malleolus" && has("posterior tibialis", "deltoid ligament", "medial ankle")) {
    return refined(base, [sign * 0.13, -1.57, 0.03], [sign * -0.88, 0, 0.48], `${base.cue}; bias just above the medial malleolus on posterior tibialis/deltoid ligament line`);
  }

  if (marker.zone === "lateral_malleolus" && has("peroneal", "high-ankle", "lateral ankle")) {
    return refined(base, [sign * 0.34, -1.56, 0.03], [sign * 0.88, 0, 0.48], `${base.cue}; bias above the lateral malleolus toward peroneal/high-ankle structures`);
  }

  if (marker.zone === "dorsal_foot" && has("tibialis anterior", "dorsal")) {
    return refined(base, [sign * 0.23, -1.78, 0.19], [0, 0.22, 0.98], `${base.cue}; bias over the dorsal midfoot / tibialis anterior insertion line`);
  }

  if (marker.zone === "plantar_foot" && has("plantar", "fascia")) {
    return refined(base, [sign * 0.23, -1.84, -0.05], [0, -0.46, -0.89], `${base.cue}; bias along the plantar fascia through the arch`);
  }

  return base;
}
