import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/home/presentation/providers/hub_prefs_provider.dart';
import 'package:hydrawav3/features/home/presentation/providers/hub_stats_provider.dart';
import 'package:hydrawav3/features/home/presentation/widgets/hub_modules.dart';

/// Game day is a date, and the board says how many were activated on it
/// (prototype C0-gameday).
void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9, 30);
  final lastGame = today.subtract(const Duration(days: 3));
  String key(DateTime d) => GameDayNotifier.dayKey(d);

  GamePrepRow row(String id, int i, List<DateTime> ran) {
    final history = [
      for (final t in ran)
        SessionHistoryItem(id: '$id-$t', clientId: id, createdAt: t),
    ];
    final ranToday = ran.any((t) =>
        t.year == today.year && t.month == today.month && t.day == today.day);
    return GamePrepRow(
      client: Client(id: id, clientName: 'Player $id'),
      index: i,
      today: ranToday ? history.first : null,
      last: history.isEmpty ? null : history.first,
      history: history,
    );
  }

  // 3 players: a ran today, b ran on the last game day, c never.
  GamePrepData data() {
    final a = row('a', 0, [today]);
    final b = row('b', 1, [lastGame]);
    final c = row('c', 2, const []);
    return GamePrepData(prepped: [a], left: [b, c]);
  }

  Future<ProviderContainer> pump(WidgetTester tester,
      {required Map<String, Object> prefs}) async {
    tester.view.physicalSize = const Size(390, 1400) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      gamePrepProvider.overrideWith((ref, team) => AsyncValue.data(data())),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: HubGamePrep(HubSize.large)),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    return container;
  }

  /// Unmounts and disposes, so game day's midnight timer is cancelled
  /// before the test checks for pending timers.
  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  final fmt = DateFormat('EEEE, MMM d');

  testWidgets('no game day yet: no line', (tester) async {
    final c = await pump(tester, prefs: {});
    expect(find.text('Game day'), findsNothing);
    expect(find.text('Last game day'), findsNothing);
    await done(tester, c);
  });

  testWidgets('game day on: today and the last one, with counts',
      (tester) async {
    final c = await pump(tester, prefs: {
      'hub_game_day_on': '${now.year}-${now.month}-${now.day}',
      GameDayNotifier.historyKey: [key(lastGame), key(today)],
    });
    expect(find.text('Game day'), findsOneWidget);
    expect(find.text(fmt.format(today)), findsOneWidget);
    expect(find.text('1 of 3 activated'), findsNWidgets(2));
    expect(find.text('Last game day'), findsOneWidget);
    expect(find.text(fmt.format(lastGame)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester, c);
  });

  testWidgets('the switch from an earlier day is off; its record stays',
      (tester) async {
    final c = await pump(tester, prefs: {
      'hub_game_day_on':
          '${lastGame.year}-${lastGame.month}-${lastGame.day}',
      GameDayNotifier.historyKey: [key(lastGame)],
    });
    expect(find.text('Game day'), findsNothing);
    expect(find.text('Last game day'), findsOneWidget);
    expect(find.text('1 of 3 activated'), findsOneWidget);
    await done(tester, c);
  });

  test('turning game day on records the date once', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
    addTearDown(c.dispose);
    expect(c.read(gameDaysProvider), isEmpty);
    await c.read(gameDayActiveProvider.notifier).activate();
    await c.read(gameDayActiveProvider.notifier).end();
    await c.read(gameDayActiveProvider.notifier).activate();
    expect(sp.getStringList(GameDayNotifier.historyKey),
        [key(DateTime.now())]);
    expect(c.read(gameDaysProvider).length, 1);
  });
}
