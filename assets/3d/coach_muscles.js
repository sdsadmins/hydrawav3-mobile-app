/* Muscle name -> Z-Anatomy mesh names: the website's lib/zAnatomyMapping.ts
 * (Hydrawav3-ai, 2026-10-30), compiled to plain JS unchanged, so the app
 * lights the same muscles the admin sees in the Session Coach editor.
 * Re-copy it when the website's mapping changes.
 * highlightMuscles([{name, color}]) lights each set muscle; [] clears it. */
(function () {
var exports = {};
"use strict";
/**
 * Maps our muscle database names → Z-Anatomy mesh names in the GLB model.
 *
 * Z-Anatomy naming convention:
 *   - ".l" suffix = left side, ".r" suffix = right side
 *   - Full Terminologia Anatomica names (e.g., "Gluteus maximus muscle.l")
 *   - Multi-part muscles have separate meshes (e.g., 3 deltoid parts, 3 trapezius parts)
 *
 * Our database names:
 *   - "Gluteus Maximus" → both sides
 *   - "Left Gluteus Maximus" → left only
 *   - "Right Gluteus Maximus" → right only
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.getZAnatomyMeshNames = getZAnatomyMeshNames;
exports.getHighlightMeshNames = getHighlightMeshNames;
// Core mapping: our names → Z-Anatomy mesh name stems
// The stem is the mesh name WITHOUT the .l/.r suffix
const MAPPING = {
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
    "ilio psoas": { both: ["Psoas major", "Iliacus muscle"] },
    // Common misspellings seen in admin data
    iliopsas: { both: ["Psoas major", "Iliacus muscle"] },
    "left iliopsas": { left: ["Psoas major", "Iliacus muscle"] },
    "right iliopsas": { right: ["Psoas major", "Iliacus muscle"] },
    illiopsoas: { both: ["Psoas major", "Iliacus muscle"] },
    "left illiopsoas": { left: ["Psoas major", "Iliacus muscle"] },
    "right illiopsoas": { right: ["Psoas major", "Iliacus muscle"] },
    "gluteus maximus": { both: ["Gluteus maximus muscle"] },
    "gluteal maximus": { both: ["Gluteus maximus muscle"] },
    "left gluteal maximus": { left: ["Gluteus maximus muscle"] },
    "right gluteal maximus": { right: ["Gluteus maximus muscle"] },
    glutes: { both: ["Gluteus maximus muscle", "Gluteus medius muscle", "Gluteus minimus muscle"] },
    gluteals: { both: ["Gluteus maximus muscle", "Gluteus medius muscle", "Gluteus minimus muscle"] },
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
    // Region-level admin names (no single muscle): highlight the muscle group of that area.
    "mid back": {
        both: [
            "Transverse part of trapezius muscle",
            "Rhomboid major muscle",
            "Rhomboid minor muscle",
            "Iliocostalis thoracis muscle",
            "Longissimus thoracis muscle",
            "Spinalis thoracis muscle",
        ],
    },
    "middle back": {
        both: [
            "Transverse part of trapezius muscle",
            "Rhomboid major muscle",
            "Rhomboid minor muscle",
            "Iliocostalis thoracis muscle",
            "Longissimus thoracis muscle",
            "Spinalis thoracis muscle",
        ],
    },
    "lower back": {
        both: ["Iliocostalis lumborum muscle", "Multifidus lumborum muscle", "Quadratus lumborum muscle"],
    },
    "low back": {
        both: ["Iliocostalis lumborum muscle", "Multifidus lumborum muscle", "Quadratus lumborum muscle"],
    },
    "upper back": {
        both: ["Descending part of trapezius muscle", "Rhomboid major muscle", "Rhomboid minor muscle", "Levator scapulae"],
    },
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
    // === UPPER ARM ===
    // Side words ("Left Triceps Brachii", "Arm - Upper - Back - Right ...") are handled by the lookup,
    // so only the base names are needed here.
    "triceps brachii": {
        both: ["Long head of triceps brachii", "Lateral head of triceps brachii", "Medial head of triceps brachii"],
    },
    triceps: {
        both: ["Long head of triceps brachii", "Lateral head of triceps brachii", "Medial head of triceps brachii"],
    },
    "biceps brachii": { both: ["Long head of biceps brachii", "Short head of biceps brachii"] },
    biceps: { both: ["Long head of biceps brachii", "Short head of biceps brachii"] },
    brachialis: { both: ["Brachialis muscle"] },
    coracobrachialis: { both: ["Coracobrachialis muscle"] },
    anconeus: { both: ["Anconeus muscle"] },
    // === FOREARM ===
    brachioradialis: { both: ["Brachioradialis muscle"] },
    "pronator teres": { both: ["Superficial head of pronator teres", "Deep head of pronator teres"] },
    "pronator quadratus": { both: ["Pronator quadratus"] },
    supinator: { both: ["Supinator"] },
    "palmaris longus": { both: ["Palmaris longus muscle"] },
    "flexor carpi radialis": { both: ["Flexor carpi radialis"] },
    "flexor carpi ulnaris": { both: ["Humeral head of flexor carpi ulnaris", "Ulnar head of flexor carpi ulnaris"] },
    "extensor carpi radialis": { both: ["Extensor carpi radialis longus", "Extensor carpi radialis brevis"] },
    "extensor carpi radialis longus": { both: ["Extensor carpi radialis longus"] },
    "extensor carpi radialis brevis": { both: ["Extensor carpi radialis brevis"] },
    "extensor carpi ulnaris": { both: ["Humeral head of extensor carpi ulnaris", "Ulnar head of extensor carpi ulnaris"] },
    "extensor digitorum": { both: ["Extensor digitorum"] },
    "flexor digitorum superficialis": {
        both: ["Humero-ulnar head of flexor digitorum superficialis", "Radial head of flexor digitorum superficialis"],
    },
    "flexor digitorum profundus": { both: ["Flexor digitorum profundus"] },
    "flexor pollicis longus": { both: ["Flexor pollicis longus"] },
    "wrist flexors": {
        both: ["Flexor carpi radialis", "Humeral head of flexor carpi ulnaris", "Ulnar head of flexor carpi ulnaris", "Palmaris longus muscle"],
    },
    "wrist extensors": {
        both: [
            "Extensor carpi radialis longus",
            "Extensor carpi radialis brevis",
            "Humeral head of extensor carpi ulnaris",
            "Ulnar head of extensor carpi ulnaris",
        ],
    },
    // === HAND / WRIST ===
    thenar: {
        both: [
            "Abductor pollicis brevis",
            "Superficial head of flexor pollicis brevis",
            "Deep head of flexor pollicis brevis",
            "Opponens pollicis muscle",
        ],
    },
    hypothenar: {
        both: ["Abductor digiti minimi of hand", "Flexor digiti minimi of hand", "Opponens digiti minimi muscle of hand"],
    },
    "hand abductor digiti minimi": { both: ["Abductor digiti minimi of hand"] },
    "hand flexor digiti minimi": { both: ["Flexor digiti minimi of hand"] },
    palm: {
        both: [
            "Abductor pollicis brevis",
            "Superficial head of flexor pollicis brevis",
            "Deep head of flexor pollicis brevis",
            "Opponens pollicis muscle",
            "Abductor digiti minimi of hand",
            "Flexor digiti minimi of hand",
            "Opponens digiti minimi muscle of hand",
            "Lumbrical muscles of hand",
        ],
    },
    "hand palm": {
        both: [
            "Abductor pollicis brevis",
            "Superficial head of flexor pollicis brevis",
            "Deep head of flexor pollicis brevis",
            "Opponens pollicis muscle",
            "Abductor digiti minimi of hand",
            "Flexor digiti minimi of hand",
            "Opponens digiti minimi muscle of hand",
            "Lumbrical muscles of hand",
        ],
    },
    "hand dorsal": { both: ["Dorsal interossei muscles of hand"] },
    "dorsal interossei": { both: ["Dorsal interossei muscles of hand"] },
    "hand dorsal interossei": { both: ["Dorsal interossei muscles of hand"] },
    "foot dorsal interossei": { both: ["Dorsal interossei muscles of foot"] },
    "palmar interossei": { both: ["Palmar interossei muscles"] },
    lumbricals: { both: ["Lumbrical muscles of hand"] },
    "hand lumbricals": { both: ["Lumbrical muscles of hand"] },
    "foot lumbricals": { both: ["Lumbrical muscles of foot"] },
    "extensor digiti minimi": { both: ["Extensor digiti minimi"] },
    "extensor digit minimi": { both: ["Extensor digiti minimi"] },
    "extensor indicis": { both: ["Extensor indicis"] },
    "abductor pollicis brevis": { both: ["Abductor pollicis brevis"] },
    "abductor pollicis longus": { both: ["Abductor pollicis longus"] },
    "extensor pollicis brevis": { both: ["Extensor pollicis brevis"] },
    "extensor pollicis longus": { both: ["Extensor pollicis longus"] },
    "opponens pollicis": { both: ["Opponens pollicis muscle"] },
    // No retinaculum meshes in the GLB: the tendons that pass under each are the closest neighbours.
    "flexor retinaculum": { both: ["Palmaris longus muscle", "Flexor carpi radialis"] },
    "extensor retinaculum": { both: ["Extensor digitorum", "Extensor carpi radialis brevis"] },
    // Abbreviations used in admin data
    ecrl: { both: ["Extensor carpi radialis longus"] },
    ecrb: { both: ["Extensor carpi radialis brevis"] },
    ecu: { both: ["Humeral head of extensor carpi ulnaris", "Ulnar head of extensor carpi ulnaris"] },
    fcu: { both: ["Humeral head of flexor carpi ulnaris", "Ulnar head of flexor carpi ulnaris"] },
    fcr: { both: ["Flexor carpi radialis"] },
    brachioradalis: { both: ["Brachioradialis muscle"] },
    // === UPPER BACK (additional) ===
    "rhomboid major": { both: ["Rhomboid major muscle"] },
    "rhomboid minor": { both: ["Rhomboid minor muscle"] },
    "serratus posterior superior": { both: ["Serratus posterior superior muscle"] },
    "serratus posterior inferior": { both: ["Serratus posterior inferior muscle"] },
    serratus: { both: ["Serratus anterior muscle"] },
    // No "Semispinalis capitis" mesh in the GLB; these are its neighbours at the occiput.
    "semispinalis capitis": { both: ["Semispinalis colli muscle", "Splenius capitis muscle"] },
    "splenius capitis": { both: ["Splenius capitis muscle"] },
    "splenius cervicis": { both: ["Splenius colli muscle"] },
    // === LOWER LEG / FOOT (additional) ===
    "anterior tibialis": { both: ["Tibialis anterior muscle"] },
    "tibia's anterior": { both: ["Tibialis anterior muscle"] },
    "tibias anterior": { both: ["Tibialis anterior muscle"] },
    "tibialis posterior": { both: ["Tibialis posterior muscle"] },
    "posterior tibialis": { both: ["Tibialis posterior muscle"] },
    "achilles tendon": { both: ["Calcaneal tendon"] },
    achilles: { both: ["Calcaneal tendon"] },
    "calcaneal tendon": { both: ["Calcaneal tendon"] },
    "peroneus brevis": { both: ["Fibularis brevis muscle"] },
    "fibularis longus": { both: ["Fibularis longus muscle"] },
    "fibularis brevis": { both: ["Fibularis brevis muscle"] },
    peroneus: { both: ["Fibularis longus muscle", "Fibularis brevis muscle"] },
    peroneals: { both: ["Fibularis longus muscle", "Fibularis brevis muscle"] },
    "extensor digitorum longus": { both: ["Extensor digitorum longus"] },
    "extensor digitorum brevis": { both: ["Extensor digitorum brevis"] },
    "extensor hallucis longus": { both: ["Extensor hallucis longus"] },
    "extensor hallucis brevis": { both: ["Extensor hallucis brevis"] },
    "flexor digitorum longus": { both: ["Flexor digitorum longus"] },
    "flexor digitorum brevis": { both: ["Flexor digitorum brevis"] },
    "flexor hallucis longus": { both: ["Flexor hallucis longus"] },
    "flexor hallucis brevis": { both: ["Medial head of flexor hallucis brevis", "Lateral head of flexor hallucis brevis"] },
    "abductor hallucis": { both: ["Abductor hallucis"] },
    "adductor hallucis": { both: ["Oblique head of adductor hallucis", "Transverse head of adductor hallucis"] },
    // Bare "abductor digiti minimi" in admin data appears in the foot list; the hand form is "hand abductor digiti minimi".
    "abductor digiti minimi": { both: ["Abductor digiti minimi of foot"] },
    "foot abductor digiti minimi": { both: ["Abductor digiti minimi of foot"] },
    // No plantar fascia mesh; flexor digitorum brevis sits directly on it.
    "plantar fascia": { both: ["Flexor digitorum brevis", "Abductor hallucis"] },
    plantar: { both: ["Flexor digitorum brevis", "Abductor hallucis"] },
    popliteus: { both: ["Popliteus muscle"] },
    // No patellar tendon mesh; the quadriceps insertion is the closest neighbour.
    "patellar tendon": { both: ["Rectus femoris muscle", "Vastus medialis muscle", "Vastus lateralis muscle"] },
    knee: { both: ["Popliteus muscle", "Vastus medialis muscle", "Vastus lateralis muscle"] },
    // === THIGH / HIP (additional) ===
    pectineus: { both: ["Pectineus muscle"] },
    hamstring: { both: ["Long head of biceps femoris", "Short head of biceps femoris", "Semitendinosus muscle", "Semimembranosus muscle"] },
    "biceps femoris short head": { both: ["Short head of biceps femoris"] },
    "biceps femoris long head": { both: ["Long head of biceps femoris"] },
    glute: { both: ["Gluteus maximus muscle"] },
    gluteal: { both: ["Gluteus maximus muscle"] },
    "gluteal maxiumus": { both: ["Gluteus maximus muscle"] },
    // PSIS (posterior superior iliac spine) has no mesh; gluteus maximus originates there.
    psis: { both: ["Gluteus maximus muscle", "Iliocostalis lumborum muscle"] },
    "iliotibial tract": { both: ["Iliotibial tract"] },
    // === CORE (additional) ===
    "transverse abdominus": { both: ["Transversus abdominis muscle"] },
    "transversus abdominus": { both: ["Transversus abdominis muscle"] },
    "internal oblique": { both: ["Internal abdominal oblique muscle"] },
    "external oblique": { both: ["External abdominal oblique muscle"] },
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
    "transversus abdominis": { both: ["Transversus abdominis muscle"] },
    "left transversus abdominis": { left: ["Transversus abdominis muscle"] },
    "right transversus abdominis": { right: ["Transversus abdominis muscle"] },
    tva: { both: ["Transversus abdominis muscle"] },
    "internal obliques": { both: ["Internal abdominal oblique muscle"] },
    "external obliques": { both: ["External abdominal oblique muscle"] },
    obliques: {
        both: [
            "Internal abdominal oblique muscle",
            "External abdominal oblique muscle",
        ],
    },
    diaphragm: { both: ["Diaphragm"] },
    // === HEAD / FACE (facial expression) ===
    frontalis: { both: ["Frontalis muscle"] },
    occipitalis: { both: ["Occipitalis muscle"] },
    occipitofrontalis: { both: ["Frontalis muscle", "Occipitalis muscle"] },
    "orbicularis oculi": {
        both: ["Orbital part of orbicularis oculi", "Palpebral part of orbicularis oculi"],
    },
    "corrugator supercilii": { both: ["Corrugator supercilii"] },
    procerus: { both: ["Procerus muscle"] },
    nasalis: { both: ["Nasalis muscle"] },
    "depressor septi nasi": { both: ["Depressor septi nasi"] },
    "orbicularis oris": { both: ["Orbicularis oris muscle"] },
    buccinator: { both: ["Bucinator"] },
    bucinator: { both: ["Bucinator"] },
    "zygomaticus major": { both: ["Zygomaticus major muscle"] },
    "zygomaticus minor": { both: ["Zygomaticus minor muscle"] },
    zygomaticus: { both: ["Zygomaticus major muscle", "Zygomaticus minor muscle"] },
    "zygomaticus major & minor": { both: ["Zygomaticus major muscle", "Zygomaticus minor muscle"] },
    "levator labii superioris alaeque nasi": { both: ["Levator nasolabialis"] },
    "levator labii superioris": { both: ["Levator labii superioris"] },
    risorius: { both: ["Risorius muscle"] },
    "depressor labii inferioris": { both: ["Depressor labii inferioris"] },
    "depressor anguli oris": { both: ["Depressor anguli oris"] },
    mentalis: { both: ["Mentalis muscle"] },
    "levator anguli oris": { both: ["Levator anguli oris"] },
    platysma: { both: ["Platysma"] },
    // NOTE: Auricularis (anterior/superior/posterior) meshes do NOT exist in the
    // current GLB. Temporoparietalis is the closest available neighbour.
    temporoparietalis: { both: ["Temporoparietalis muscle"] },
    // === MASTICATION (chewing) ===
    masseter: { both: ["Superficial part of masseter", "Deep part of masseter"] },
    temporalis: { both: ["Temporalis muscle"] },
    "medial pterygoid": { both: ["Medial pterygoid muscle"] },
    "lateral pterygoid": {
        both: ["Superior head of lateral pterygoid muscle", "Inferior head of lateral pterygoid muscle"],
    },
    pterygoids: {
        both: [
            "Medial pterygoid muscle",
            "Superior head of lateral pterygoid muscle",
            "Inferior head of lateral pterygoid muscle",
        ],
    },
    // === EXTRAOCULAR (eye movement) ===
    "superior rectus": { both: ["Superior rectus muscle"] },
    "inferior rectus": { both: ["Inferior rectus muscle"] },
    "medial rectus": { both: ["Medial rectus muscle"] },
    "lateral rectus": { both: ["Lateral rectus muscle"] },
    "superior oblique": { both: ["Superior oblique muscle"] },
    "inferior oblique": { both: ["Inferior oblique muscle"] },
    "extraocular muscles": {
        both: [
            "Superior rectus muscle",
            "Inferior rectus muscle",
            "Medial rectus muscle",
            "Lateral rectus muscle",
            "Superior oblique muscle",
            "Inferior oblique muscle",
        ],
    },
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
/** Words that only qualify a muscle ("Distal Gluteus Maximus", "Posterior Deltoid") and can be dropped when no key matches. */
const QUALIFIERS = ["anterior", "posterior", "medial", "lateral", "distal", "proximal", "upper", "lower", "deep", "superficial", "bilateral"];
/** Trailing words that describe an area rather than a muscle. */
const AREA_WORDS = ["region", "area", "muscles", "muscle", "tendons", "tendon", "same side", "level"];
/** Region segments that pick the hand or foot variant of a shared muscle name (lumbricals, interossei...). */
const CONTEXT_REGIONS = ["hand", "foot", "wrist", "ankle"];
/** Keys whose mapping is restricted to one side. */
function sided(m, side) {
    if (side === "left")
        return expandMapping({ left: m.both || m.left || [] });
    if (side === "right")
        return expandMapping({ right: m.both || m.right || [] });
    return expandMapping(m);
}
/** Direct lookup of one normalised name, trying the sided key first. */
function lookupExact(name, side) {
    if (side) {
        const m = MAPPING[`${side} ${name}`];
        if (m)
            return expandMapping(m);
    }
    const m = MAPPING[name];
    return m ? sided(m, side) : null;
}
/** Resolve one muscle (no "&", no "/") to mesh names. */
function resolvePart(raw, side, context) {
    let name = raw.replace(/\s+/g, " ").trim();
    if (!name)
        return [];
    // Strip trailing area words: "popliteus area", "thenar muscles", "achilles tendon region".
    let changed = true;
    while (changed) {
        changed = false;
        for (const w of AREA_WORDS) {
            const re = new RegExp(`\\s+${w}$`);
            if (re.test(name) && MAPPING[name] === undefined) {
                name = name.replace(re, "").trim();
                changed = true;
            }
        }
    }
    if (!name)
        return [];
    // Hand/foot context first ("Hand - Right Lumbricals" → "hand lumbricals").
    if (context) {
        const hit = lookupExact(`${context} ${name}`, side);
        if (hit)
            return hit;
    }
    const direct = lookupExact(name, side);
    if (direct)
        return direct;
    // Drop leading qualifiers one at a time: "distal gluteus maximus" → "gluteus maximus".
    const words = name.split(" ");
    for (let i = 0; i < words.length - 1 && QUALIFIERS.includes(words[i]); i++) {
        const rest = words.slice(i + 1).join(" ");
        const hit = (context && lookupExact(`${context} ${rest}`, side)) || lookupExact(rest, side);
        if (hit)
            return hit;
    }
    // Longest key contained in the name ("semispinalis capitis muscle group" → "semispinalis capitis").
    let best = null;
    for (const key of Object.keys(MAPPING)) {
        if (key.length < 4)
            continue;
        const re = new RegExp(`(^|\\s)${key.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}(\\s|$)`);
        if (re.test(name) && (!best || key.length > best.length))
            best = key;
    }
    if (best)
        return sided(MAPPING[best], side);
    // Finally a name that is a prefix of a key ("rhomboid" → "rhomboid major" + "rhomboid minor").
    if (name.length >= 5) {
        const out = new Set();
        for (const [key, m] of Object.entries(MAPPING)) {
            if (key.startsWith(`${name} `))
                for (const n of sided(m, side))
                    out.add(n);
        }
        if (out.size)
            return Array.from(out);
    }
    return [];
}
/** Expand "extensor carpi radialis longus/brevis" → ["extensor carpi radialis longus", "extensor carpi radialis brevis"]. */
function expandSlash(part) {
    if (!part.includes("/"))
        return [part];
    const words = part.split(" ");
    const i = words.findIndex((w) => w.includes("/"));
    const halves = words[i].split("/").map((h) => h.trim()).filter(Boolean);
    const before = words.slice(0, i).join(" ");
    const after = words.slice(i + 1).join(" ");
    // Suffix form: shared stem + two endings ("... longus/brevis").
    const suffixed = halves.map((h) => [before, h, after].filter(Boolean).join(" "));
    // Whole-name form: two complete names ("tensor fasciae latae/iliotibial band").
    const whole = part.split("/").map((p) => p.trim()).filter(Boolean);
    return [part, ...suffixed, ...whole];
}
/**
 * Given one of our muscle names, returns the list of Z-Anatomy mesh names
 * that should be highlighted in the 3D model.
 *
 * Handles the formats used in admin data:
 * - "Gluteus Maximus" → both sides; "Left Gluteus Maximus" / "Gluteus Maximus (left)" → one side
 * - "Hip - Back - Right Gluteus Medius", "Hand - Right - Extensor Digit Minimi" (side in any segment)
 * - "Back - Upper - Bilateral Rhomboid Major" → both sides
 * - "Biceps & Triceps", "Teres Major (Posterior) Pectoralis Minor (Anterior)" → union of the parts
 * - "Extensor Carpi Radialis Longus/Brevis", "Peroneus (Fibularis) Longus"
 */
function getZAnatomyMeshNames(muscleName) {
    let lower = muscleName.toLowerCase().trim();
    if (!lower)
        return [];
    // Region segments: "Hip - Back - Right Gluteus Medius". The separator is a dash with whitespace on
    // at least one side, so hyphenated words ("ilio-psoas", "t12-l5") stay intact.
    const segs = /\s-|-\s/.test(lower)
        ? lower.split(/\s*-\s+|\s+-\s*/).map((x) => x.trim()).filter(Boolean)
        : [lower];
    // Side may sit in any segment ("Hand - Right - Extensor Digit Minimi"); "bilateral" forces both sides.
    let side = null;
    let bilateral = false;
    const sideRe = /(^|[\s(])(left|right)(?=[\s)]|$)/;
    for (const seg of segs) {
        const m = seg.match(sideRe);
        if (m && !side)
            side = m[2];
        if (/\bbilateral\b/.test(seg))
            bilateral = true;
    }
    if (bilateral)
        side = null;
    const context = segs.length > 1 && CONTEXT_REGIONS.includes(segs[0].replace(/s$/, "")) ? segs[0].replace(/s$/, "") : null;
    let name = segs[segs.length - 1];
    // Alias spelled inside parentheses: "Peroneus (Fibularis) Longus".
    name = name.replace(/\s*\(fibularis\)\s*/g, " ");
    // Other parentheticals are qualifiers or separators: "(Anterior & Posterior)", "(Level T10)", "(Posterior)".
    name = name.replace(/\([^)]*\)/g, " & ");
    name = name.replace(/(^|[\s])(left|right)(?=[\s]|$)/g, " ").replace(/\bbilateral\b/g, " ");
    name = name.replace(/\s+/g, " ").trim();
    if (!name)
        return [];
    const parts = name
        .split(/\s*(?:&|,|\band\b)\s*/)
        .map((p) => p.trim())
        .filter(Boolean);
    const out = new Set();
    for (const part of parts) {
        // A plain part has one candidate; "a/b" parts contribute every reading that resolves.
        for (const candidate of expandSlash(part)) {
            for (const n of resolvePart(candidate, side, context))
                out.add(n);
        }
    }
    return Array.from(out);
}
function expandMapping(m) {
    const names = [];
    if (m.both) {
        for (const stem of m.both) {
            // Special case: "Diaphragm" has no .l/.r
            if (stem === "Diaphragm" || stem === "Linea alba" || stem === "Transverse arytenoid muscle") {
                names.push(stem);
            }
            else {
                names.push(`${stem}.l`);
                names.push(`${stem}.r`);
            }
        }
    }
    if (m.left) {
        for (const stem of m.left) {
            names.push(`${stem}.l`);
        }
    }
    if (m.right) {
        for (const stem of m.right) {
            names.push(`${stem}.r`);
        }
    }
    return names;
}
/**
 * Given a list of our muscle names, returns a deduplicated Set of all
 * Z-Anatomy mesh names that should be highlighted.
 */
function getHighlightMeshNames(muscles) {
    const result = new Set();
    for (const m of muscles) {
        for (const name of getZAnatomyMeshNames(m)) {
            result.add(name);
        }
    }
    return result;
}

window.hwMuscleMeshes = function (names) {
  return Array.from(getHighlightMeshNames((names || []).map(function (n) { return String(n || ""); })));
};
window.highlightMuscles = function (muscles) {
  if (typeof muscles === "string") { try { muscles = JSON.parse(muscles); } catch (e) { muscles = []; } }
  var colors = new Map();
  for (var muscle of (Array.isArray(muscles) ? muscles : [])) {
    var name = typeof muscle === "string" ? muscle : String(muscle && muscle.name || "");
    var color = typeof muscle === "string" ? "" : String(muscle && muscle.color || "");
    for (var mesh of getZAnatomyMeshNames(name)) {
      if (!colors.has(mesh)) colors.set(mesh, color);
    }
  }
  if (window.highlightMeshes) {
    window.highlightMeshes(Array.from(colors, function (entry) {
      return { name: entry[0], color: entry[1] };
    }));
  }
};
})();
