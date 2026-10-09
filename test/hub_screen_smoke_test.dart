import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/core/theme/widgets/hw_tablet.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/home/presentation/providers/hub_prefs_provider.dart';
import 'package:hydrawav3/features/home/presentation/widgets/hub_modules.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';

/// Guards a real regression that shipped a blank Hub.
///
/// The Hub's side-by-side tiles use `Row(crossAxisAlignment: stretch)` so
/// paired cards match height. Inside a scroll view that asks for infinite
/// height unless the row is bounded (`IntrinsicHeight`), and the failure mode
/// is brutal: the assertion aborts the entire sliver, so the whole screen
/// renders empty rather than just the offending row.
///
/// `flutter analyze`, `flutter test` and a full release build all pass with
/// that bug present — only laying the widget out catches it. Every Hub module
/// at every size belongs in this test.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Lays [child] out under genuinely unbounded height, which is what a
  /// CustomScrollView gives its slivers.
  Future<void> pumpInScrollView(WidgetTester tester, Widget child) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Stub the network and Bluetooth reads these modules touch, so the
          // test stays about layout and spins up no Dio clients, BLE stack or
          // polling timers.
          allSessionsProvider.overrideWith((ref) async => []),
          clientListProvider.overrideWith((ref) async => []),
          protocolListProvider.overrideWith((ref) async => []),
          hubPairedDevicesProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(padding: EdgeInsets.zero, children: [child]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  for (final module in HubModule.values) {
    for (final size in HubSize.values) {
      testWidgets('${module.name} lays out at ${size.name}', (tester) async {
        await pumpInScrollView(tester, HubModuleView(module, size));
        expect(tester.takeException(), isNull);
        // Every size carries the module's name — as the embedded heading, or
        // as the label above a compact row.
        final label = kHubModuleMeta[module]!.label;
        expect(
          find.text(size == HubSize.small ? label.toUpperCase() : label),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Quick Start with no units says so and cannot start',
      (tester) async {
    await pumpInScrollView(
        tester, const HubModuleView(HubModule.quick, HubSize.large));
    expect(find.text('0 connected · 0 selected · Guest'), findsOneWidget);
    expect(find.text('No units connected. '), findsOneWidget);
    expect(find.text('Start Now'), findsOneWidget);
    // Nothing armed → the button is dimmed, not live.
    final dims = find
        .ancestor(of: find.text('Start Now'), matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity);
    expect(dims.any((o) => o < 1), isTrue);
  });

  testWidgets('Usage renders honest empties, not placeholders',
      (tester) async {
    await pumpInScrollView(
        tester, const HubModuleView(HubModule.usage, HubSize.large));
    expect(tester.takeException(), isNull);
    // No checks yet → an em-dash score and the empty graph, never 0%.
    expect(find.textContaining('No post-session check-ins in the last 7 days'),
        findsOneWidget);
    expect(find.text('Scores appear after post-session checks'),
        findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('no sessions yet'), findsOneWidget);
  });

  testWidgets('Usage scores real checks and draws the graph', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    SessionHistoryItem session(int daysAgo, int rank) => SessionHistoryItem(
          createdAt: now.subtract(Duration(days: daysAgo)),
          protocols: [
            HistoryProtocol(
              protocol: 'Deep-Tension Recovery',
              duration: 1800,
              questionAnswers: [
                HistoryQuestionAnswer(question: 'q', answer: 'a', rank: rank),
              ],
            ),
          ],
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // 3 of 4 checks this week came back good; one 40 days ago did not.
          allSessionsProvider.overrideWith((ref) async => [
                session(0, 5),
                session(1, 4),
                session(3, 2),
                session(5, 5),
                session(40, 1),
              ]),
          clientListProvider.overrideWith((ref) async => []),
          protocolListProvider.overrideWith((ref) async => []),
          hubPairedDevicesProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HubModuleView(HubModule.usage, HubSize.large),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    // Says what the number is made of.
    expect(
        find.text('3 of 4 post-session check-ins said the session helped · '
            'last 7 days', findRichText: true),
        findsOneWidget);
    expect(find.text('Score by day'), findsOneWidget);
    expect(find.text('75'), findsOneWidget); // the counted-up score
    // ALL includes the older miss: 3 of 5.
    expect(find.textContaining('60%'), findsOneWidget);
    expect(find.text('Scores appear after post-session checks'), findsNothing);
    // 5 sessions x 30 min.
    expect(find.text('2.5 h', findRichText: true), findsOneWidget);
    expect(find.text('Deep-Tension Recovery'), findsOneWidget);

    // Switching the window re-scores and redraws.
    await tester.tap(find.textContaining('All time'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(
        find.text('3 of 5 post-session check-ins said the session helped · '
            'all time', findRichText: true),
        findsOneWidget);
    expect(find.text('Score by month'), findsOneWidget);
  });

  testWidgets('Support Recovery offers the four pathways', (tester) async {
    await pumpInScrollView(
        tester, const HubModuleView(HubModule.recovery, HubSize.large));
    for (final label in [
      'Discomfort',
      'Joint Mobility',
      'Post-Workout',
      'Lymphatic',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('the recovery tiles share rows on the narrowest phone',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpInScrollView(
        tester, const HubModuleView(HubModule.recovery, HubSize.large));
    expect(tester.takeException(), isNull);

    double y(String t) =>
        tester.renderObject<RenderBox>(find.text(t)).localToGlobal(Offset.zero).dy;
    // 2 x 2: the pairs sit on the same line, the rows stack.
    expect((y('Discomfort') - y('Joint Mobility')).abs(), lessThan(2));
    expect((y('Post-Workout') - y('Lymphatic')).abs(), lessThan(2));
    expect(y('Post-Workout'), greaterThan(y('Discomfort')));
  });
  Future<void> pumpWith(
    WidgetTester tester,
    Widget child, {
    List<SessionHistoryItem> sessions = const [],
    List<Client> clients = const [],
    List<Protocol> protocols = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          allSessionsProvider.overrideWith((ref) async => sessions),
          clientListProvider.overrideWith((ref) async => clients),
          protocolListProvider.overrideWith((ref) async => protocols),
          hubPairedDevicesProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(padding: EdgeInsets.zero, children: [child]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('Game Prep counts who is prepped and leads with the longest wait',
      (tester) async {
    final now = DateTime.now();
    Client player(String id, String name) => Client(
        id: id, clientName: name, memberType: 'Player', sport: 'Football');
    await pumpWith(
      tester,
      const HubModuleView(HubModule.gameprep, HubSize.large),
      clients: [
        player('a', 'Grant Owens'),
        player('b', 'Luke Park'),
        player('c', 'Maya Reid'),
        const Client(id: 'x', clientName: 'Clinic Client'),
      ],
      sessions: [
        SessionHistoryItem(clientId: 'a', createdAt: now),
        SessionHistoryItem(
            clientId: 'b', createdAt: now.subtract(const Duration(days: 3))),
      ],
    );
    expect(tester.takeException(), isNull);
    // Only players count; Grant ran today.
    expect(find.text('of 3 prepped today'), findsOneWidget);
    expect(find.text('2 to go · 33% of the squad ready'), findsOneWidget);
    // Maya has never had a session, so she is up next, ahead of Luke.
    expect(find.text('UP NEXT'), findsOneWidget);
    final maya = tester.getTopLeft(find.text('Maya')).dx;
    final luke = tester.getTopLeft(find.text('Luke')).dx;
    expect(maya, lessThan(luke));
    expect(find.text('3 DAYS SINCE LAST'), findsOneWidget);
    expect(find.text('Grant'), findsNothing); // prepped, so not in "To prep"

    // Game day switches on from the widget.
    await tester.tap(find.text('Start game day'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Game day on'), findsOneWidget);
  });

  testWidgets('Learn leads with the default stack, starred, and shows more',
      (tester) async {
    const protocols = [
      Protocol(id: 's1', templateName: 'Hot Pack', description: 'Warm'),
      Protocol(id: 's2', templateName: 'Energizing', description: 'Uplifting'),
      Protocol(
        id: 'p1',
        templateName: 'Movement Preparation',
        isProtocolPlus: true,
        protocolPlusIds: ['s1', 's2'],
        description: 'Ends long instead of hot.',
      ),
      Protocol(
        id: 'p2',
        templateName: 'Performance Activation',
        isProtocolPlus: true,
        protocolPlusIds: ['s1', 's2'],
        description: 'The pre-game anchor: comforting warmth opens the '
            'tissue and an energizing finish leaves the body ready.',
      ),
    ];
    await pumpWith(
      tester,
      const HubModuleView(HubModule.learn, HubSize.large),
      protocols: protocols,
      prefs: {'hub_default_protocol_id': 'p2'},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Performance Activation ★'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Hot Pack → Energizing'), findsOneWidget);
    // Details stay closed until asked for, then show in full.
    expect(find.textContaining('The pre-game anchor'), findsNothing);
    await tester.tap(find.text('Show more'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('The pre-game anchor'), findsOneWidget);
    expect(find.text('1. Hot Pack  Warm', findRichText: true), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    // Next slide keeps the details open and is not starred.
    await tester.tap(find.bySemanticsLabel('Next protocol'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Movement Preparation'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('a very long most-used protocol name wraps, never overflows',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const long = 'Deep-Tension Recovery with Lymphatic Activation · Lower '
        'Back and Hamstrings Plus Extended Cool Down';
    await pumpWith(
      tester,
      const HubModuleView(HubModule.usage, HubSize.large),
      sessions: [
        SessionHistoryItem(
          createdAt: DateTime.now(),
          protocols: const [HistoryProtocol(protocol: long, duration: 600)],
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    final t = tester.widget<Text>(find.text(long));
    expect(t.maxLines, 3);
    expect(t.overflow, TextOverflow.ellipsis);
  });
  testWidgets('the tablet board lays out every module side by side',
      (tester) async {
    // An 11" iPad in portrait. On a tablet the Hub is an auto-fit grid, and
    // Game Prep's player cards wrap instead of scrolling — a layout a phone
    // never builds, so it gets its own guard.
    tester.view.physicalSize = const Size(834 * 2, 2400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final players = [
      for (final n in ['Grant Owens', 'Luke Park', 'Maya Reid', 'Ava Cole'])
        Client(id: n, clientName: n, memberType: 'Player', sport: 'Football'),
    ];
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        allSessionsProvider.overrideWith((ref) async => []),
        clientListProvider.overrideWith((ref) async => players),
        protocolListProvider.overrideWith((ref) async => []),
        hubPairedDevicesProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            expect(HwTablet.of(context), isTrue);
            final pad = HwTablet.sidePadding(context);
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: pad),
              children: [
                HwAutoGrid(
                  fullWidth: const {0},
                  children: [
                    for (final m in HubModule.values)
                      HubModuleView(m, HubSize.large),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);

    // Two columns: Support Recovery and Athlete Readiness share a row, and
    // Quick Start spans above them.
    double top(String t) => tester.getTopLeft(find.text(t)).dy;
    double left(String t) => tester.getTopLeft(find.text(t)).dx;
    expect((top('Support Recovery') - top('Athlete Readiness & Performance'))
        .abs(), lessThan(2));
    expect(left('Athlete Readiness & Performance'),
        greaterThan(left('Support Recovery') + 300));
    expect(top('Quick Start'), lessThan(top('Support Recovery')));
    // The player cards wrap onto rows rather than a sideways rail.
    expect(find.text('START'), findsNWidgets(players.length));
  });
}
