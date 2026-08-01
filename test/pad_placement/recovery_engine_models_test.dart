import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/pad_placement/domain/pad_marker_mapper.dart';
import 'package:hydrawav3/features/pad_placement/domain/recovery_engine_models.dart';

/// A real `recovery-engine-v3/resolve` response, trimmed to the fields the
/// client reads. Captured verbatim from the deployed backend so the mapping is
/// tested against what the engine actually sends, not against a shape invented
/// here — the two drifting apart is the whole failure this file guards.
Map<String, dynamic> resolveResponse({
  bool referOut = false,
  List<Map<String, dynamic>>? sets,
}) =>
    {
      'generation': 'v2',
      'pathway': 'discomfort',
      'safety': {'refer_out': false, 'reason': null},
      'point': {
        'recovery_id': 'rec-low-back-muscular-tightness-v1',
        'goal_pathway': 'discomfort',
        'region': 'low-back',
        'side': 'bilateral',
        'acuity': 'chronic',
      },
      'assessment': {
        'movement_test': 'direct_select',
        'finding': 'Tightness and restriction through the low-back',
      },
      'thermal': {
        'mode': 'hot_pack',
        'rationale': 'Warmth relaxes the tissue and supports circulation.',
      },
      'clinical_intent': {
        'mechanism_rationale':
            'Warmth relaxes the low-back tissue directly for a broad, '
                'superficial tightness.',
        'expected_sensation': 'Gentle warmth and a soft contrast.',
        'reassessment_marker': 'Re-check the area for easier movement.',
        'wellness_claim_wording': 'This placement may support tightness and '
            'restriction through the low-back.',
      },
      'pointSafety': {
        'refer_out': referOut,
        'refer_out_reason': referOut ? 'Please get this looked at first.' : null,
        'cautions_relative': referOut ? <String>[] : ['Avoid over broken skin'],
      },
      'sets': sets ??
          [
            {
              'set_index': 1,
              'pad_geometry': 'side_by_side',
              'set_role': 'primary_site',
              'note': '',
              'pads': [
                {
                  'pad_label': 'sun',
                  'side': 'right',
                  'plane': 'posterior',
                  'aspect': 'posterior',
                  'body_side': 'right',
                  'position': 'mid',
                  'landmark_anchor': 'Lumbar paraspinal, right',
                  'target_muscles': [
                    'Iliocostalis lumborum muscle',
                    'Multifidus lumborum muscle',
                  ],
                  'proxy_for': null,
                },
                {
                  'pad_label': 'moon',
                  'side': 'left',
                  'plane': 'posterior',
                  'aspect': 'posterior',
                  'body_side': 'left',
                  'position': 'mid',
                  'landmark_anchor': 'Lumbar paraspinal, left',
                  'target_muscles': [
                    'Iliocostalis lumborum muscle',
                    'Multifidus lumborum muscle',
                  ],
                  'proxy_for': null,
                },
              ],
            },
          ],
    };

