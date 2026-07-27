import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/payments/domain/plan_model.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/payments/presentation/widgets/token_balance_badge.dart';

/// The top-bar badge names the plan. A raw credit count must never appear
/// there — the balance and usage belong in the plan sheet behind it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpBadge(WidgetTester tester, SubscriptionPlan? plan) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentPlanProvider.overrideWith((ref) async => plan),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: TokenBalanceBadge())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('badges a package plan as Enterprise, not by product name',
      (tester) async {
    // "Pro+" is the product; "Enterprise" is the category the pill shows.
    await pumpBadge(
      tester,
      const SubscriptionPlan(
        name: 'Pro+',
        status: 'active',
        remainingTokens: 1234,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Enterprise'), findsOneWidget);
    expect(find.text('Pro+'), findsNothing);
    // The balance is present in state but must not be on the badge.
    expect(find.textContaining('1234'), findsNothing);
  });

  testWidgets('any custom package name still badges as Enterprise',
      (tester) async {
    await pumpBadge(
      tester,
      const SubscriptionPlan(name: 'Pro Team', status: 'active'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Enterprise'), findsOneWidget);
    expect(find.text('Pro Team'), findsNothing);
  });

  testWidgets('names a Free plan rather than showing its credits',
      (tester) async {
    await pumpBadge(
      tester,
      const SubscriptionPlan(name: 'Free', remainingTokens: 46),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Free'), findsOneWidget);
    expect(find.textContaining('46'), findsNothing);
  });

  testWidgets('stays hidden until a plan is known', (tester) async {
    await pumpBadge(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.byType(Text), findsNothing);
  });
}
