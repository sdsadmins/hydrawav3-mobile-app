import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hydrawav3/features/payments/data/store_region.dart';
import 'package:hydrawav3/features/payments/presentation/widgets/plan_locked_sheet.dart';

/// Tapping a locked protocol: US storefront gets "Upgrade your plan" with the
/// website link-out; every other country gets information only — no
/// upgrade/buy wording at all (App Store 3.1.1).
void main() {
  Future<void> open(WidgetTester tester, String? country) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showPlanLockedSheet(c,
                  protocolName: 'Deep-Tension Recovery'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/settings/subscription',
        builder: (c, s) => const Scaffold(body: Text('PLAN SCREEN')),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [storeCountryProvider.overrideWith((ref) async => country)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    // Let the store-country future settle before the sheet reads it.
    final container =
        ProviderScope.containerOf(tester.element(find.text('open')));
    await container.read(storeCountryProvider.future);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final c in ['US', 'USA']) {
    testWidgets('$c: Upgrade your plan + website button', (tester) async {
      await open(tester, c);
      expect(find.text('Upgrade your plan'), findsOneWidget);
      expect(find.text('Upgrade plan'), findsOneWidget);
      expect(find.textContaining('Deep-Tension Recovery'), findsOneWidget);
    });
  }

  for (final c in ['IN', 'GBR', null]) {
    testWidgets('$c: information only, no upgrade wording', (tester) async {
      await open(tester, c);
      expect(find.text('Not in your plan'), findsOneWidget);
      expect(find.textContaining('Upgrade'), findsNothing);
      expect(find.textContaining('Buy'), findsNothing);
      expect(find.textContaining('website'), findsNothing);
      await tester.tap(find.text('View plan & usage'));
      await tester.pumpAndSettle();
      expect(find.text('PLAN SCREEN'), findsOneWidget);
    });
  }
}
