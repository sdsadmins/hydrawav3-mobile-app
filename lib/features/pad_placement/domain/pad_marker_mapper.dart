// Turns a performance-protocols `PadSetPayload` into the marker list the
// Z-Anatomy viewer already consumes (`window.renderPadPlacement`), plus the
// `{recommendation: {sets: […]}, markers: […]}` envelope the existing pad
// screens read — so there is exactly one data path into the 3D view.
//
// The payload gives us `landmark_anchor`, `target_muscles`, `plane`, `side` and
// `position_along_muscle`, but no `zone`. Resolution is three tiers:
//
//  1. zone key — the anchor normalises onto one of the calibrated landmarks in
//     `pad_placement.src.js` (exact key or a curated synonym).
//  2. muscle geometry — no zone, but `target_muscles` are present: the viewer
//     places the pad from the real mesh centroid, nudged by
//     `position_along_muscle` and pushed out along `plane`, then snapped to the
//     skin surface.
//  3. unmapped — neither resolves: NO pad is drawn and the written cue is badged
//     in the list. Drawing it at a default landmark (what the viewer used to do)
//     shows a wrong placement with full confidence.

import '../../performance_protocols/domain/performance_models.dart';

/// Set colours, as hex for the 3D badges. These are the ported "pad-set
/// neutrals" (`RefPalette.set1/2/3` in `core/theme/hw_tokens.dart`) — the same
/// three values the Flutter chrome uses, so a set reads identically in the list
/// and on the model. Change both or neither.
const List<String> kSetColors = ['#71838F', '#84936F', '#9A8B7A'];

String setColorFor(int setIndexZeroBased) =>
    kSetColors[setIndexZeroBased % kSetColors.length];

/// Every landmark key the viewer knows, with the body view it sits on.
/// Union of `LOCAL_PAD_LANDMARKS` and the shared `ANATOMY_LANDMARKS` zones in
/// `tool/kinetic_chain_viewer/pad_placement.src.js` — keep the two in step.
const Map<String, String> kPadZoneViews = {
  // trunk / spine
  'thoracolumbar': 'back',
  'low_back_l23': 'back',
  'serratus_posterior_inferior_t11_t12': 'back',
  'external_oblique': 'front',
  'iliac_fossa': 'front',
  'lat': 'side',
  'serratus': 'side',
  'serratus_anterior_rib7': 'side',
  // neck / upper back
  'occipital': 'back',
  'splenius_capitis_c2_c3': 'back',
  'c6_c7': 'back',
  'levator': 'back',
  'upper_trap': 'back',
  'mid_trap': 'back',
  'rhomboid': 'back',
  // shoulder
  'anterior_deltoid': 'front',
  'posterior_deltoid': 'back',
  'teres_superior': 'back',
  'teres_inferior': 'back',
  'infraspinatus_greater_tubercle': 'back',
  'pectoralis_minor_coracoid': 'front',
  // hip / glute
  'glute': 'back',
  'gluteus_maximus_upper_belly': 'back',
  'gluteus_maximus_tuberosity': 'back',
  'gluteus_medius_posterior_hip': 'back',
  'posterior_hip': 'back',
  'piriformis_posterior_hip': 'back',
  'posterior_ilium': 'back',
  'anterior_hip': 'front',
  // hamstring
  'hamstring_origin': 'back',
  'medial_hamstring_origin': 'back',
  'lateral_ischial_tuberosity': 'back',
  // knee / thigh
  'above_patella': 'front',
  'below_patella': 'front',
  'below_patella_left': 'front',
  'below_patella_right': 'front',
  'medial_knee_superior': 'front',
  'medial_knee_inferior': 'front',
  'lateral_knee_superior': 'front',
  'lateral_knee_inferior': 'front',
  'posterior_knee_above_fossa': 'back',
  'popliteus_posterior_knee': 'back',
  'rectus_femoris_quad_tendon': 'front',
  'vastus_medialis_vmo': 'front',
  'vastus_lateralis_vl': 'front',
  'sartorius_pes_anserine': 'front',
  // elbow / forearm
  'anterior_medial_elbow': 'side',
  'posterior_medial_elbow': 'side',
  'anterior_lateral_elbow': 'side',
  'posterior_lateral_elbow': 'side',
  'pronator_teres_medial_epicondyle': 'side',
  'triceps_olecranon': 'side',
  'anterior_distal_forearm': 'side',
  'posterior_distal_forearm': 'side',
  'extensor_carpi_ulnaris_forearm': 'side',
  // lower leg / foot
  'tibialis_anterior_tuberosity': 'front',
  'fibularis_longus_fibular_head': 'front',
  'medial_malleolus': 'front',
  'lateral_malleolus': 'front',
  'tibialis_posterior_medial_malleolus': 'front',
  'fibularis_longus_lateral_malleolus': 'front',
  'tibialis_anterior_medial_cuneiform': 'side',
  'plantar_foot': 'side',
  'flexor_digitorum_brevis_arch': 'side',
  'dorsal_foot': 'side',
};

