import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/pad_placement/domain/anatomy_scene_marker.dart';

/// A marker exactly as `PadPlacementViewData.markers()` emits it.
Map<String, dynamic> perfMarker({
  String zone = 'hamstring_origin',
  String role = 'sun',
  String side = 'right',
  int setIndex = 0,
  List<String> targetMuscles = const ['Biceps femoris', 'Semitendinosus'],
}) =>
    {
      'role': role,
      'zone': zone,
      'side': side,
      'sideStrict': true,
      'label': 'Upper hamstring at the gluteal fold - posterior - proximal',
      'setIndex': setIndex,
      'setTitle': 'Posterior chain',
      'setColor': '#71838F',
      if (targetMuscles.isNotEmpty) 'targetMuscles': targetMuscles,
      'plane': 'posterior',
      'muscleOffset': 0.35,
      'positionAlongMuscle': 'proximal',
    };

/// A marker exactly as the recovery placement-session response emits it —
/// untyped, no muscle list.
Map<String, dynamic> recoveryMarker() => {
      'role': 'moon',
      'zone': 'low_back_l23',
      'side': 'left',
      'label': 'Lumbar paraspinal',
      'surface': 'back',
      'setIndex': 0,
      'setTitle': 'Set 1',
      'setting': 'Normal',
    };

