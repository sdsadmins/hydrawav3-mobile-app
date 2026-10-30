import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/session_coach/data/session_coach_repository.dart';
import 'package:hydrawav3/features/session_coach/domain/session_coach_models.dart';
import 'package:hydrawav3/features/session_coach/presentation/widgets/session_coach_card.dart';

Map<String, dynamic> _marker(String id, String type) => {
      'id': id,
      'type': type,
      'position': [0.1, 1.2, 0.3],
      'normal': [0, 0, 1],
    };

/// The shape `GET session-coach/body-part/:id` returns (refs populated).
final _knee = SessionCoach.fromJson({
  '_id': 'c1',
  'bodyPartId': {'_id': 'b1', 'partName': 'Knee'},
  'defaultProtocolId': {'_id': 'p1', 'template_name': 'Total Recovery'},
  'secondaryProtocolIds': [
    {'_id': 'p2', 'template_name': 'Post-Workout Recovery'},
  ],
  'supportTypes': ['Support recovery'],
  'sets': {
    'Support recovery': [
      {
        'id': 's1',
        'name': 'Calf',
        'muscles': [
          {
            'muscleId': 'm1',
            'muscleName': 'Gastrocnemius',
            'sun': _marker('a', 'sun'),
            'moon': _marker('b', 'moon'),
          },
        ],
      },
      {
        'id': 's2',
        'name': 'Above the knee',
        'muscles': [
          {'muscleId': 'm2', 'muscleName': 'Vastus medialis', 'sun': _marker('c', 'sun')},
        ],
      },
    ],
  },
});