/// Clinical phrasing → zone key. Longest phrase wins, so specific beats generic.
/// This table starts deliberately small; grow it from the viewer's
/// `[padPlacement] unmapped` console output rather than guessing.
const Map<String, String> _kZoneSynonyms = {
  'lumbar paraspinal': 'low_back_l23',
  'lumbar spine': 'low_back_l23',
  'low back': 'low_back_l23',
  'lower back': 'low_back_l23',
  'l2 l3': 'low_back_l23',
  'thoracolumbar junction': 'thoracolumbar',
  'latissimus dorsi': 'lat',
  'lats': 'lat',
  'oblique': 'external_oblique',
  'anterior iliac fossa': 'iliac_fossa',
  'hip crease': 'iliac_fossa',
  'asis': 'iliac_fossa',
  'serratus anterior': 'serratus_anterior_rib7',
  'base of skull': 'occipital',
  'suboccipital': 'occipital',
  'splenius capitis': 'splenius_capitis_c2_c3',
  'cervicothoracic junction': 'c6_c7',
  'base of neck': 'c6_c7',
  'levator scapulae': 'levator',
  'upper trapezius': 'upper_trap',
  'upper trap': 'upper_trap',
  'shoulder slope': 'upper_trap',
  'middle trapezius': 'mid_trap',
  'mid trap': 'mid_trap',
  'medial scapular border': 'rhomboid',
  'rhomboids': 'rhomboid',
  'front shoulder': 'anterior_deltoid',
  'back shoulder': 'posterior_deltoid',
  'greater tubercle': 'infraspinatus_greater_tubercle',
  'infraspinatus': 'infraspinatus_greater_tubercle',
  'rotator cuff': 'teres_superior',
  'coracoid': 'pectoralis_minor_coracoid',
  'pectoralis minor': 'pectoralis_minor_coracoid',
  'gluteus maximus': 'gluteus_maximus_upper_belly',
  'gluteal fold': 'hamstring_origin',
  'gluteus medius': 'gluteus_medius_posterior_hip',
  'piriformis': 'piriformis_posterior_hip',
  'posterior superior iliac spine': 'posterior_ilium',
  'psis': 'posterior_ilium',
  'greater trochanter': 'gluteus_medius_posterior_hip',
  'tensor fasciae latae': 'anterior_hip',
  'tfl': 'anterior_hip',
  'hip flexor': 'anterior_hip',
  'ischial tuberosity': 'hamstring_origin',
  'proximal hamstring': 'hamstring_origin',
  'hamstring origin': 'hamstring_origin',
  'medial hamstring': 'medial_hamstring_origin',
  'quad tendon': 'rectus_femoris_quad_tendon',
  'rectus femoris': 'rectus_femoris_quad_tendon',
  'vastus medialis': 'vastus_medialis_vmo',
  'vmo': 'vastus_medialis_vmo',
  'vastus lateralis': 'vastus_lateralis_vl',
  'pes anserine': 'sartorius_pes_anserine',
  'sartorius': 'sartorius_pes_anserine',
  'popliteal': 'popliteus_posterior_knee',
  'popliteus': 'popliteus_posterior_knee',
  'medial epicondyle': 'pronator_teres_medial_epicondyle',
  'pronator teres': 'pronator_teres_medial_epicondyle',
  'lateral epicondyle': 'anterior_lateral_elbow',
  'common extensor origin': 'anterior_lateral_elbow',
  'olecranon': 'triceps_olecranon',
  'triceps insertion': 'triceps_olecranon',
  'extensor carpi ulnaris': 'extensor_carpi_ulnaris_forearm',
  'distal forearm': 'anterior_distal_forearm',
  'tibial tuberosity': 'tibialis_anterior_tuberosity',
  'tibialis anterior': 'tibialis_anterior_tuberosity',
  'fibular head': 'fibularis_longus_fibular_head',
  'peroneal': 'fibularis_longus_lateral_malleolus',
  'medial malleolus': 'medial_malleolus',
  'lateral malleolus': 'lateral_malleolus',
  'tibialis posterior': 'tibialis_posterior_medial_malleolus',
  'medial cuneiform': 'tibialis_anterior_medial_cuneiform',
  'plantar fascia': 'flexor_digitorum_brevis_arch',
  'plantar arch': 'flexor_digitorum_brevis_arch',
  'plantar surface': 'plantar_foot',
  'dorsum of the foot': 'dorsal_foot',
  'midfoot': 'dorsal_foot',
  'above the kneecap': 'above_patella',
  'below the kneecap': 'below_patella',
  'patellar tendon': 'below_patella',
};