void main() {
  group('performance markers', () {
    test('muscle name becomes label; the written cue moves to cue', () {
      // The single most important assertion in this file. Our `label` is a
      // sentence for the practitioner; the viewer's `label` feeds landmark
      // refinement and mesh resolution and must be the muscle name.
      final m = toAnatomySceneMarkers(
        [perfMarker()],
        source: MarkerSource.performance,
      ).single;

      expect(m['label'], 'Biceps femoris');
      expect(m['muscle'], 'Biceps femoris');
      expect(
        m['cue'],
        'Upper hamstring at the gluteal fold - posterior - proximal',
      );
    });

    test('targetMuscles becomes muscles and the old key is dropped', () {
      final m = toAnatomySceneMarkers(
        [perfMarker()],
        source: MarkerSource.performance,
      ).single;

      expect(m['muscles'], ['Biceps femoris', 'Semitendinosus']);
      expect(m.containsKey('targetMuscles'), isFalse);
    });

    test('zone becomes the synthetic per-pad key; the landmark key is kept', () {
      final m = toAnatomySceneMarkers(
        [perfMarker(setIndex: 2, role: 'moon')],
        source: MarkerSource.performance,
      ).single;

      expect(m['zone'], 'perf-moon-2');
      expect(m['landmarkZone'], 'hamstring_origin');
    });

    test('a bilateral zone suffix survives onto the synthetic key', () {
      // `markers(bilateral: true)` emits `<landmarkKey>-<side>`. The side has to
      // reach the synthetic key or the pair collapses to one identity and only
      // one of the two renders.
      final m = toAnatomySceneMarkers(
        [perfMarker(zone: 'hamstring_origin-left', side: 'left')],
        source: MarkerSource.performance,
      ).single;

      expect(m['zone'], 'perf-sun-0-left');
      expect(m['landmarkZone'], 'hamstring_origin');
    });

    test('padLabelStyle is always word and the grey setColor is dropped', () {
      final m = toAnatomySceneMarkers(
        [perfMarker()],
        source: MarkerSource.performance,
      ).single;

      expect(m['padLabelStyle'], 'word');
      expect(m.containsKey('setColor'), isFalse);
    });

    test('plane and positionAlongMuscle mirror into exactPlacement', () {
      final m = toAnatomySceneMarkers(
        [perfMarker()],
        source: MarkerSource.performance,
      ).single;

      final exact = m['exactPlacement'] as Map<String, dynamic>;
      expect(exact['plane'], 'posterior');
      expect(exact['musclePosition'], 'proximal');
      expect(exact['muscle'], 'Biceps femoris');
      // The flat copies stay for the bounding-box fallback tier.
      expect(m['muscleOffset'], 0.35);
    });

    test('setRole is threaded from the set list by index', () {
      final out = toAnatomySceneMarkers(
        [perfMarker(setIndex: 0), perfMarker(setIndex: 2)],
        source: MarkerSource.performance,
        setRoles: const ['generator', 'transfer', 'terminus'],
      );

      expect(out[0]['setRole'], 'generator');
      expect(out[1]['setRole'], 'terminus');
    });

    test('an out-of-range or absent set role is simply omitted', () {
      final withShortList = toAnatomySceneMarkers(
        [perfMarker(setIndex: 5)],
        source: MarkerSource.performance,
        setRoles: const ['generator'],
      ).single;
      final withNoList = toAnatomySceneMarkers(
        [perfMarker()],
        source: MarkerSource.performance,
      ).single;

      expect(withShortList.containsKey('setRole'), isFalse);
      expect(withNoList.containsKey('setRole'), isFalse);
    });

    test('no muscle list leaves label unset rather than passing the cue', () {
      // Letting the sentence through as `label` is the failure mode this guards.
      final m = toAnatomySceneMarkers(
        [perfMarker(targetMuscles: const [])],
        source: MarkerSource.performance,
      ).single;

      expect(m.containsKey('label'), isFalse);
      expect(m['cue'], isNotEmpty);
    });
  });

  group('recovery markers', () {
    test('the curated zone passes through verbatim', () {
      // Recovery is positioned entirely by its zone. Rewriting it would move
      // every recovery pad — the one regression that must not happen.
      final m = toAnatomySceneMarkers(
        [recoveryMarker()],
        source: MarkerSource.recovery,
      ).single;

      expect(m['zone'], 'low_back_l23');
      expect(m.containsKey('landmarkZone'), isFalse);
    });

    test('the server label is preserved and also copied to cue', () {
      final m = toAnatomySceneMarkers(
        [recoveryMarker()],
        source: MarkerSource.recovery,
      ).single;

      // Short anatomical text, which is what landmark refinement matches on.
      expect(m['label'], 'Lumbar paraspinal');
      expect(m['cue'], 'Lumbar paraspinal');
    });

    test('no muscles key is invented when the server sent none', () {
      final m = toAnatomySceneMarkers(
        [recoveryMarker()],
        source: MarkerSource.recovery,
      ).single;

      expect(m.containsKey('muscles'), isFalse);
    });

    test('padLabelStyle is not forced, so badges stay compact S1/M1', () {
      final m = toAnatomySceneMarkers(
        [recoveryMarker()],
        source: MarkerSource.recovery,
      ).single;

      expect(m.containsKey('padLabelStyle'), isFalse);
    });
  });

  group('shared behaviour', () {
    test('sideStrict is set with a side and removed without one', () {
      final withSide = toAnatomySceneMarkers(
        [perfMarker(side: 'left')],
        source: MarkerSource.performance,
      ).single;
      final noSide = toAnatomySceneMarkers(
        [
          {
            'role': 'sun',
            'zone': 'occipital',
            'label': 'Occipital',
            'setIndex': 0,
          }
        ],
        source: MarkerSource.recovery,
      ).single;

      expect(withSide['side'], 'left');
      expect(withSide['sideStrict'], isTrue);
      expect(noSide.containsKey('side'), isFalse);
      expect(noSide.containsKey('sideStrict'), isFalse);
    });

    test('a bogus side value is dropped rather than passed on', () {
      final m = toAnatomySceneMarkers(
        [
          {...perfMarker(), 'side': 'bilateral'},
        ],
        source: MarkerSource.performance,
      ).single;

      expect(m.containsKey('side'), isFalse);
      expect(m.containsKey('sideStrict'), isFalse);
    });

    test('role is normalised and setIndex coerced from a string', () {
      final m = toAnatomySceneMarkers(
        [
          {...perfMarker(), 'role': 'MOON', 'setIndex': '3'},
        ],
        source: MarkerSource.performance,
      ).single;

      expect(m['role'], 'moon');
      expect(m['setIndex'], 3);
    });

    test('unknown keys pass through untouched', () {
      final m = toAnatomySceneMarkers(
        [
          {...perfMarker(), 'somethingNew': 'from the server'},
        ],
        source: MarkerSource.performance,
      ).single;

      expect(m['somethingNew'], 'from the server');
    });

    test('__mobileIndex maps a picked marker back to the original list', () {
      final out = toAnatomySceneMarkers(
        [perfMarker(), perfMarker(role: 'moon'), perfMarker(setIndex: 1)],
        source: MarkerSource.performance,
      );

      expect(out.map((m) => m['__mobileIndex']), [0, 1, 2]);
    });

    test('the input maps are not mutated', () {
      final input = perfMarker();
      final before = Map<String, dynamic>.of(input);

      toAnatomySceneMarkers([input], source: MarkerSource.performance);

      expect(input, before);
    });
  });
}
