import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/home/presentation/widgets/hub_modules.dart';

/// Guards a real regression that shipped a blank Hub.
///
/// The Hub's side-by-side modules use `Row(crossAxisAlignment: stretch)` so
/// paired cards match height. Inside a scroll view that asks for infinite
/// height unless the row is bounded (`IntrinsicHeight`), and the failure mode
/// is brutal: the assertion aborts the entire sliver, so the whole screen
/// renders empty rather than just the offending row.
///
/// `flutter analyze`, `flutter test` and a full release build all pass with
/// that bug present — only laying the widget out catches it. Any new 2-up row
/// on the Hub belongs in this test.
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
          // Stub the two network reads these modules touch, so the test stays
          // about layout and spins up no Dio clients or polling timers.
          allSessionsProvider.overrideWith((ref) async => []),
          clientListProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(padding: EdgeInsets.zero, children: [child]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('HubTiles lays out in a scroll view', (tester) async {
    await pumpInScrollView(tester, const HubTiles());
    expect(tester.takeException(), isNull);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Recovery'), findsOneWidget);
  });

  testWidgets('HubQuickPulse lays out in a scroll view', (tester) async {
    await pumpInScrollView(tester, const HubQuickPulse());
    expect(tester.takeException(), isNull);
    expect(find.text('Quick Start'), findsOneWidget);
    expect(find.text('Outcome Pulse'), findsOneWidget);
    // With no history, the Pulse states that rather than showing a number.
    expect(
        find.text('First checks land after your next session.'), findsOneWidget);
  });

  testWidgets('HubResources renders the spec\'s four tiles, row and card',
      (tester) async {
    await pumpInScrollView(tester, const HubResources());
    expect(tester.takeException(), isNull);

    // The 2x2 grid, in the spec's order.
    expect(find.text('Learn about protocols'), findsOneWidget);
    expect(find.text('Call customer support'), findsOneWidget);
    expect(find.text('Business resources'), findsOneWidget);
    expect(find.text('Buy more products'), findsOneWidget);

    // Rental Economics is a full-width row beneath the grid, with the spec's
    // longer subtitle — not a fifth tile.
    expect(find.text('Rental Economics'), findsOneWidget);
    expect(
      find.text('The numbers behind renting units — payback, margins & ROI · '
          'hydrawav3.com/economics'),
      findsOneWidget,
    );

    // Rent & Earn closes the section.
    expect(find.text('PASSIVE INCOME'), findsOneWidget);
    expect(find.text('Send a unit home. Earn while they recover.'),
        findsOneWidget);
    expect(find.textContaining('Your unit earns even while you sleep.'),
        findsOneWidget);
    // No active leases in this harness, so no count is appended.
    expect(find.text('Start earning · Rent & Earn'), findsOneWidget);
  });

  testWidgets('HubWeek renders honest zeros, not placeholders',
      (tester) async {
    await pumpInScrollView(tester, const HubWeek());
    expect(tester.takeException(), isNull);
    expect(find.text('measured, not estimated'), findsOneWidget);
    // No sessions logged → the Outcome Pulse legend reads em-dash, never 0%.
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('HubLastSession renders nothing when there is no history',
      (tester) async {
    await pumpInScrollView(tester, const HubLastSession());
    expect(tester.takeException(), isNull);
    expect(find.text('Last session'), findsNothing);
  });

  testWidgets('HubLabsCard is on the Hub by default', (tester) async {
    // The More → Labs toggle governs the readiness offer *before sessions*
    // (app.js:3856, 3870). It does not gate this card, which is the pitch for
    // the experiment and always rides on the Hub.
    await pumpInScrollView(tester, const HubLabsCard());

    expect(tester.takeException(), isNull);
    expect(find.text('LABS · A FIRST, FOR MOST PEOPLE'), findsOneWidget);
    expect(find.text('Ever measured your readiness from your own breath?'),
        findsOneWidget);
    // Both actions, per the spec's two-button row.
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('▶ Try the experiment'), findsOneWidget);
  });

  testWidgets('the Labs buttons share one line, neither truncated',
      (tester) async {
    // Narrowest phone we support. Both labels must render in full, on one
    // line each, at equal height — the 1 : 1.3 split has to leave the ghost
    // button enough room.
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpInScrollView(tester, const HubLabsCard());
    expect(tester.takeException(), isNull);

    final ghost = tester.renderObject<RenderBox>(find.text('How it works'));
    final primary =
        tester.renderObject<RenderBox>(find.text('▶ Try the experiment'));

    // One line each: a wrapped label would be ~2x this height.
    expect(ghost.size.height, lessThan(24));
    expect(primary.size.height, lessThan(24));

    // Side by side on the same row, not stacked.
    final ghostY = ghost.localToGlobal(Offset.zero).dy;
    final primaryY = primary.localToGlobal(Offset.zero).dy;
    expect((ghostY - primaryY).abs(), lessThan(2));

    // And nothing was ellipsised away.
    for (final t in [
      tester.widget<Text>(find.text('How it works')),
      tester.widget<Text>(find.text('▶ Try the experiment')),
    ]) {
      expect(t.overflow, TextOverflow.ellipsis);
    }
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('the Labs card explains itself before sending you off',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: Scaffold(body: HubLabsCard()),
        ),
      ),
    );
    await tester.tap(find.text('How it works'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Readiness from breath — how it works'), findsOneWidget);
    expect(find.text('Lie down, phone on your belly'), findsOneWidget);
    expect(find.text('Your breath becomes numbers'), findsOneWidget);
    expect(find.text('See your Readiness score'), findsOneWidget);
  });
}