/// How far along the muscle the pad sits, as a signed fraction of the muscle's
/// long axis (+1 = proximal end, -1 = distal end). Consumed by the viewer's
/// tier-2 geometry path.
double? muscleOffsetFor(String positionAlongMuscle) {
  final s = positionAlongMuscle.toLowerCase();
  if (s.isEmpty) return null;
  if (s.contains('proximal') || s.contains('origin') || s.contains('upper')) {
    return 0.35;
  }
  if (s.contains('distal') ||
      s.contains('insertion') ||
      s.contains('lower') ||
      s.contains('tendon')) {
    return -0.35;
  }
  if (s.contains('mid') || s.contains('belly') || s.contains('centre')) {
    return 0.0;
  }
  return null;
}

/// One pad resolved for rendering.
class ResolvedPad {
  final Pad pad;

  /// 'sun' or 'moon'.
  final String role;

  /// 0-based, as the viewer's `setIndex` (it adds 1 for the S1/M1 badge).
  final int setIndex;
  final String setTitle;

  /// Tier 1 result — null when the anchor didn't resolve to a landmark.
  final String? zone;

  /// 'left' / 'right' / null.
  final String? side;

  const ResolvedPad({
    required this.pad,
    required this.role,
    required this.setIndex,
    required this.setTitle,
    this.zone,
    this.side,
  });

  /// Tier 2 is possible when the corpus named muscles we can look up in the GLB.
  bool get hasMuscleFallback => pad.targetMuscles.isNotEmpty;

  /// Tier 3 — nothing to place from. The list shows the written cue instead.
  bool get isUnmapped => zone == null && !hasMuscleFallback;

  /// The body view this pad sits on, for the "rotate to see" hint and the
  /// focus-chip auto-rotate.
  String get view {
    final z = zone;
    if (z != null && kPadZoneViews.containsKey(z)) return kPadZoneViews[z]!;
    final p = pad.plane.toLowerCase();
    if (p.contains('posterior') || p.contains('dorsal')) return 'back';
    if (p.contains('lateral') || p.contains('medial')) return 'side';
    if (p.contains('anterior') || p.contains('ventral')) return 'front';
    return 'front';
  }

