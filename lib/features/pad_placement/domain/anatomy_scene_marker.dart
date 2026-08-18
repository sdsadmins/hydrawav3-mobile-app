/// Adapts the app's marker maps to the shape `anatomy_scene.src.js` reads.
///
/// WHY AN ADAPTER RATHER THAN TEACHING THE VIEWER OUR FIELD NAMES.
/// `anatomy_scene.src.js` is a close port of the web `AnatomyScene.jsx`, and
/// every function in it — `refineLandmark`, `markerMuscleSearchTerms`,
/// `highlightSize`, `markerClusterKey`, `addSetArcs` — reads WEB field names.
/// Rewriting all of them to read ours is exactly where a close port drifts and
/// stops matching the reference. So the JS keeps the web's vocabulary and this
/// one pure `Map -> Map` function does the translation.
///
/// THE MAPPING THAT MATTERS MOST: `label` <-> `cue`.
/// Our `label` is `Pad.cue` — a written sentence for the practitioner. The
/// web's `label` is the MUSCLE NAME, and it is fed straight into the landmark
/// refinement's term matching. Get these backwards and a cue like
/// "...lumbar paraspinal - posterior" trips the low-back refinement branch while
/// the muscle resolver receives a sentence: pads that look plausible and are in
/// the wrong place, which is the worst failure mode available here.
///
/// Two producers feed this, and both must keep working:
///   * performance — `PadPlacementViewData.markers()`, which carries
///     `targetMuscles` / `plane` / `positionAlongMuscle` and a `zone` that is a
///     real curated landmark key.
///   * recovery — the untyped `markers` array straight off
///     `POST ai-padplacement/placement-session`, which has a curated `zone` and
///     no muscle list at all.
library;

enum MarkerSource {
  /// `PadPlacementViewData.markers()` — the performance pad map.
  performance,

  /// Raw server markers from the recovery placement session.
  recovery,
}

/// Converts [markers] (our shape) into the viewer's shape.
///
/// [setRoles] is `PadSet.role` per set index ('generator' / 'transfer' /
/// 'terminus'); the viewer puts it on the set-arc label. Performance only —
/// recovery has no such concept.
///
/// Unknown keys are passed through untouched, so a field added server-side
/// reaches the viewer without a change here.
List<Map<String, dynamic>> toAnatomySceneMarkers(
  List<Map<String, dynamic>> markers, {
  required MarkerSource source,
  List<String>? setRoles,
}) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < markers.length; i++) {
    final raw = markers[i];
    final sides = _sidesFor(raw, source: source);
    if (sides.length > 1) {
      for (final side in sides) {
        out.add(_adapt(raw, i, source, setRoles, sideOverride: side));
      }
      continue;
    }
    out.add(
      _adapt(raw, i, source, setRoles, sideOverride: sides.isEmpty ? null : sides.first),
    );
  }
  return out;
}

