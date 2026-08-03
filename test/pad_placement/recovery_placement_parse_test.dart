import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/pad_placement/domain/recovery_engine_models.dart';
import 'package:hydrawav3/features/performance_protocols/domain/performance_models.dart';

/// Shaped on a real `recovery-engine-v3/resolve` response: neck, range of
/// motion, right side. One APPLIED set (`primary_site`, diagonal geometry) and
/// one set the point authors but the engine held back (`referral_link`, set 2).
///
/// Trimmed to the keys the parser reads — the omitted blocks (safety screen,
/// exclusions, reference, laterality) are not parsed here.
const _resolveJson = '''
{
  "pathway": "range_of_motion",
  "generation": "v3",
  "safety": { "refer_out": false, "reason": null },
  "pathwayRouting": {
    "requested": "range_of_motion",
    "applied": "range_of_motion",
    "rerouted": false,
    "reason": null
  },
  "presentation": {
    "region": "neck",
    "aspect": "lateral",
    "side": "right",
    "condition_family": "joint_mobility_limitation",
    "acuity": "chronic"
  },
  "reassessmentNote": null,
  "reviewFlags": [],
  "reference": {
    "disclaimer": "HydraWav3 is a wellness device placement guide, not a clinical diagnostic tool. This rulebook is for practitioner use only.",
    "client_disclaimer": "This is general wellness guidance, not medical advice, and not a diagnosis."
  },
  "intake": { "region": "neck", "display_name": "Neck" },
  "assessment": {
    "movement_test_run": null,
    "movement_test_authored": "Neck rotation (left and right)",
    "tests_offered": [
      { "test": "Neck rotation (left and right)", "reveals": "lateral and rotational pattern" }
    ],
    "finding": "A neck wanting greater range",
    "case_type": "local_isolated"
  },
  "point": {
    "recovery_id": "rec-neck-rom-right-v1",
    "goal_pathway": "range_of_motion",
    "case_type": "local_isolated",
    "region": "neck",
    "version": "1.0",
    "source": "authored"
  },
  "driver": {
    "description": "Cervical mobility on the chosen side.",
    "tissue_type": "joint"
  },
  "thermal": {
    "mode": "hot_pack",
    "rationale": "Warmth relaxes the tissue and supports range.",
    "recommendation_only": true
  },
  "clinical_intent": {
    "what_it_helps_relieve": ["A neck that feels stiff or blocked"],
    "expected_mobility_rom_benefit": "May support fuller neck range.",
    "lymphatic_circulatory_benefit": null,
    "tissue_recovery_benefit": null,
    "mechanism_rationale": "Warmth over the neck raises tissue extensibility to support range on the chosen side.",
    "expected_response_time": {
      "typical_window": "one session",
      "note": "Re-assess after."
    },
    "expected_sensation": "Gentle warmth and a soft contrast through the area.",
    "reassessment_marker": "Re-run the Neck rotation (left and right); look for easier, fuller range.",
    "claim_strength": "may_support",
    "wellness_claim_wording": "This placement may support a neck that feels stiff or blocked."
  },
  "safetyBlock": {
    "refer_out": false,
    "cautions_relative": ["Occipital placement: run cryo, do not use the alternating setting"]
  },
  "chain": {
    "conditional": {
      "withheld_sets": [
        {
          "set_index": 2,
          "set_role": "referral_link",
          "note": "The upper-back neighbor for a fuller neck-mobility effect.",
          "reason": "A referral-link set is for where a pattern travels. The user reported no referral, this point authors none, and its case_type is \\"local_isolated\\", so it does not apply. Report a referral to see it."
        }
      ]
    },
    "referral": {
      "applies": false,
      "withheld_sets": [
        {
          "set_index": 2,
          "set_role": "referral_link",
          "note": "The upper-back neighbor for a fuller neck-mobility effect.",
          "reason": "A referral-link set is for where a pattern travels."
        }
      ]
    }
  },
  "sets": [
    {
      "set_index": 1,
      "set_role": "primary_site",
      "pad_geometry": "diagonal",
      "note": "Cervical mobility on the chosen side.",
      "pads": [
        {
          "pad_label": "sun",
          "body_side": "right",
          "aspect": "posterior",
          "plane": "posterior",
          "side": "right",
          "position": "proximal",
          "landmark_anchor": "Levator scapulae, right",
          "target_muscles": ["Levator scapulae"],
          "proxy_for": null
        },
        {
          "pad_label": "moon",
          "body_side": "right",
          "aspect": "posterior",
          "plane": "posterior",
          "side": "right",
          "position": "mid",
          "landmark_anchor": "C6-C7, right",
          "target_muscles": ["Semispinalis colli muscle", "Multifidus colli muscle"],
          "proxy_for": null
        }
      ]
    }
  ],
  "session": {
    "sets_returned": 1,
    "sets_in_document": 2,
    "sequencing_note": "Apply priority-1 sets first; sequence the rest of the chain across later sessions.",
    "guidance": "Apply all 1 set this session. 1 referral-link set is authored on this point and is not shown (set 2)."
  }
}
''';

