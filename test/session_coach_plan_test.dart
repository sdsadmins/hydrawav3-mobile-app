import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/session_coach/data/coach_plan_store.dart';
import 'package:hydrawav3/features/session_coach/data/session_coach_repository.dart';
import 'package:hydrawav3/features/session_coach/domain/session_coach_models.dart';
import 'package:hydrawav3/features/session_coach/presentation/widgets/session_coach_card.dart';

Map<String, dynamic> _marker(String id, String type) => {
      'id': id,
      'type': type,
      'position': [0.1, 1.2, 0.3],
      'normal': [0, 0, 1],
    };

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
          {
            'muscleId': 'm2',
            'muscleName': 'Vastus medialis',
            'sun': _marker('c', 'sun'),
          },
        ],
      },
    ],
  },
});

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
      : super(const AuthState(
            isAuthenticated: true, isInitialized: true, selectedOrgId: '493'));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _jalen = Client(id: 'jalen', clientName: 'Jalen Brooks');
const _marcus = Client(id: 'marcus', clientName: 'Marcus Reed');

/// The Session Coach keeps each client's own plan (on this phone): it is
/// saved when a set goes on a unit, comes back for the same client, body
/// part and goal, and Game Prep's START reopens it at placement.
void main() {
  late ProviderContainer container;
  late List<String> calls;

  Future<void> pump(
    WidgetTester tester, {
    Client? client = _jalen,
    ClientMode mode = ClientMode.client,
    String? restore,
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    calls = [];
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      authStateProvider.overrideWith((ref) => _Auth()),
      coachBodyPartsProvider.overrideWith(
          (ref) async => const [CoachBodyPart(id: 'b1', name: 'Knee')]),
      sessionCoachesByBodyPartProvider.overrideWith((ref, id) async => [_knee]),
      protocolDetailProvider
          .overrideWith((ref, id) => Completer<Protocol>().future),
    ]);
    addTearDown(container.dispose);
    container.read(sessionClientModeProvider.notifier).state = mode;
    container.read(selectedClientProvider.notifier).state = client;
    if (restore != null) {
      container.read(coachRestoreRequestProvider.notifier).state = restore;
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      key: UniqueKey(), // a fresh card each pump, like reopening the screen
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SessionCoachCard(
              units: const [
                CoachUnit(id: 'u1', name: 'Unit 1'),
                CoachUnit(id: 'u2', name: 'Unit 2'),
              ],
              onApply: (d, p) async {
                calls.add('apply $d $p');
                return true;
              },
              onSetDelay: (d, s) => calls.add('delay $d ${s}s'),
              onLocate: (_) {},
              bodyBuilder: (_) => const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> toSets(WidgetTester tester) async {
    await tap(tester, find.text('Session coach'));
    await tap(tester, find.text('Knee'));
    await tap(tester, find.text('Support recovery'));
  }

  /// Plans Jalen's knee: set 2 on Unit 2 at +5 s, both sets put on.
  Future<void> planJalen(WidgetTester tester) async {
    await toSets(tester);
    for (var k = 0; k < 5; k++) {
      await tap(tester, find.text('+')); // set 2 at 0:05
    }
    await tap(tester, find.text('Use this set  →'));
    await tap(tester, find.text('Use this set  →'));
  }

  CoachPlanRecord? saved(String client) =>
      container.read(coachPlanStoreProvider).load('493', client);

  testWidgets('putting a set on a unit saves it as the client\'s plan',
      (tester) async {
    await pump(tester);
    await planJalen(tester);
    final plan = saved('jalen');
    expect(plan, isNotNull);
    expect(plan!.bodyPartName, 'Knee');
    expect(plan.goal, 'Support recovery');
    expect([for (final s in plan.sets) (s.unitId, s.protocolId, s.startAt)], [
      ('u1', 'p1', 0),
      ('u2', 'p1', 5),
    ]);
    expect(saved('marcus'), isNull);
  });

  testWidgets('a guest has nothing to file a plan under', (tester) async {
    await pump(tester, client: null, mode: ClientMode.guest);
    await planJalen(tester);
    expect(saved('jalen'), isNull);
  });

  testWidgets('the same client, body part and goal brings their delays back',
      (tester) async {
    await pump(tester);
    await planJalen(tester);
    final stored = Map<String, Object>.from({
      'coach_client_plans_v1':
          (await SharedPreferences.getInstance()).getString('coach_client_plans_v1')!,
    });
    await pump(tester, prefs: stored);
    await toSets(tester);
    expect(find.text('+5s', findRichText: true), findsOneWidget);
    expect(find.text('2nd \u00b7 starts 0:05'), findsOneWidget);
  });

  testWidgets('Game Prep START reopens the last plan at placement',
      (tester) async {
    await pump(tester);
    await planJalen(tester);
    final stored = <String, Object>{
      'coach_client_plans_v1': (await SharedPreferences.getInstance())
          .getString('coach_client_plans_v1')!,
    };
    await pump(tester, prefs: stored, restore: 'jalen');
    expect(find.text('STEP 3 OF 3 · PLACEMENT'), findsOneWidget);
    expect(find.text('Loaded their last setup — change anything'),
        findsOneWidget);
    expect(find.text('+5s', findRichText: true), findsOneWidget);
    // last time's units are suggested, not yet put on
    expect(calls, isEmpty);
    expect(container.read(coachRestoreRequestProvider), isNull);
  });

  testWidgets('START with no saved plan opens the ordinary first step',
      (tester) async {
    await pump(tester, restore: 'jalen');
    expect(find.text('STEP 3 OF 3 · PLACEMENT'), findsNothing);
    expect(find.text('Session coach'), findsOneWidget);
    expect(container.read(coachRestoreRequestProvider), isNull);
  });

  testWidgets('switching client starts the coach over', (tester) async {
    await pump(tester);
    await toSets(tester);
    await tap(tester, find.text('+'));
    expect(find.text('+1s', findRichText: true), findsOneWidget);
    container.read(selectedClientProvider.notifier).state = _marcus;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // step fade-out
    expect(find.text('STEP 3 OF 3 · PLACEMENT'), findsNothing);
    expect(find.text('+1s', findRichText: true), findsNothing);
  });
}