Map<String, dynamic> _adapt(
  Map<String, dynamic> raw,
  int index,
  MarkerSource source,
  List<String>? setRoles, {
  String? sideOverride,
}) {
  // Start from a copy so anything we don't know about survives the trip.
  final m = Map<String, dynamic>.of(raw);

  final role = (raw['role']?.toString().toLowerCase() == 'moon') ? 'moon' : 'sun';
  final setIndex = _asInt(raw['setIndex'] ?? raw['set_index']) ?? 0;
  final side = sideOverride ?? _sideOf(raw['side']);
  final muscles = _stringList(raw['targetMuscles'] ?? raw['muscles']);
  final cue = raw['label']?.toString() ?? raw['cue']?.toString() ?? '';

  m['role'] = role;
  m['setIndex'] = setIndex;

  if (side != null) {
    m['side'] = side;
    // Opt into the viewer's single-side muscle resolution. Without it a pad that
    // names a plain muscle lights up BOTH limbs and a one-sided chain reads as
    // bilateral.
    m['sideStrict'] = true;
  } else {
    m.remove('side');
    m.remove('sideStrict');
  }

  final sideZone = raw['zone']?.toString();
  if (side != null &&
      _isBilateralRequest(raw, source) &&
      sideZone != null &&
      sideZone.isNotEmpty) {
    m['zone'] = '$sideZone-$side';
  }

  // The written cue always lands on `cue`, never on `label` — see the note above.
  if (cue.isNotEmpty) m['cue'] = cue;

  if (source == MarkerSource.recovery) {
    // The server's `zone` IS a curated landmark key, and it is the only thing
    // positioning a recovery pad. Pass it through untouched — this is the path
    // recovery has always used and the one regression that must not happen.
    //
    // `label` also stays as the server sent it: it is a short anatomical
    // description ("Lumbar paraspinal"), which is what the refinement's term
    // matching wants, and it is what the previous viewer matched against.
    if (muscles.isNotEmpty) m['muscles'] = muscles;
    m.remove('targetMuscles');
    _applyExactPlacement(m, raw, muscles);
    m['__mobileIndex'] = index;

    // Bilateral recovery markers need a distinct zone per side so the viewer's
    // markerIdentity (which includes zone) differentiates them. If the server
    // provided a zone, append the side. If not (common case), create one.
    // Without this, bilateral pads with the same role on the same plane collide
    // as identical and the viewer's "first marker wins" mesh claiming produces
    // all one color. Web parity: buildRecoveryMarkers.js line 373.
    if (side != null && _isBilateralRequest(raw, source)) {
      final serverZone = raw['zone']?.toString();
      final padLabel = role == 'moon' ? 'moon' : 'sun';
      if (serverZone != null && serverZone.isNotEmpty) {
        // Server provided a zone — append side suffix to it (original behaviour).
        m['zone'] = '$serverZone-$side';
      } else {
        // No server zone — create one like the web app does.
        m['zone'] = 'recovery-$padLabel-$setIndex-$side';
      }
    }

    return m;
  }

  // ── performance ──────────────────────────────────────────────────────────
  //
  // Our `zone` is the curated landmark key from `resolveZone()`, optionally with
  // a `-left` / `-right` suffix appended by the bilateral path. The viewer wants
  // `zone` to be the per-pad identity (it keys clustering and highlight
  // identity), so the landmark key moves to `landmarkZone` and `zone` becomes
  // the same synthetic key the web builds.
  final baseZone = raw['zone']?.toString();
  final stripped = _stripSideSuffix(baseZone);
  final isBilateral = baseZone != null && stripped.suffix != null;

  if (stripped.key != null && stripped.key!.isNotEmpty) {
    m['landmarkZone'] = stripped.key;
  }
  m['zone'] = isBilateral
      ? 'perf-$role-$setIndex-${stripped.suffix}'
      : 'perf-$role-$setIndex';

  if (muscles.isNotEmpty) {
    m['muscles'] = muscles;
    // The muscle NAME is what the refinement and the mesh resolver want here.
    m['label'] = muscles.first;
    m['muscle'] = muscles.first;
  } else {
    // No muscle list: leave `label` empty rather than letting the sentence in
    // `cue` reach the term matcher.
    m.remove('label');
  }
  m.remove('targetMuscles');

  // Badge reads "Sun"/"Moon" rather than "S1"/"M1" — the web performance flow
  // sets this on every marker.
  m['padLabelStyle'] = 'word';

  // Drops our grey `setColor`: the viewer derives the badge/arc colour from
  // `setIndex` through the Okabe-Ito palette, and passing a second colour here
  // would fight it. `kAnatomySetColors` keeps the Flutter chrome in agreement.
  m.remove('setColor');

  final role0 = _roleForSet(setRoles, setIndex);
  if (role0 != null && role0.isNotEmpty) m['setRole'] = role0;

  _applyExactPlacement(m, raw, muscles);
  m['__mobileIndex'] = index;
  return m;
}

/// `plane` and `positionAlongMuscle` are what let the anchor tier put a pad on
/// the authored FACE of the body and slide it along the muscle. The viewer reads
/// them from `exactPlacement`, so mirror them there (the flat copies stay for
/// the bounding-box fallback tier).
void _applyExactPlacement(
  Map<String, dynamic> m,
  Map<String, dynamic> raw,
  List<String> muscles,
) {
  final existing = raw['exactPlacement'];
  final exact = existing is Map
      ? Map<String, dynamic>.from(existing)
      : <String, dynamic>{};

  final plane = raw['plane']?.toString();
  final position = raw['positionAlongMuscle']?.toString();

  if (muscles.isNotEmpty) exact.putIfAbsent('muscle', () => muscles.first);
  if (plane != null && plane.trim().isNotEmpty) {
    exact.putIfAbsent('plane', () => plane);
  }
  if (position != null && position.trim().isNotEmpty) {
    exact.putIfAbsent('musclePosition', () => position);
  }
  if (exact.isNotEmpty) m['exactPlacement'] = exact;
}

String? _roleForSet(List<String>? setRoles, int setIndex) {
  if (setRoles == null) return null;
  if (setIndex < 0 || setIndex >= setRoles.length) return null;
  return setRoles[setIndex];
}

({String? key, String? suffix}) _stripSideSuffix(String? zone) {
  if (zone == null || zone.isEmpty) return (key: null, suffix: null);
  for (final side in const ['left', 'right']) {
    final suffix = '-$side';
    if (zone.endsWith(suffix)) {
      return (
        key: zone.substring(0, zone.length - suffix.length),
        suffix: side,
      );
    }
  }
  return (key: zone, suffix: null);
}

String? _sideOf(Object? value) {
  final s = value?.toString().toLowerCase();
  if (s == 'left' || s == 'right') return s;
  return null;
}

List<String> _sidesFor(
  Map<String, dynamic> raw, {
  required MarkerSource source,
}) {
  final bool bilateral = source == MarkerSource.recovery &&
      (raw['render_both_sides'] == true ||
          const ['both', 'bilateral'].contains(
            raw['side']?.toString().toLowerCase()));
  final side = _sideOf(raw['side']);
  if (bilateral) {
    final base = side ?? 'right';
    final opposite = base == 'right' ? 'left' : 'right';
    return [base, opposite];
  }
  if (side != null) return [side];
  return const [];
}

bool _isBilateralRequest(Map<String, dynamic> raw, MarkerSource source) =>
    source == MarkerSource.recovery &&
    (raw['render_both_sides'] == true ||
        const ['both', 'bilateral'].contains(
          raw['side']?.toString().toLowerCase()));

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((e) => e?.toString() ?? '')
      .where((e) => e.trim().isNotEmpty)
      .toList();
}
