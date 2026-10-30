import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/payments/data/payment_repository.dart';
import 'package:hydrawav3/features/payments/data/store_region.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/settings/presentation/screens/subscription_screen.dart';

class _FakeTokens extends StateNotifier<double?>
    implements TokenBalanceNotifier {
  _FakeTokens() : super(12);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth() : super(const AuthState(isAuthenticated: true, isInitialized: true));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Plan & usage: only US-storefront users get the "Buy tokens" card; every
/// other country keeps the information-only screen unchanged.
void main() {
  Future<void> pump(WidgetTester tester, String? country) async {
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        storeCountryProvider.overrideWith((ref) async => country),
        authStateProvider.overrideWith((ref) => _FakeAuth()),
        tokenBalanceProvider.overrideWith((ref) => _FakeTokens()),
        currentPlanProvider.overrideWith((ref) async => null),
        planTokenGrantProvider.overrideWith((ref) async => null),
        subscriptionProductsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: SubscriptionScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final c in ['US', 'USA']) {
    testWidgets('US storefront ($c) shows Buy tokens', (tester) async {
      await pump(tester, c);
      expect(find.text('Buy tokens or change plan'), findsOneWidget);
    });
  }

  for (final c in ['IN', 'GBR', null]) {
    testWidgets('$c storefront keeps the screen unchanged', (tester) async {
      await pump(tester, c);
      expect(find.text('Buy tokens or change plan'), findsNothing);
      expect(find.text('Plan & usage'), findsOneWidget);
    });
  }
}