void main() {
  RecoveryPlacement parse() => RecoveryPlacement.fromJson(
        jsonDecode(_resolveJson) as Map<String, dynamic>,
        regionLabel: 'Neck',
      );

  test('resolves the applied set with its pads and geometry', () {
    final placement = parse();

    expect(placement.hasPads, isTrue);
    expect(placement.referOut, isFalse);
    expect(placement.recoveryId, 'rec-neck-rom-right-v1');

    final applied = placement.payload.appliedSets;
    expect(applied.length, 1);
    expect(applied.single.setIndex, 1);
    expect(applied.single.role, 'primary site');
    expect(applied.single.padGeometry, 'diagonal');
    expect(applied.single.sun?.landmarkAnchor, 'Levator scapulae, right');
    expect(applied.single.moon?.landmarkAnchor, 'C6-C7, right');
  });

  test('carries the withheld set — "set 2" — with the engine\'s reason', () {
    final withheld = parse().payload.withheldSets;

    // Reported under BOTH chain.conditional and chain.referral; listed once.
    expect(withheld.length, 1);
    expect(withheld.single.setIndex, 2);
    expect(withheld.single.role, 'referral link');
    expect(withheld.single.withheld, isTrue);
    expect(withheld.single.withheldReason, contains('referral-link set'));
    // A withheld set has no pads — that is what "withheld" means.
    expect(withheld.single.sun, isNull);
    expect(withheld.single.moon, isNull);
  });

  test('a withheld set never makes the payload look like a placement', () {
    final placement = parse();
    // Both sets are in `sets`; only the applied one counts.
    expect(placement.payload.sets.length, 2);
    expect(placement.payload.isRefusal, isFalse);
  });

  test('reads the movement test from the v3 keys, not the absent one', () {
    // `assessment.movement_test` does not exist in v3 — reading it left this
    // empty on every recovery placement.
    expect(parse().movementTest, 'Neck rotation (left and right)');
  });

  test('carries the session guidance and sequencing note verbatim', () {
    final payload = parse().payload;
    expect(payload.guidance, startsWith('Apply all 1 set this session.'));
    expect(payload.sequencingNote, startsWith('Apply priority-1 sets first'));
  });

  test('pad geometry resolves to the web catalogue wording', () {
    final geometry = PadGeometryInfo.of('diagonal');
    expect(geometry?.label, 'Diagonal');
    expect(geometry?.reads, 'offset');
    expect(geometry?.intent, contains('curved surface'));
    expect(PadGeometryInfo.of('not_a_geometry'), isNull);
  });

  test('thermal, claim and cautions come through', () {
    final placement = parse();
    expect(placement.thermalLabel, 'Hot pack');
    expect(placement.wellnessClaim, startsWith('This placement may support'));
    expect(placement.cautions, hasLength(1));
    expect(placement.finding, 'A neck wanting greater range');
  });

  test('the driver block — case, tissue, description', () {
    final placement = parse();
    expect(placement.driverDescription, 'Cervical mobility on the chosen side.');
    expect(placement.tissueType, 'joint');
    // How the pattern is DISTRIBUTED — from `assessment.case_type`. Explicitly
    // NOT `presentation.condition_family`, which is a different fact.
    expect(placement.caseType, 'Local isolated');
    expect(placement.conditionFamily, 'Joint mobility limitation');
    expect(placement.acuity, 'Chronic');
    expect(placement.presentationSide, 'right');
    expect(placement.presentationAspect, 'lateral');
    expect(placement.lymphaticRegion, isEmpty); // not a lymphatic placement
  });

  test('thermal carries the recommendation-only flag and no alternatives', () {
    final placement = parse();
    expect(placement.thermalRecommendationOnly, isTrue);
    expect(placement.thermalAlternatives, isEmpty);
    expect(placement.thermalDowngrade, isEmpty);
  });

  test('clinical intent — relieves, benefits, sensation', () {
    final placement = parse();
    expect(placement.whatItHelpsRelieve,
        contains('A neck that feels stiff or blocked'));
    expect(placement.mobilityBenefit, 'May support fuller neck range.');
    expect(placement.lymphaticBenefit, isEmpty);
    expect(placement.expectedSensation, startsWith('Gentle warmth'));
    expect(placement.mechanismRationale, contains('tissue extensibility'));
  });

  test('reassessment marker and its typical window', () {
    final placement = parse();
    expect(placement.reassessmentMarker, contains('Re-run the Neck rotation'));
    expect(placement.expectedWindow, 'one session');
    expect(placement.expectedWindowNote, 'Re-assess after.');
  });

  test('routing, provenance and the two disclaimers', () {
    final placement = parse();
    expect(placement.pathwayRerouted, isFalse);
    expect(placement.requestedPathway, 'range_of_motion');
    expect(placement.pointSource, 'authored');
    expect(placement.isComposed, isFalse);
    expect(placement.pointVersion, '1.0');
    expect(placement.generation, 'v3');
    expect(placement.clientDisclaimer, contains('not medical advice'));
    expect(placement.practitionerDisclaimer, contains('wellness device'));
    expect(placement.reviewFlags, isEmpty);
  });

  test('reads back out of the payload the pad map already holds', () {
    // The pad map only receives a PadSetPayload; `raw` is the whole resolve
    // envelope, so the detail is recoverable without changing any call site.
    final placement = parse();
    final round = RecoveryPlacement.fromPayload(placement.payload);
    expect(round, isNotNull);
    expect(round!.driverDescription, placement.driverDescription);
    expect(round.thermalLabel, 'Hot pack');
    expect(round.payload.withheldSets.single.setIndex, 2);

    // A performance payload has none of it.
    expect(
      RecoveryPlacement.fromPayload(const PadSetPayload(discipline: 'performance')),
      isNull,
    );
  });
}