void main() {
  late List<(String, String)> applied;
  late List<List<Map<String, dynamic>>> shown;
  // apply and delay calls in the order they happened
  late List<String> calls;

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    applied = [];
    shown = [];
    calls = [];
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        coachBodyPartsProvider.overrideWith((ref) async => const [
              CoachBodyPart(id: 'b1', name: 'Knee'),
              CoachBodyPart(id: 'b2', name: 'Wrist'),
            ]),
        sessionCoachesByBodyPartProvider.overrideWith(
            (ref, id) async => id == 'b1' ? [_knee] : const <SessionCoach>[]),
        protocolDetailProvider
            .overrideWith((ref, id) => Completer<Protocol>().future),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SessionCoachCard(
              units: const [
                CoachUnit(id: 'u1', name: 'Unit 1', canLocate: true),
                CoachUnit(id: 'u2', name: 'Unit 2', canLocate: true),
              ],
              onApply: (d, p) async {
                applied.add((d, p));
                calls.add('apply $d');
                return true;
              },
              onSetDelay: (d, s) => calls.add('delay $d ${s}s'),
              onLocate: (_) {},
              bodyBuilder: (m) {
                shown.add(m);
                return const ColoredBox(color: Colors.black);
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final size in [const Size(360, 800), const Size(1024, 1366)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('body → goal → sets → use this set ($tag)', (tester) async {
      await pump(tester, size);
      // closed: the coach capsule
      expect(find.text('Session coach'), findsOneWidget);
      expect(find.textContaining('Body area, protocol and pad placement'),
          findsOneWidget);
      expect(find.text('0/2', findRichText: true), findsOneWidget);

      await tap(tester, find.text('Session coach'));
      expect(find.text('STEP 1 OF 3 · BODY'), findsOneWidget);
      await tap(tester, find.text('Knee'));

      expect(find.text('STEP 2 OF 3 · GOAL'), findsOneWidget);
      expect(find.text('Not in this coach plan'), findsOneWidget); // activation
      expect(find.text('Total Recovery'), findsOneWidget);
      await tap(tester, find.text('Support recovery'));

      expect(find.text('STEP 3 OF 3 · PLACEMENT'), findsOneWidget);
      expect(find.text('Set 1 · Calf'), findsWidgets);
      // both set cards sit side by side; each lists its pads by muscle
      // Sun + Moon lines on the card, and the caption on the 3D box
      expect(find.text('Gastrocnemius'), findsNWidgets(3));
      expect(find.text('Vastus medialis'), findsOneWidget);
      expect(shown.last.length, 2); // the set's Sun + Moon go to the 3D body
      // set 1 defaults to the Unit 1 tab, set 2 to the next free unit
      expect(find.text('Locate Unit 1'), findsOneWidget);
      expect(find.text('Locate Unit 2'), findsOneWidget);

      await tap(tester, find.text('Use this set  →'));
      expect(applied, [('u1', 'p1')]);
      expect(find.text('1 of 2 planned'), findsOneWidget);
      // moves on to set 2, defaulting to the next free unit
      // set 1 is assigned
      expect(find.text('2 SETS \u00b7 1 ASSIGNED'), findsOneWidget);
      expect(shown.last.length, 1); // the body now shows set 2
      await tap(tester, find.text('Use this set  →'));
      expect(applied.last, ('u2', 'p1'));
      expect(find.text('2 of 2 planned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> toSets(WidgetTester tester) async {
    await pump(tester, const Size(390, 844));
    await tap(tester, find.text('Session coach'));
    await tap(tester, find.text('Knee'));
    await tap(tester, find.text('Support recovery'));
  }

  Finder plus() => find.text('+');
  Finder minus() => find.text('\u2212');
  Finder delay(String v) => find.text('${v}s', findRichText: true);

  testWidgets('the delay sits between the two set cards, 0 at first',
      (tester) async {
    await toSets(tester);
    expect(delay('0'), findsOneWidget); // one joint for 2 sets
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('starts with the others'), findsNWidgets(2));
    expect(find.text('Reset delays'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('− / + step a second; cards show their order and start',
      (tester) async {
    await toSets(tester);
    await tap(tester, plus());
    expect(delay('+1'), findsOneWidget);
    expect(find.text('1st \u00b7 starts 0:00'), findsOneWidget);
    expect(find.text('2nd \u00b7 starts 0:01'), findsOneWidget);
    expect(find.text('Reset delays'), findsOneWidget);
    for (var k = 0; k < 4; k++) {
      await tap(tester, plus());
    }
    expect(find.text('2nd \u00b7 starts 0:05'), findsOneWidget);
    await tap(tester, minus());
    expect(delay('+4'), findsOneWidget);
    await tap(tester, find.text('Reset delays'));
    expect(delay('0'), findsOneWidget);
    expect(find.text('Reset delays'), findsNothing);
  });

  testWidgets('holding + keeps stepping, and it stops at 60 s',
      (tester) async {
    await toSets(tester);
    await tester.ensureVisible(plus());
    final g = await tester.startGesture(tester.getCenter(plus()));
    await tester.pump(const Duration(milliseconds: 600)); // long press starts
    for (var k = 0; k < 80; k++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await g.up();
    await tester.pump();
    expect(delay('+60'), findsOneWidget); // a unit's Start Delay tops out
    expect(tester.takeException(), isNull);
  });

  testWidgets('Use this set: protocol first, then the start delay',
      (tester) async {
    await toSets(tester);
    for (var k = 0; k < 8; k++) {
      await tap(tester, plus()); // set 2 starts at 0:08
    }
    await tap(tester, find.text('Use this set  \u2192'));
    await tap(tester, find.text('Use this set  \u2192'));
    expect(calls, [
      'apply u1',
      'delay u1 0s',
      'apply u2',
      'delay u2 8s',
    ]);
    // a later change reaches the unit that already has the set
    calls.clear();
    await tap(tester, plus());
    expect(calls, ['delay u2 9s']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delay before anything is on a unit touches no unit',
      (tester) async {
    await toSets(tester);
    await tap(tester, plus());
    expect(calls, isEmpty);
  });

  testWidgets('Swap trades the units and re-applies sets already on',
      (tester) async {
    await toSets(tester);
    for (var k = 0; k < 3; k++) {
      await tap(tester, plus());
    }
    await tap(tester, find.text('Use this set  \u2192'));
    await tap(tester, find.text('Use this set  \u2192'));
    calls.clear();
    await tap(tester, find.text('Swap'));
    expect(calls, [
      'apply u2',
      'delay u2 0s',
      'apply u1',
      'delay u1 3s',
    ]);
    expect(find.text('Locate Unit 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a body part without a coach says so', (tester) async {
    await pump(tester, const Size(390, 844));
    await tap(tester, find.text('Session coach'));
    await tap(tester, find.text('Wrist'));
    expect(find.text('No coach plan for Wrist yet. Pick another body part.'),
        findsOneWidget);
  });
}
