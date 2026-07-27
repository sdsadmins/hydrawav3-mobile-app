import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/core/theme/widgets/hw_primitives.dart';
import 'package:hydrawav3/features/payments/domain/plan_model.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/payments/presentation/widgets/token_details_sheet.dart';

/// The token badge opens the UI spec's `tokenSheet()` (app.js:2245): an
/// Enterprise package billed in session hours, or a pay-as-you-go credit
/// balance.
///
/// The usage bars measure against the product's `aiCredit` — the tokens granted
/// per period, which is what seeds `remainingTokens` server-side
/// (payment.service.ts:174). Session time and AI reports are both derived from
/// that same pool, so all the gauges share one fraction.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSheet(
    WidgetTester tester,
    SubscriptionPlan? plan, {
    double? grant,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentPlanProvider.overrideWith((ref) async => plan),
          planTokenGrantProvider.overrideWith((ref) async => grant),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTokenDetailsSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Enterprise draws both usage bars against the token grant',
      (tester) async {
    // 250 of a 1000-token grant left → 25% remaining on every gauge.
    await pumpSheet(
      tester,
      const SubscriptionPlan(
        name: 'Pro Team',
        status: 'active',
        remainingTokens: 250,
        sessionDurationSeconds: 36000, // 10 h left → 40 h granted
        aiReportsAvailable: 25, // → 100 granted
        deviceLimit: 6,
      ),
      grant: 1000,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Pro Team · Enterprise'), findsOneWidget);
    expect(find.text('Session time left'), findsOneWidget);
    expect(find.text('10 h'), findsOneWidget);
    expect(find.text('30 of 40 device-hours used · 6 units'), findsOneWidget);
    expect(find.text('Full Mobility Reports left'), findsOneWidget);
    expect(find.text('75 of 100 AI reports used this period'), findsOneWidget);
    expect(find.text('Full plan & usage'), findsOneWidget);

    expect(find.byType(HwBar), findsNWidgets(2));
    expect(find.text('Session credits'), findsNothing);
  });

  testWidgets('Enterprise omits the bars when the grant is unknown',
      (tester) async {
    await pumpSheet(
      tester,
      const SubscriptionPlan(
        name: 'Pro Team',
        remainingTokens: 250,
        sessionDurationSeconds: 36000,
        aiReportsAvailable: 25,
        deviceLimit: 6,
      ),
      // No product resolved → no allowance.
    );

    expect(tester.takeException(), isNull);
    expect(find.text('10 h'), findsOneWidget);
    // Never a fabricated denominator.
    expect(find.byType(HwBar), findsNothing);
    expect(find.textContaining('device-hours used'), findsNothing);
  });

  testWidgets('pay-as-you-go shows the balance, grant and bar', (tester) async {
    await pumpSheet(
      tester,
      const SubscriptionPlan(name: 'Free', remainingTokens: 46),
      grant: 60,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Session credits'), findsOneWidget);
    expect(find.text('46'), findsOneWidget);
    expect(find.text('of 60 this month · 1 credit ≈ one ~9-min session'),
        findsOneWidget);
    expect(find.byType(HwBar), findsOneWidget);
    expect(find.text('Top up credits'), findsOneWidget);
    expect(find.text('Session time left'), findsNothing);
  });

  testWidgets('pay-as-you-go drops the total when no grant is known',
      (tester) async {
    await pumpSheet(
      tester,
      const SubscriptionPlan(name: 'Free', remainingTokens: 42),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('1 credit ≈ one ~9-min session'), findsOneWidget);
    expect(find.byType(HwBar), findsNothing);
  });

  testWidgets('an unknown balance renders an em-dash, not a zero',
      (tester) async {
    await pumpSheet(tester, const SubscriptionPlan(name: 'Free'));

    expect(tester.takeException(), isNull);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  group('grant maths', () {
    const plan = SubscriptionPlan(
      name: 'Pro',
      remainingTokens: 250,
      sessionDurationSeconds: 36000,
      aiReportsAvailable: 25,
    );

    test('one pool drives one fraction', () {
      expect(plan.fractionOfGrant(1000), 0.25);
    });

    test('remaining units scale back up to the period total', () {
      expect(plan.totalForGrant(36000, 1000), 144000); // 40 h
      expect(plan.totalForGrant(25, 1000), 100);
    });

    test('an unknown or empty grant yields nothing rather than a divide', () {
      expect(plan.fractionOfGrant(null), isNull);
      expect(plan.fractionOfGrant(0), isNull);
      expect(plan.totalForGrant(25, null), isNull);
      expect(
        const SubscriptionPlan(name: 'Pro', remainingTokens: 0)
            .totalForGrant(25, 1000),
        isNull,
      );
    });

    test('productId is read from the plan response', () {
      final p = SubscriptionPlan.fromJson(const {
        'planName': 'Pro',
        'productId': 'prod_123',
      });
      expect(p.productId, 'prod_123');
    });

    test('aiCredit is read from the product response', () {
      final p = Product.fromJson(const {
        '_id': 'prod_123',
        'name': 'Pro',
        'aiCredit': 1000,
      });
      expect(p.id, 'prod_123');
      expect(p.aiCredit, 1000);
    });
  });
}
