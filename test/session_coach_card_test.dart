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

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    applied = [];
    shown = [];
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
                return true;
              },
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
      expect(find.text('Session coach'), findsOneWidget);
      expect(find.text('0 of 2 planned'), findsOneWidget);

      await tap(tester, find.text('Session coach'));
      expect(find.text('STEP 1 OF 3 · BODY'), findsOneWidget);
      await tap(tester, find.text('Knee'));

      expect(find.text('STEP 2 OF 3 · GOAL'), findsOneWidget);
      expect(find.text('Not in this coach plan'), findsOneWidget); // activation
      expect(find.text('Total Recovery'), findsOneWidget);
      await tap(tester, find.text('Support recovery'));

      expect(find.text('STEP 3 OF 3 · PLACEMENT'), findsOneWidget);
      expect(find.text('Set 1 · Calf'), findsWidgets);
      expect(find.text('Sun: Gastrocnemius'), findsOneWidget);
      expect(find.text('Moon: Gastrocnemius'), findsOneWidget);
      expect(shown.last.length, 2); // the set's Sun + Moon go to the 3D body
      expect(find.text('Locate Unit 1'), findsOneWidget);

      await tap(tester, find.text('Use this set  →'));
      expect(applied, [('u1', 'p1')]);
      expect(find.text('1 of 2 planned'), findsOneWidget);
      // moves on to set 2, defaulting to the next free unit
      expect(find.text('Sun: Vastus medialis'), findsOneWidget);
      expect(shown.last.length, 1);
      await tap(tester, find.text('Use this set  →'));
      expect(applied.last, ('u2', 'p1'));
      expect(find.text('2 of 2 planned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a body part without a coach says so', (tester) async {
    await pump(tester, const Size(390, 844));
    await tap(tester, find.text('Session coach'));
    await tap(tester, find.text('Wrist'));
    expect(find.text('No coach plan for Wrist yet. Pick another body part.'),
        findsOneWidget);
  });
}
