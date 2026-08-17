// AUTO-GENERATED from Hydrawav3-ai/lib/zAnatomyMapping.ts (MAPPING dict).
// Do not edit by hand; re-extract if the web mapping changes.

export const MAPPING = {
  // === HIP / PELVIS ===
  "psoas major": { both: ["Psoas major"] },
  "left psoas major": { left: ["Psoas major"] },
  "right psoas major": { right: ["Psoas major"] },
  iliacus: { both: ["Iliacus muscle"] },
  "left iliacus": { left: ["Iliacus muscle"] },
  "right iliacus": { right: ["Iliacus muscle"] },
  iliopsoas: { both: ["Psoas major", "Iliacus muscle"] },
  "left iliopsoas": { left: ["Psoas major", "Iliacus muscle"] },
  "right iliopsoas": { right: ["Psoas major", "Iliacus muscle"] },
  "ilio-psoas": { both: ["Psoas major", "Iliacus muscle"] },
  "gluteus maximus": { both: ["Gluteus maximus muscle"] },
  "left gluteus maximus": { left: ["Gluteus maximus muscle"] },
  "right gluteus maximus": { right: ["Gluteus maximus muscle"] },
  "gluteus medius": { both: ["Gluteus medius muscle"] },
  "left gluteus medius": { left: ["Gluteus medius muscle"] },
  "right gluteus medius": { right: ["Gluteus medius muscle"] },
  "gluteus minimus": { both: ["Gluteus minimus muscle"] },
  "left gluteus minimus": { left: ["Gluteus minimus muscle"] },
  "right gluteus minimus": { right: ["Gluteus minimus muscle"] },
  piriformis: { both: ["Piriformis muscle"] },
  "left piriformis": { left: ["Piriformis muscle"] },
  "right piriformis": { right: ["Piriformis muscle"] },
  "tensor fasciae latae": { both: ["Iliotibial tract"] },
  "left tensor fasciae latae": { left: ["Iliotibial tract"] },
  "right tensor fasciae latae": { right: ["Iliotibial tract"] },
  "tensor fasciae latae/iliotibial band": { both: ["Iliotibial tract"] },
  "left tensor fasciae latae/iliotibial band": { left: ["Iliotibial tract"] },
  "right tensor fasciae latae/iliotibial band": { right: ["Iliotibial tract"] },
  tfl: { both: ["Iliotibial tract"] },
  "left tfl": { left: ["Iliotibial tract"] },
  "right tfl": { right: ["Iliotibial tract"] },
  "it band": { both: ["Iliotibial tract"] },
  "left it band": { left: ["Iliotibial tract"] },
  "right it band": { right: ["Iliotibial tract"] },
  "iliotibial band": { both: ["Iliotibial tract"] },
  "left iliotibial band": { left: ["Iliotibial tract"] },
  "right iliotibial band": { right: ["Iliotibial tract"] },
  "hip adductors": {
    both: ["Adductor longus", "Adductor brevis", "Adductor magnus"],
  },
  adductors: {
    both: ["Adductor longus", "Adductor brevis", "Adductor magnus"],
  },
  "adductor longus": { both: ["Adductor longus"] },
  "left adductor longus": { left: ["Adductor longus"] },
  "right adductor longus": { right: ["Adductor longus"] },
  "adductor brevis": { both: ["Adductor brevis"] },
  "left adductor brevis": { left: ["Adductor brevis"] },
  "right adductor brevis": { right: ["Adductor brevis"] },
  "adductor magnus": { both: ["Adductor magnus"] },
  "left adductor magnus": { left: ["Adductor magnus"] },
  "right adductor magnus": { right: ["Adductor magnus"] },
  "obturator internus": { both: ["Obturator internus"] },

  // === THIGH ===
  "rectus femoris": { both: ["Rectus femoris muscle"] },
  "left rectus femoris": { left: ["Rectus femoris muscle"] },
  "right rectus femoris": { right: ["Rectus femoris muscle"] },
  "vastus lateralis": { both: ["Vastus lateralis muscle"] },
  "left vastus lateralis": { left: ["Vastus lateralis muscle"] },
  "right vastus lateralis": { right: ["Vastus lateralis muscle"] },
  "vastus medialis": { both: ["Vastus medialis muscle"] },
  "left vastus medialis": { left: ["Vastus medialis muscle"] },
  "right vastus medialis": { right: ["Vastus medialis muscle"] },
  "vastus medialis oblique": { both: ["Vastus medialis muscle"] },
  "left vastus medialis oblique": { left: ["Vastus medialis muscle"] },
  "right vastus medialis oblique": { right: ["Vastus medialis muscle"] },
  vmo: { both: ["Vastus medialis muscle"] },
  "left vmo": { left: ["Vastus medialis muscle"] },
  "right vmo": { right: ["Vastus medialis muscle"] },
  // The 4th quad part had no standalone key — only reachable via the
  // `quadriceps` bundle below, unlike its three siblings above. Added so a pad
  // naming it specifically resolves to just this mesh instead of the bundle.
  "vastus intermedius": { both: ["Vastus intermedius muscle"] },
  "left vastus intermedius": { left: ["Vastus intermedius muscle"] },
  "right vastus intermedius": { right: ["Vastus intermedius muscle"] },
  quadriceps: {
    both: [
      "Rectus femoris muscle",
      "Vastus lateralis muscle",
      "Vastus medialis muscle",
      "Vastus intermedius muscle",
    ],
  },
  "left quadriceps": {
    left: [
      "Rectus femoris muscle",
      "Vastus lateralis muscle",
      "Vastus medialis muscle",
      "Vastus intermedius muscle",
    ],
  },
  "right quadriceps": {
    right: [
      "Rectus femoris muscle",
      "Vastus lateralis muscle",
      "Vastus medialis muscle",
      "Vastus intermedius muscle",
    ],
  },
  hamstrings: {
    both: [
      "Long head of biceps femoris",
      "Short head of biceps femoris",
      "Semitendinosus muscle",
      "Semimembranosus muscle",
    ],
  },
  "left hamstrings": {
    left: [
      "Long head of biceps femoris",
      "Short head of biceps femoris",
      "Semitendinosus muscle",
      "Semimembranosus muscle",
    ],
  },
  "right hamstrings": {
    right: [
      "Long head of biceps femoris",
      "Short head of biceps femoris",
      "Semitendinosus muscle",
      "Semimembranosus muscle",
    ],
  },
  "biceps femoris": {
    both: ["Long head of biceps femoris", "Short head of biceps femoris"],
  },
  "left biceps femoris": { left: ["Long head of biceps femoris", "Short head of biceps femoris"] },
  "right biceps femoris": { right: ["Long head of biceps femoris", "Short head of biceps femoris"] },
  semitendinosus: { both: ["Semitendinosus muscle"] },
  "left semitendinosus": { left: ["Semitendinosus muscle"] },
  "right semitendinosus": { right: ["Semitendinosus muscle"] },
  semimembranosus: { both: ["Semimembranosus muscle"] },
  "left semimembranosus": { left: ["Semimembranosus muscle"] },
  "right semimembranosus": { right: ["Semimembranosus muscle"] },
  sartorius: { both: ["Sartorius muscle"] },
  "left sartorius": { left: ["Sartorius muscle"] },
  "right sartorius": { right: ["Sartorius muscle"] },
  gracilis: { both: ["Gracilis muscle"] },
  "left gracilis": { left: ["Gracilis muscle"] },
  "right gracilis": { right: ["Gracilis muscle"] },

  // === LOWER LEG ===
  gastrocnemius: {
    both: ["Lateral head of gastrocnemius", "Medial head of gastrocnemius"],
  },
  soleus: { both: ["Soleus muscle"] },
  calves: {
    both: [
      "Lateral head of gastrocnemius",
      "Medial head of gastrocnemius",
      "Soleus muscle",
    ],
  },
  "left calves": {
    left: [
      "Lateral head of gastrocnemius",
      "Medial head of gastrocnemius",
      "Soleus muscle",
    ],
  },
  "right calves": {
    right: [
      "Lateral head of gastrocnemius",
      "Medial head of gastrocnemius",
      "Soleus muscle",
    ],
  },
  "left gastrocnemius": { left: ["Lateral head of gastrocnemius", "Medial head of gastrocnemius"] },
  "right gastrocnemius": { right: ["Lateral head of gastrocnemius", "Medial head of gastrocnemius"] },
  // Lateral/medial HEAD, not left/right body side — a pad authored against just
  // one head (e.g. a lymphatic "over-node" placement naming "lateral"/"medial"
  // explicitly) used to fall back to the combined `gastrocnemius` entry above
  // and resolve to BOTH heads regardless, which is what put Sun and Moon on
  // the exact same two meshes for a calf chain meaning to keep them apart.
  "lateral head of gastrocnemius": { both: ["Lateral head of gastrocnemius"] },
  "medial head of gastrocnemius": { both: ["Medial head of gastrocnemius"] },
  "gastrocnemius lateral head": { both: ["Lateral head of gastrocnemius"] },
  "gastrocnemius medial head": { both: ["Medial head of gastrocnemius"] },
  "lateral gastrocnemius": { both: ["Lateral head of gastrocnemius"] },
  "medial gastrocnemius": { both: ["Medial head of gastrocnemius"] },
  "left soleus": { left: ["Soleus muscle"] },
  "right soleus": { right: ["Soleus muscle"] },
  "tibialis anterior": { both: ["Tibialis anterior muscle"] },
  "left tibialis anterior": { left: ["Tibialis anterior muscle"] },
  "right tibialis anterior": { right: ["Tibialis anterior muscle"] },
  "peroneus longus": { both: ["Fibularis longus muscle"] },
  plantaris: { both: ["Plantaris muscle"] },

  // === SPINE / BACK ===
  "erector spinae": {
  both: [
    "Iliocostalis lumborum muscle",
    "Iliocostalis thoracis muscle",
    "Longissimus thoracis muscle",
    "Spinalis thoracis muscle",
  ],
},
  "left erector spinae": {
  left: [
    "Iliocostalis lumborum muscle",
    "Iliocostalis thoracis muscle",
    "Longissimus thoracis muscle",
    "Spinalis thoracis muscle",
  ],
},

"right erector spinae": {
  right: [
    "Iliocostalis lumborum muscle",
    "Iliocostalis thoracis muscle",
    "Longissimus thoracis muscle",
    "Spinalis thoracis muscle",
  ],
},
  multifidus: {
    both: [
      "Multifidus lumborum muscle",
      "Multifidus thoracis muscle",
      "Multifidus colli muscle",
    ],
  },
  "quadratus lumborum": { both: ["Quadratus lumborum muscle"] },
  "left quadratus lumborum": { left: ["Quadratus lumborum muscle"] },
  "right quadratus lumborum": { right: ["Quadratus lumborum muscle"] },
  "latissimus dorsi": { both: ["Latissimus dorsi muscle"] },
  "thoracolumbar fascia": {
    both: [
      "Latissimus dorsi muscle",
      "Iliocostalis lumborum muscle",
    ],
  },

  // === UPPER BACK / NECK ===
  "upper trapezius": { both: ["Descending part of trapezius muscle"] },
  trapezius: {
    both: [
      "Descending part of trapezius muscle",
      "Transverse part of trapezius muscle",
      "Ascending part of trapezius muscle",
    ],
  },
  "middle trapezius": { both: ["Transverse part of trapezius muscle"] },
  "lower trapezius": { both: ["Ascending part of trapezius muscle"] },
  rhomboids: { both: ["Rhomboid major muscle", "Rhomboid minor muscle"] },
  "levator scapulae": { both: ["Levator scapulae"] },
  sternocleidomastoid: { both: ["Sternocleidomastoid muscle"] },
  scm: { both: ["Sternocleidomastoid muscle"] },
  scalenes: {
    both: [
      "Scalenus anterior muscle",
      "Scalenus medius muscle",
      "Scalenus posterior muscle",
    ],
  },
  "deep neck flexors": {
  both: [
    "Sternocleidomastoid muscle",
    "Scalenus anterior muscle",
    "Scalenus medius muscle",
  ],
},

"deep cervical flexors": {
  both: [
    "Sternocleidomastoid muscle",
    "Scalenus anterior muscle",
    "Scalenus medius muscle",
  ],
},

"longus colli": {
  both: [
    "Sternocleidomastoid muscle",
    "Scalenus anterior muscle",
    "Scalenus medius muscle",
  ],
},
  suboccipitals: {
    both: [
      "Rectus posterior major capitis muscle",
      "Rectus posterior minor capitis muscle",
      "Obliquus superior capitis muscle",
      "Obliquus inferior capitis muscle",
    ],
  },

  // === SHOULDER ===
  deltoids: {
    both: [
      "Acromial part of deltoid muscle",
      "Clavicular part of deltoid muscle",
      "Scapular spinal part of deltoid muscle",
    ],
  },
  deltoid: {
    both: [
      "Acromial part of deltoid muscle",
      "Clavicular part of deltoid muscle",
      "Scapular spinal part of deltoid muscle",
    ],
  },
  "left deltoid": {
    left: [
      "Acromial part of deltoid muscle",
      "Clavicular part of deltoid muscle",
      "Scapular spinal part of deltoid muscle",
    ],
  },
  "right deltoid": {
    right: [
      "Acromial part of deltoid muscle",
      "Clavicular part of deltoid muscle",
      "Scapular spinal part of deltoid muscle",
    ],
  },
  // Anterior/posterior deltoid, split from the shared "deltoid" entry above so
  // a Sun-anterior + Moon-posterior pad pair resolve to DIFFERENT meshes
  // instead of both claiming all 3 deltoid parts (Sun claiming first left
  // nothing for Moon to highlight). Mesh names match Hydrawave3's
  // AnatomyScene.jsx, which already keeps this split.
  "anterior deltoid": {
    both: ["Clavicular part of deltoid muscle"],
  },
  "posterior deltoid": {
    both: ["Scapular spinal part of deltoid muscle"],
  },
  "rotator cuff": {
    both: [
      "Supraspinatus muscle",
      "Infraspinatus muscle",
      "Teres minor muscle",
      "Subscapularis muscle",
    ],
  },
  subscapularis: { both: ["Subscapularis muscle"] },
  infraspinatus: { both: ["Infraspinatus muscle"] },
  supraspinatus: { both: ["Supraspinatus muscle"] },
  "teres major": { both: ["Teres major muscle"] },
  "teres minor": { both: ["Teres minor muscle"] },
  "serratus anterior": { both: ["Serratus anterior muscle"] },

  // === CHEST ===
  "pectoralis major": {
    both: [
      "Sternocostal head of pectoralis major muscle",
      "Clavicular head of pectoralis major muscle",
      "(Abdominal part of pectoralis major muscle)",
    ],
  },
  "pectoralis minor": { both: ["Pectoralis minor muscle"] },
  pecs: {
    both: [
      "Sternocostal head of pectoralis major muscle",
      "Clavicular head of pectoralis major muscle",
      "(Abdominal part of pectoralis major muscle)",
    ],
  },

  // === CORE ===
  "rectus abdominis": { both: ["Rectus abdominis muscle"] },
  "transverse abdominis": { both: ["Transversus abdominis muscle"] },
  "internal obliques": { both: ["Internal abdominal oblique muscle"] },
  "external obliques": { both: ["External abdominal oblique muscle"] },
  obliques: {
    both: [
      "Internal abdominal oblique muscle",
      "External abdominal oblique muscle",
    ],
  },
  diaphragm: { both: ["Diaphragm"] },

  // === SPINAL SEGMENTS ===
  // Note: Z-Anatomy vertebrae may have different naming - these are educated guesses
  // Will need to verify against actual model mesh names
  "t12": { both: ["T12 vertebra", "Twelfth thoracic vertebra"] },
  "l1": { both: ["L1 vertebra", "First lumbar vertebra"] },
  "l2": { both: ["L2 vertebra", "Second lumbar vertebra"] },
  "l3": { both: ["L3 vertebra", "Third lumbar vertebra"] },
  "l4": { both: ["L4 vertebra", "Fourth lumbar vertebra"] },
  "l5": { both: ["L5 vertebra", "Fifth lumbar vertebra"] },
  "s1": { both: ["S1 vertebra", "First sacral vertebra", "Sacrum"] },
  "s2": { both: ["S2 vertebra", "Second sacral vertebra", "Sacrum"] },
  "t12-l5": { both: ["T12 vertebra", "L1 vertebra", "L2 vertebra", "L3 vertebra", "L4 vertebra", "L5 vertebra"] },
  "l2-l3": { both: ["L2 vertebra", "L3 vertebra"] },
  "l4-l5": { both: ["L4 vertebra", "L5 vertebra"] },
  "l5-s1": { both: ["L5 vertebra", "S1 vertebra", "Sacrum"] },
};