void main() {
  group('RecoveryPlacement', () {
    test('maps a resolve into the pad-set payload the pad map renders', () {
      final p = RecoveryPlacement.fromJson(resolveResponse(),
          regionLabel: 'Lower Back');

      expect(p.recoveryId, 'rec-low-back-muscular-tightness-v1');
      expect(p.region, 'low-back');
      expect(p.pathway, 'discomfort');
      expect(p.generation, 'v2');
      expect(p.hasPads, isTrue);
      expect(p.referOut, isFalse);

      // The payload is what PlacementCard and PadMapScreen consume, so the
      // refusal flag they branch on has to be false for a real placement.
      expect(p.payload.isRefusal, isFalse);
      expect(p.payload.sets, hasLength(1));
      expect(p.payload.discipline, 'recovery');
      expect(p.payload.displayName, 'Lower Back');
      expect(p.payload.contextLine, 'Lower Back · Discomfort');
      expect(p.payload.chain!.name,
          'Tightness and restriction through the low-back');
    });

    test('pad fields survive the rename the two corpora disagree on', () {
      final p = RecoveryPlacement.fromJson(resolveResponse());
      final set = p.payload.sets.single;

      // `position` is performance's `position_along_muscle`. Without the rename
      // the marker carries no muscleOffset and the pad sits at the muscle's
      // midpoint regardless of what was authored.
      expect(set.sun!.positionAlongMuscle, 'mid');
      expect(set.moon!.positionAlongMuscle, 'mid');

      expect(set.sun!.side, 'right');
      expect(set.moon!.side, 'left');
      expect(set.sun!.plane, 'posterior');
      expect(set.sun!.landmarkAnchor, 'Lumbar paraspinal, right');
      expect(set.sun!.targetMuscles, contains('Multifidus lumborum muscle'));
      expect(set.sun!.proxyFor, isNull);

      // `primary_site` reaches the pad map's role line as words.
      expect(set.role, 'primary site');
    });

    test('a v3 pad, which carries aspect and body_side and no plane/side', () {
      final json = resolveResponse(sets: [
        {
          'set_index': 2,
          'set_role': 'referral_link',
          'note': 'Runs alongside the primary set this session.',
          'pads': [
            {
              'pad_label': 'sun',
              'body_side': 'left',
              'aspect': 'posterior',
              'position': 'proximal',
              'landmark_anchor': 'Gluteal fold, left',
              'target_muscles': ['Gluteus maximus muscle'],
              'proxy_for': null,
            },
          ],
        },
      ]);
      final set = RecoveryPlacement.fromJson(json).payload.sets.single;

      expect(set.sun!.side, 'left');
      expect(set.sun!.plane, 'posterior');
      expect(set.sun!.positionAlongMuscle, 'proximal');
      expect(set.setIndex, 2);
      expect(set.placementLabel, 'Runs alongside the primary set this session.');
    });

    test('the pads resolve to drawable markers, not to the unmapped tier', () {
      final p = RecoveryPlacement.fromJson(resolveResponse());
      final view = PadPlacementViewData.from(p.payload);

      expect(view.pads, hasLength(2));
      expect(view.hasUnmapped, isFalse,
          reason: '"Lumbar paraspinal" is a calibrated landmark; if this fails '
              'the pads render as written cues with no marker on the model');
      expect(view.pads.first.zone, 'low_back_l23');
      expect(view.viewFor(null), 'back');

      final markers = view.markers();
      expect(markers, hasLength(2));
      expect(markers.map((m) => m['side']), containsAll(['right', 'left']));
      expect(markers.first['muscleOffset'], 0.0);
    });

    test('a refer-out carries the message and withholds the pads', () {
      final p = RecoveryPlacement.fromJson(
        resolveResponse(referOut: true, sets: const []),
      );

      expect(p.referOut, isTrue);
      expect(p.hasPads, isFalse);
      expect(p.payload.isRefusal, isTrue);
      expect(p.emptyReason, 'Please get this looked at first.');
    });

    test('no authored point is not a refer-out, and says so differently', () {
      final json = resolveResponse(sets: const [])
        ..['point'] = <String, dynamic>{}
        ..['assessment'] = <String, dynamic>{};
      final p = RecoveryPlacement.fromJson(json);

      expect(p.referOut, isFalse);
      expect(p.hasPads, isFalse);
      expect(p.emptyReason, contains('no authored placement'));
    });
  });

  group('RecoveryGeneration', () {
    test('reads the two generations the client knows', () {
      expect(RecoveryGeneration.readFrom({'generation': 'v3'}),
          same(RecoveryGeneration.v3));
      expect(RecoveryGeneration.readFrom({'generation': 'V2 '}),
          same(RecoveryGeneration.v2));
    });

    test('anything else is null — "could not find out" is not "it is v2"', () {
      // The web's own bug: a default that is right most of the time is
      // indistinguishable from a decision until the day it is wrong.
      for (final verdict in [null, {}, {'generation': 'v4'}, 'v3', 42]) {
        expect(RecoveryGeneration.readFrom(verdict), isNull,
            reason: 'verdict $verdict must not resolve to a generation');
      }
    });

    test('each generation carries its own whole endpoint set', () {
      expect(RecoveryGeneration.v3.catalogPath, contains('-v3/intake'));
      expect(RecoveryGeneration.v3.resolvePath, contains('-v3/resolve'));
      expect(RecoveryGeneration.v2.catalogPath, endsWith('recovery-engine/catalog'));
      expect(RecoveryGeneration.v2.resolvePath, endsWith('recovery-engine/resolve'));
      // Never composed from two — the paths must not share a generation.
      expect(RecoveryGeneration.v2.screenPath,
          isNot(RecoveryGeneration.v3.screenPath));
    });
  });

  group('RecoverySafetyScreen', () {
    final screen = RecoverySafetyScreen.fromJson({
      'questions': [
        {
          'key': 'recent_injury_or_impact',
          'question': 'Any recent significant injury or impact?',
          'scope': 'universal',
          'gate': 'refer_out',
        },
        {
          'key': 'pregnancy_trunk_placement',
          'question': 'Pregnancy, for any trunk placement?',
          'scope': 'trunk',
          'gate': 'refer_out',
        },
      ],
      'disclaimer': 'Authored wellness line.',
    });

    test('every authored flag is answered no, from the payload\'s own keys', () {
      expect(screen.allFlagsNo, {
        'recent_injury_or_impact': false,
        'pregnancy_trunk_placement': false,
      });
    });

    test('an empty screen sends no map — "not asked" is not "answered no"', () {
      expect(const RecoverySafetyScreen().allFlagsNo, isEmpty);
    });

    test('the authored disclaimer wins, and there is always one', () {
      expect(screen.disclaimerOrFallback, 'Authored wellness line.');
      expect(const RecoverySafetyScreen().disclaimerOrFallback,
          RecoverySafetyScreen.fallbackDisclaimer);
    });
  });

  group('RecoveryGoal', () {
    test('only discomfort runs a test and offers a referral', () {
      expect(RecoveryGoal.discomfort.asksMovementTest, isTrue);
      expect(RecoveryGoal.discomfort.asksReferral, isTrue);
      for (final g in [
        RecoveryGoal.rangeOfMotion,
        RecoveryGoal.performanceRecovery,
        RecoveryGoal.lymphatic,
      ]) {
        expect(g.asksMovementTest, isFalse);
        expect(g.asksReferral, isFalse);
      }
    });

    test('lymphatic is the one pathway with no side question', () {
      expect(RecoveryGoal.lymphatic.asksSide, isFalse);
      expect(RecoveryGoal.discomfort.asksSide, isTrue);
    });
  });

  group('RecoveryIntakeCatalog (v2 catalog shape)', () {
    // The v2 catalogue, as `GET recovery-engine/catalog` actually returns it.
    final v2 = {
      'pathways': [
        {
          'goal_pathway': 'discomfort',
          'regions': [
            {
              'region': 'low-back',
              'points': 10,
              'hasMovementTest': true,
              'movementTests': ['Bilateral squat', 'Bilateral squat (gentle)'],
              'referrals': ['glute', 'hamstring'],
              'sides': ['right', 'bilateral'],
            },
            {
              'region': 'upper-back',
              'points': 8,
              'hasMovementTest': false,
              'movementTests': [],
              'referrals': [],
              'sides': ['bilateral'],
            },
          ],
        },
        {
          'goal_pathway': 'range_of_motion',
          'regions': [
            {
              'region': 'low-back',
              'points': 3,
              'hasMovementTest': false,
              'movementTests': [],
              'referrals': [],
              'sides': ['bilateral'],
            },
          ],
        },
      ],
      'corpus': 114,
    };

    test('normalises onto the same region model the v3 intake produces', () {
      final catalog = RecoveryIntakeCatalog.fromV2Json(v2);
      final lowBack = catalog.byId('low-back')!;

      // No display name in the payload, so the key is humanised and nothing
      // else is invented.
      expect(lowBack.label, 'Low back');
      expect(lowBack.movementTests.map((t) => t.test),
          ['Bilateral squat', 'Bilateral squat (gentle)']);
      expect(lowBack.movementTests.first.reveals, isEmpty);
      expect(lowBack.referralMenu, ['glute', 'hamstring']);
      expect(lowBack.aspectOffered, isFalse);
    });

    test('hasMovementTest false means no tests, whatever the list says', () {
      final catalog = RecoveryIntakeCatalog.fromV2Json(v2);
      expect(catalog.byId('upper-back')!.movementTests, isEmpty);
    });

    test('points per goal are summed over the pathway\'s regions', () {
      final catalog = RecoveryIntakeCatalog.fromV2Json(v2);
      expect(catalog.pointsFor('discomfort'), 18);
      expect(catalog.pointsFor('range_of_motion'), 3);
      expect(catalog.pointsFor('lymphatic_activation'), 0);
    });

    test('a region serving two pathways is listed once, with both goals', () {
      final catalog = RecoveryIntakeCatalog.fromV2Json(v2);
      expect(catalog.regions.where((r) => r.region == 'low-back'), hasLength(1));
      expect(catalog.byId('low-back')!.goalPathways,
          containsAll(['discomfort', 'range_of_motion']));
      // Scoping still holds: range_of_motion offers only what it authored.
      expect(catalog.regionsFor('range_of_motion').map((r) => r.region),
          ['low-back']);
    });
  });

  group('RecoveryIntakeCatalog', () {
    // The catalogue as the newer backend sends it: per-pathway region lists on
    // top of the whole-corpus one.
    final json = {
      'version': '3.1',
      'regions': [
        {
          'known': true,
          'region': 'low-back',
          'display_name': 'Lower Back',
          'movement_tests': [
            {'test': 'Forward bend (flexion)', 'reveals': 'posterior chain'},
          ],
          'referral_menu': ['glute', 'hamstring'],
          'sides': ['right', 'left', 'both'],
          'aspects': ['posterior'],
          'aspect_offered': false,
          'goal_pathways': ['discomfort'],
        },
        {
          'known': true,
          'region': 'neck',
          'display_name': 'Neck',
          'sides': ['right', 'left', 'both'],
          'aspects': ['medial', 'lateral'],
          'aspect_offered': true,
          'goal_pathways': ['discomfort', 'range_of_motion'],
        },
        {
          // Listed so a client can explain the gap — never offered as a chip.
          'known': false,
          'region': 'full-body',
          'display_name': 'Full body',
        },
      ],
      'pathways': [
        {
          'goal_pathway': 'range_of_motion',
          'regions': [
            {'known': true, 'region': 'neck', 'display_name': 'Neck'},
          ],
        },
      ],
    };

    test('parses the regions and drops the ones nothing is authored for', () {
      final catalog = RecoveryIntakeCatalog.fromV3Json(json);

      expect(catalog.version, '3.1');
      expect(catalog.regions, hasLength(3));

      final offered = catalog.regionsFor(null);
      expect(offered.map((r) => r.region), ['low-back', 'neck']);

      final lowBack = catalog.byId('low-back')!;
      expect(lowBack.label, 'Lower Back');
      expect(lowBack.movementTests.single.test, 'Forward bend (flexion)');
      expect(lowBack.referralMenu, ['glute', 'hamstring']);
      expect(lowBack.asksSide, isTrue);
      // One authored aspect is not a question.
      expect(lowBack.aspectOffered, isFalse);
      expect(catalog.byId('neck')!.aspectOffered, isTrue);
    });

    test('a goal is served its own region list, not the whole corpus', () {
      final catalog = RecoveryIntakeCatalog.fromV3Json(json);
      expect(catalog.regionsFor('range_of_motion').map((r) => r.region),
          ['neck']);
    });

    test('falls back to each region\'s own goal_pathways without `pathways`',
        () {
      final withoutPathways = Map<String, dynamic>.from(json)
        ..remove('pathways');
      final catalog = RecoveryIntakeCatalog.fromV3Json(withoutPathways);

      expect(catalog.regionsFor('range_of_motion').map((r) => r.region),
          ['neck']);
      expect(catalog.regionsFor('discomfort').map((r) => r.region),
          ['low-back', 'neck']);
    });

    test('an older catalogue that declares no pathways still offers areas', () {
      final legacy = {
        'version': '3.1',
        'regions': [
          {'known': true, 'region': 'knee', 'display_name': 'Knee'},
        ],
      };
      final catalog = RecoveryIntakeCatalog.fromV3Json(legacy);

      // Offering everything and letting the resolve be the authority beats an
      // empty chip row, which is a dead end with nothing to say.
      expect(catalog.regionsFor('discomfort').map((r) => r.region), ['knee']);
    });
  });
}