  /// The marker the viewer bridge expects, extended with the tier-2 inputs.
  Map<String, dynamic> toMarker() => {
        'role': role,
        if (zone != null) 'zone': zone,
        if (side != null) 'side': side,
        'label': pad.cue,
        'setIndex': setIndex,
        'setTitle': setTitle,
        'setColor': setColorFor(setIndex),
        if (pad.targetMuscles.isNotEmpty) 'targetMuscles': pad.targetMuscles,
        if (pad.plane.trim().isNotEmpty) 'plane': pad.plane,
        if (muscleOffsetFor(pad.positionAlongMuscle) != null)
          'muscleOffset': muscleOffsetFor(pad.positionAlongMuscle),
        if (pad.positionAlongMuscle.trim().isNotEmpty)
          'positionAlongMuscle': pad.positionAlongMuscle,
      };
}

/// A payload prepared for the pad-map screen: the sets in `set_index` order and
/// every pad resolved to a tier.
class PadPlacementViewData {
  final PadSetPayload payload;
  final List<ResolvedPad> pads;

  const PadPlacementViewData({required this.payload, required this.pads});

  /// APPLIED sets only.
  ///
  /// A recovery payload also carries the sets the engine authored but held back
  /// this session (`chain.conditional.withheld_sets`). Those have no pads by
  /// definition, so letting them through here would shift every positional
  /// `setIndex` — which is what the markers, the set colours and the focus chips
  /// all key off — and put a pad-less entry in the legend. The pad map lists
  /// them separately, from `payload.withheldSets`.
  factory PadPlacementViewData.from(PadSetPayload payload) {
    final applied = payload.appliedSets;
    final pads = <ResolvedPad>[];
    for (final set in applied) {
      // The set's OWN index, not its position in this (possibly filtered,
      // e.g. sets 2-3 withheld/deferred) list — see
      // `PadSetPayload.markerIndexOf`. Using loop position here instead used
      // to relabel "Set 4" as "Set 2" whenever an earlier set was filtered
      // out, since the SAME number drives the marker's arc label, its
      // palette colour, and the viewer's set-focus — all wrong together, not
      // just the label.
      final markerSetIndex = payload.markerIndexOf(set);
      for (final entry in [('sun', set.sun), ('moon', set.moon)]) {
        final pad = entry.$2;
        if (pad == null) continue;
        pads.add(ResolvedPad(
          pad: pad,
          role: entry.$1,
          setIndex: markerSetIndex,
          setTitle: set.title,
          zone: resolveZone(pad),
          side: pad.sideKey ?? _sideFromPlane(pad.plane),
        ));
      }
    }
    return PadPlacementViewData(payload: payload, pads: pads);
  }

  List<PadSet> get sets => payload.appliedSets;

  /// Pads for one set, or all of them when [setIndex] is null (the reference's
  /// "All areas" chip).
  List<ResolvedPad> padsFor(int? setIndex) => setIndex == null
      ? pads
      : pads.where((p) => p.setIndex == setIndex).toList();

  /// Markers to hand to `window.renderPadPlacement`. Tier-3 pads are omitted on
  /// purpose — better a missing disc than a confident wrong one.
  ///
  /// [mirrored] flips the whole chain to the opposite side. [bilateral] draws it on BOTH sides at
  /// once — and because that already shows both, mirroring on top of it would be a no-op, so it is
  /// IGNORED rather than half-applied (the web reached the same conclusion in its Jul 25 review).
  ///
  /// Under [bilateral] each pad yields TWO markers whose `zone` keys carry the side; without that the
  /// pair collapses into one identity and only one of them renders.
  List<Map<String, dynamic>> markers({
    int? focusSetIndex,
    bool mirrored = false,
    bool bilateral = false,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final pad in padsFor(focusSetIndex)) {
      if (pad.isUnmapped) continue;
      final base = _effectiveSide(pad, bilateral ? false : mirrored);
      final sides = bilateral
          ? <String>[base, base == 'right' ? 'left' : 'right']
          : <String>[base];
      for (final side in sides) {
        final marker = Map<String, dynamic>.of(pad.toMarker());
        marker['side'] = side;
        // Opt into the viewer's geometry-backed single-side highlight: a performance pad names a
        // plain muscle and carries its side HERE, so without this flag both limbs light up and a
        // one-sided chain reads as bilateral.
        marker['sideStrict'] = true;
        if (bilateral) {
          marker['zone'] = '${marker['zone'] ?? 'perf'}-$side';
          marker['label'] = '${marker['label'] ?? ''} — $side side (bilateral)'.trim();
        }
        out.add(marker);
      }
    }
    return out;
  }

