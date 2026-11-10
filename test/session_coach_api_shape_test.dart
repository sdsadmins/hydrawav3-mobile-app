import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/session_coach/domain/session_coach_models.dart';

/// `GET session-coach/body-part/:id` as the server returned it on 2026-10-30:
/// protocols grouped per support type, muscle pad colours.
const _live = r'''
[{"_id":"6ae47be8de4923dece887a34",
  "bodyPartId":{"_id":"6998d524ab5877f63dd637e4","partName":"Back Left Lower Leg"},
  "supportTypes":["Support activation"],
  "protocols":{"Support activation":{
    "defaultProtocolId":{"_id":"6a83464506ccc271e8ccab8b","template_name":"Activate","kind":"protocol"},
    "secondaryProtocolIds":[{"_id":"69aca7637b784aec85462e99","template_name":"Breath Sync 5","kind":"protocol"}]}},
  "isActive":true,
  "sets":{"Support activation":[{"id":"mvuvismi-0ga9lf","name":"Set 1","muscles":[{
    "muscleId":"6998fab0ab5877f63dd63fe8",
    "muscleName":"Leg - Lower - Back - Left Gastrocnemius",
    "sun":{"id":"pad_mvuvizmdtirv8","type":"sun","position":[-0.0664,0.3031,0.1331],"normal":[-0.432,-0.4771,0.7653],"mesh":"external abdominal oblique muscle.r","region":"external abdominal oblique","facing":"front","side":"right","createdAt":1793358801877},
    "moon":{"id":"pad_mvuvj17x6nxx7","type":"moon","position":[0.1272,0.406,0.1219],"normal":[0.6633,-0.2259,0.7134],"mesh":"external abdominal oblique muscle.l","region":"external abdominal oblique","facing":"front","side":"left","createdAt":1793358803949},
    "muscleColor":"#3B82F6","sunColor":"#818CF8","moonColor":"#EF4444"}]}]},
  "createdBy":1,"updatedBy":1,
  "createdAt":"2026-10-30T11:13:44.145Z","updatedAt":"2026-10-30T11:13:44.145Z","__v":0}]
''';

void main() {
  SessionCoach coach() => SessionCoach.fromJson(
      Map<String, dynamic>.from((jsonDecode(_live) as List).first as Map));

  test('protocols come from the support type', () {
    final c = coach();
    expect(c.bodyPartName, 'Back Left Lower Leg');
    expect(c.defaultProtocolFor(kSupportActivation)?.name, 'Activate');
    expect(c.protocolsFor(kSupportActivation).map((p) => p.name),
        ['Activate', 'Breath Sync 5']);
    expect(c.setsFor(kSupportActivation), hasLength(1));
    expect(c.setsFor(kSupportRecovery), isEmpty);
  });

  test('the set lists its muscles and colours its pads', () {
    final set = coach().setsFor(kSupportActivation).single;
    expect(set.muscleNames, ['Leg - Lower - Back - Left Gastrocnemius']);
    expect(set.sunMuscles, ['Leg - Lower - Back - Left Gastrocnemius']);
    expect(set.moonMuscles, ['Leg - Lower - Back - Left Gastrocnemius']);
    expect(set.markers.map((m) => '${m['type']} ${m['color']}'),
        ['sun #818CF8', 'moon #EF4444']);
    expect(set.muscleHighlights, [
      {
        'name': 'Leg - Lower - Back - Left Gastrocnemius',
        'color': '#3B82F6',
      },
    ]);
    expect(set.padLabels.map((pad) => '${pad.type} ${pad.color}'),
        ['sun #818CF8', 'moon #EF4444']);
    // the pad itself is passed through as stored
    expect(set.markers.first['position'], [-0.0664, 0.3031, 0.1331]);
  });

  test('the older shape (top-level protocols) still reads', () {
    final c = SessionCoach.fromJson({
      '_id': 'c1',
      'defaultProtocolId': {'_id': 'p1', 'template_name': 'Total Recovery'},
      'secondaryProtocolIds': ['p2'],
      'supportTypes': [kSupportRecovery],
      'sets': {},
    });
    expect(c.defaultProtocolFor(kSupportRecovery)?.name, 'Total Recovery');
    expect(c.protocolsFor(kSupportRecovery).map((p) => p.id), ['p1', 'p2']);
  });

  test('a populated body-part reference is normalized to its id and name', () {
    final run = SessionCoachRun.fromJson({
      'sessionCoachId': 'c1',
      'bodyPartId': {'_id': 'body-1', 'partName': 'Elbow'},
      'supportType': kSupportRecovery,
      'sets': [
        {
          'setId': 's1',
          'name': 'Set 1',
          'protocolId': 'p1',
          'protocolName': 'Recovery',
          'macAddress': 'AA:BB:CC',
        },
      ],
    });

    expect(run.bodyPartId, 'body-1');
    expect(run.bodyPartName, 'Elbow');
  });

  test('a pad colour that is not a hex colour is dropped', () {
    final m = CoachMuscle.fromJson({
      'muscleName': 'Hamstrings',
      'sun': {'type': 'sun'},
      'sunColor': "red');alert(1);//",
    });
    expect(m.muscleColor, kDefaultCoachMuscleColor);
    expect(m.sunColor, kDefaultCoachSunColor);
    expect(m.moonColor, kDefaultCoachMoonColor);
  });
}
