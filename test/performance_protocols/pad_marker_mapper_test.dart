import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/pad_placement/domain/pad_marker_mapper.dart';
import 'package:hydrawav3/features/performance_protocols/domain/performance_models.dart';

Map<String, dynamic> _pad({
  String label = 'Sun pad',
  String anchor = '',
  String side = 'right',
  String plane = 'posterior',
  String position = 'proximal',
  List<String> muscles = const [],
}) =>
    {
      'pad_label': label,
      'side': side,
      'plane': plane,
      'position_along_muscle': position,
      'landmark_anchor': anchor,
      'stack_position': 'base',
      'target_muscles': muscles,
    };

Map<String, dynamic> _payload(List<Map<String, dynamic>> sets) => {
      'discipline': 'tennis',
      'display_name': 'Tennis',
      'role': 'Singles Player',
      'subtype': null,
      'chain': {
        'chain_id': 'c1',
        'name': 'Serve chain',
        'movement': 'overhead serve',
        'directional_mode': 'proximal_to_distal',
      },
      'sets': sets,
    };

void main() {
  group('tier 1 — zone keys', () {
    test('an exact zone key passes through', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {
          'set_index': 1,
          'role': 'generator',
          'placement_label': 'Posterior hip',
          'sun': _pad(anchor: 'hamstring_origin'),
        }
      ])));

      final sun = data.padOf(0, 'sun')!;
      expect(sun.zone, 'hamstring_origin');
      expect(sun.isUnmapped, isFalse);
      expect(sun.view, 'back');
    });

    test('clinical phrasing resolves through the synonym table', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {
          'set_index': 1,
          'sun': _pad(anchor: 'Ischial tuberosity, just medial'),
          'moon': _pad(
              anchor: 'Upper trapezius at the shoulder slope', side: 'left'),
        }
      ])));

      expect(data.padOf(0, 'sun')!.zone, 'hamstring_origin');
      expect(data.padOf(0, 'moon')!.zone, 'upper_trap');
    });

    test('the longest matching phrase wins over a generic one', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {'set_index': 1, 'sun': _pad(anchor: 'medial hamstring origin')}
      ])));

      expect(data.padOf(0, 'sun')!.zone, 'medial_hamstring_origin');
    });
  });

  group('tier 2 — muscle geometry', () {
    test('an unknown anchor with target muscles emits the geometry inputs', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {
          'set_index': 1,
          'sun': _pad(
            anchor: 'two finger-widths lateral to the crest',
            plane: 'anterior',
            position: 'distal',
            muscles: ['Rectus abdominis'],
          ),
        }
      ])));

      final sun = data.padOf(0, 'sun')!;
      expect(sun.zone, isNull);
      expect(sun.hasMuscleFallback, isTrue);
      expect(sun.isUnmapped, isFalse);

      final marker = sun.toMarker();
      expect(marker['targetMuscles'], ['Rectus abdominis']);
      expect(marker['plane'], 'anterior');
      expect(marker['muscleOffset'], lessThan(0)); // distal
      expect(marker.containsKey('zone'), isFalse);
      expect(sun.view, 'front'); // from the plane, no zone
    });

    test('proximal / mid / distal map to signed offsets', () {
      expect(muscleOffsetFor('proximal third'), greaterThan(0));
      expect(muscleOffsetFor('mid belly'), 0.0);
      expect(muscleOffsetFor('distal insertion'), lessThan(0));
      expect(muscleOffsetFor(''), isNull);
    });
  });

  group('tier 3 — unmapped', () {
    test('no zone and no muscles means no marker is emitted', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {
          'set_index': 1,
          'sun': _pad(anchor: 'wherever it feels tight'),
          'moon': _pad(anchor: 'lumbar paraspinal', side: 'left'),
        }
      ])));

      expect(data.padOf(0, 'sun')!.isUnmapped, isTrue);
      expect(data.hasUnmapped, isTrue);

      // Only the resolvable moon pad reaches the viewer.
      final markers = data.markers();
      expect(markers, hasLength(1));
      expect(markers.single['role'], 'moon');
      expect(markers.single['zone'], 'low_back_l23');
    });
  });

  group('sides and ordering', () {
    test('side comes from the pad, falling back to the plane text', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {
          'set_index': 1,
          'sun': _pad(anchor: 'lat', side: 'left'),
          'moon': _pad(anchor: 'lat', side: '', plane: 'right lateral'),
        }
      ])));

      expect(data.padOf(0, 'sun')!.side, 'left');
      expect(data.padOf(0, 'moon')!.side, 'right');
    });

    test('sets sort by set_index regardless of payload order', () {
      final payload = PadSetPayload.fromJson(_payload([
        {'set_index': 3, 'placement_label': 'C', 'sun': _pad(anchor: 'lat')},
        {'set_index': 1, 'placement_label': 'A', 'sun': _pad(anchor: 'lat')},
        {'set_index': 2, 'placement_label': 'B', 'sun': _pad(anchor: 'lat')},
      ]));

      expect(payload.sets.map((s) => s.placementLabel), ['A', 'B', 'C']);

      final data = PadPlacementViewData.from(payload);
      expect(data.markers().map((m) => m['setIndex']), [0, 1, 2]);
      // Set colours cycle in reference order (blue / magenta / green).
      expect(data.markers().map((m) => m['setColor']), kSetColors);
    });

    test('a side-only set opens front — the stage only flips front/back', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {'set_index': 1, 'sun': _pad(anchor: 'lat')} // `lat` is a side zone
      ])));

      expect(data.padOf(0, 'sun')!.view, 'side');
      expect(data.viewFor(0), 'front');
    });

    test('focusing a set filters the markers and picks its view', () {
      final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
        {'set_index': 1, 'sun': _pad(anchor: 'anterior_deltoid')},
        {'set_index': 2, 'sun': _pad(anchor: 'hamstring_origin')},
      ])));

      expect(data.markers(focusSetIndex: 1), hasLength(1));
      expect(data.viewFor(1), 'back');
      expect(data.viewFor(0), 'front');
    });

    test('show all sets also includes deferred later-session pads', () {
      final payload = PadSetPayload.fromJson({
        'discipline': 'tennis',
        'display_name': 'Tennis',
        'role': 'Singles Player',
        'chain': {'chain_id': 'c1', 'name': 'Serve chain'},
        'sets': [
          {
            'set_index': 1,
            'role': 'generator',
            'sun': _pad(anchor: 'anterior_deltoid'),
          },
          {
            'set_index': 2,
            'role': 'transfer',
            'sun': _pad(anchor: 'hamstring_origin'),
            'deferred': true,
          },
        ],
      });

      final data = PadPlacementViewData.from(payload);
      expect(payload.appliedSets, hasLength(1));
      expect(payload.deferredSets, hasLength(1));
      expect(data.markers(includeDeferred: true), hasLength(2));
    });
  });

  group('helper utilities', () {
    test('all-view data includes deferred pads when requested', () {
      final payload = PadSetPayload.fromJson({
        'discipline': 'tennis',
        'display_name': 'Tennis',
        'role': 'Singles Player',
        'chain': {'chain_id': 'c1', 'name': 'Serve chain'},
        'sets': [
          {'set_index': 1, 'role': 'generator', 'sun': _pad(anchor: 'lat')},
          {
            'set_index': 2,
            'role': 'transfer',
            'sun': _pad(anchor: 'hamstring_origin'),
            'deferred': true,
          },
        ],
      });

      final data = PadPlacementViewData.from(payload);
      expect(data.padsFor(null), hasLength(1));
      expect(data.padsFor(null, includeDeferred: true), hasLength(2));
    });
  });

  group('catalogue parsing', () {
    test('disciplines parse from objects, bare strings and nested envelopes',
        () {
      expect(
        Discipline.listFrom([
          {'discipline': 'track', 'display_name': 'Track & Field'}
        ]).single.label,
        'Track & Field',
      );
      // A bare id list must not read as "this org has no disciplines".
      expect(
        Discipline.listFrom(['tennis', 'golf']).map((d) => d.discipline),
        ['tennis', 'golf'],
      );
      expect(
        Discipline.listFrom({
          'data': {
            'disciplines': [
              {'discipline': 'tennis'}
            ]
          }
        }).single.discipline,
        'tennis',
      );
    });

    test('the label falls back to the wire key when no display_name is sent',
        () {
      expect(Discipline.listFrom(['track']).single.label, 'track');
    });

    test('a payload with no list at all is distinguishable from an empty list',
        () {
      // An empty catalogue: a real, reportable emptiness.
      expect(rowsOrNull(<dynamic>[]), isEmpty);
      expect(rowsOrNull({'data': <dynamic>[]}), isEmpty);
      // Not a catalogue response — e.g. a dev tunnel's HTML interstitial, or a
      // renamed field. Must NOT be reported as "nothing is authored yet".
      expect(rowsOrNull('<html>ngrok</html>'), isNull);
      expect(rowsOrNull({'message': 'Not Found'}), isNull);
      expect(rowsOrNull(null), isNull);
    });

    test('chains accept a bare id list, labelled by id until names arrive', () {
      final chains = ChainSummary.listFrom(['serve_chain']);
      expect(chains.single.chainId, 'serve_chain');
      expect(chains.single.label, 'serve_chain');
    });
  });

  group('refusal envelope', () {
    test('chain: null is a refusal, not an empty pad set', () {
      final payload = PadSetPayload.fromJson({
        'discipline': 'tennis',
        'role': 'Singles Player',
        'chain': null,
        'sets': <dynamic>[],
        'message': 'I can’t help with that — please seek urgent care.',
      });

      expect(payload.isRefusal, isTrue);
      expect(payload.refusalMessage, contains('urgent care'));
    });

    test('a real pad set is not a refusal', () {
      final payload = PadSetPayload.fromJson(_payload([
        {'set_index': 1, 'sun': _pad(anchor: 'lat')}
      ]));
      expect(payload.isRefusal, isFalse);
      expect(payload.contextLine, 'Tennis · Singles Player');
    });
  });

  test('the viewer envelope keeps the shape the pad screens already read', () {
    final data = PadPlacementViewData.from(PadSetPayload.fromJson(_payload([
      {
        'set_index': 1,
        'role': 'generator',
        'placement_label': 'Posterior hip',
        'sun': _pad(anchor: 'hamstring_origin'),
        'moon': _pad(anchor: 'glute', side: 'left'),
      }
    ])));

    final envelope = data.toViewerPayload();
    final rec = envelope['recommendation'] as Map<String, dynamic>;
    expect(rec['title'], 'Serve chain');
    final sets = rec['sets'] as List;
    expect(sets, hasLength(1));
    expect((sets.first as Map)['title'], 'Set 1 · Posterior hip');
    expect(((sets.first as Map)['sun'] as Map)['label'], isNotEmpty);
    expect(envelope['markers'], hasLength(2));
  });
}