  /// Ported verbatim from the web's `effectiveSide`: an unsided pad defaults to RIGHT, and mirroring
  /// swaps whichever side it ended up on.
  static String _effectiveSide(ResolvedPad pad, bool mirrored) {
    var side = pad.pad.sideKey ?? 'right';
    if (side != 'left' && side != 'right') side = 'right';
    if (mirrored) side = side == 'right' ? 'left' : 'right';
    return side;
  }

  ResolvedPad? padOf(int setIndex, String role) {
    for (final p in pads) {
      if (p.setIndex == setIndex && p.role == role) return p;
    }
    return null;
  }

  /// The body view a focused set should open on. Clamped to front/back: the
  /// stage only flips between those two (as the UI spec's rotate button does),
  /// and the viewer's `setView` silently falls back to front for anything else —
  /// which would leave the view pill disagreeing with the camera.
  String viewFor(int? focusSetIndex) {
    final list = padsFor(focusSetIndex);
    for (final pad in list) {
      if (pad.view == 'front' || pad.view == 'back') return pad.view;
    }
    return 'front';
  }

  bool get hasUnmapped => pads.any((p) => p.isUnmapped);

  /// The `{recommendation, markers}` envelope the existing pad screens read, so
  /// the recovery viewer and this one stay interchangeable.
  Map<String, dynamic> toViewerPayload({int? focusSetIndex}) => {
        'recommendation': {
          'title': payload.chain?.name ?? 'Performance Placement',
          'summary': payload.contextLine,
          'sets': [
            for (final set in sets)
              {
                'title': set.title,
                'setting': set.role,
                if (set.sun != null) 'sun': {'label': set.sun!.cue},
                if (set.moon != null) 'moon': {'label': set.moon!.cue},
              }
          ],
        },
        'markers': markers(focusSetIndex: focusSetIndex),
      };
}

/// Tier 1: `landmark_anchor` (falling back to the target muscle text) → a
/// calibrated zone key. Returns null when nothing matches — the caller then
/// drops to tier 2 or 3.
String? resolveZone(Pad pad) {
  for (final candidate in [
    pad.landmarkAnchor,
    pad.padLabel,
    ...pad.targetMuscles,
  ]) {
    final hit = _zoneFromText(candidate);
    if (hit != null) return hit;
  }
  return null;
}

String? _zoneFromText(String text) {
  if (text.trim().isEmpty) return null;

  // Exact key, e.g. the corpus already speaks zone keys.
  final key = _snake(text);
  if (kPadZoneViews.containsKey(key)) return key;

  // Synonyms, longest phrase first so "medial hamstring" beats "hamstring".
  final spaced = _spaced(text);
  final phrases = _kZoneSynonyms.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final phrase in phrases) {
    if (spaced.contains(phrase)) return _kZoneSynonyms[phrase];
  }

  // A zone key mentioned inside a longer sentence ("place over the upper_trap").
  // Whole-word only: a substring test would read "lateral" as the `lat` zone and
  // put a shoulder pad on the ribcage.
  for (final zone in kPadZoneViews.keys) {
    if (spaced.contains(' ${zone.replaceAll('_', ' ')} ')) return zone;
  }
  return null;
}

/// "L2-L3 lumbar paraspinal" → "l2_l3_lumbar_paraspinal"
String _snake(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Same normalisation but space-separated, for phrase matching.
String _spaced(String s) => ' ${_snake(s).replaceAll('_', ' ')} ';

/// Some anchors carry the side only in the plane text ("left lateral").
String? _sideFromPlane(String plane) {
  final p = plane.toLowerCase();
  if (p.contains('left')) return 'left';
  if (p.contains('right')) return 'right';
  return null;
}
