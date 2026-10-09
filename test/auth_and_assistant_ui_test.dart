import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/assistant/presentation/widgets/assistant_welcome_panel.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/login_screen.dart';
import 'package:hydrawav3/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/home/presentation/widgets/hub_modules.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/splash/presentation/screens/splash_screen.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth({String orgType = 'CLINIC'})
      : super(AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          user: UserProfile(
            id: '7',
            firstName: 'Marcus',
            lastName: 'Ellison',
            organizationType: orgType,
          ),
        ));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTokens extends StateNotifier<double?>
    implements TokenBalanceNotifier {
  _FakeTokens(super.v);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The v6 sign-in family (splash, login, organization picker, onboarding)
/// and the Assistant's opening panel lay out on phone and tablet, show the
/// prototype's structure, and keep their existing behaviour.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> sized(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  for (final size in [const Size(320, 760), const Size(834, 1112)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('login: v6 card, same logo + BETA, same checks ($tag)',
        (tester) async {
      await sized(tester, size);
      await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: LoginScreen())));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('BETA'), findsOneWidget);
      expect(find.text('Practitioner sign in'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Forgot password'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Required'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('organization picker and create form ($tag)', (tester) async {
      await sized(tester, size);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _FakeAuth()),
          organizationProvider.overrideWith((ref) async => [
                {'id': 1, 'name': 'Gulf Coast Tarpons', 'address': 'Tampa, FL'},
                {'id': 2, 'name': 'Northgate Ironworks'},
              ]),
        ],
        child: const MaterialApp(home: SelectOrganizationPage()),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('SELECT ORGANIZATION'), findsOneWidget);
      expect(find.text('Gulf Coast Tarpons'), findsOneWidget);
      expect(find.text('Tampa, FL'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(ProviderScope(
        key: const ValueKey('empty'),
        overrides: [
          authStateProvider.overrideWith((ref) => _FakeAuth()),
          organizationProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: SelectOrganizationPage()),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('CREATE YOUR ORGANIZATION'), findsOneWidget);
      await tester.ensureVisible(find.text('Create organization'));
      await tester.tap(find.text('Create organization'));
      await tester.pump();
      expect(find.text('Organization name is required.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onboarding: heading and step line ($tag)', (tester) async {
      await sized(tester, size);
      await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: OnboardingScreen())));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('PRACTITIONER ONBOARDING'), findsOneWidget);
      expect(find.text('Step 1 of 4 · Practitioner'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('splash shows the tagline and releases after its minimum',
      (tester) async {
    late WidgetRef wref;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          wref = ref;
          return const SplashScreen();
        }),
      ),
    ));
    await tester.pump();
    expect(find.text('Performance-First. Recovery-Next.'), findsOneWidget);
    expect(wref.read(splashHoldProvider), isTrue);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(wref.read(splashHoldProvider), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  Future<List<String>> pumpPanel(WidgetTester tester,
      {required bool university, Size size = const Size(390, 1400)}) async {
    final prefs = await SharedPreferences.getInstance();
    final taps = <String>[];
    final today = DateTime.now();
    await sized(tester, size);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStateProvider.overrideWith((ref) =>
            _FakeAuth(orgType: university ? 'UNIVERSITY' : 'CLINIC')),
        tokenBalanceProvider.overrideWith((ref) => _FakeTokens(27.5)),
        clientListProvider.overrideWith((ref) async => const [
              Client(id: 'c1', clientName: 'Malik Carter'),
              Client(id: 'c2', clientName: 'Jaylen Brooks'),
            ]),
        allSessionsProvider.overrideWith((ref) async => [
              SessionHistoryItem(
                id: 's1',
                clientId: 'c1',
                clientType: 'client',
                createdAt: today,
                protocols: const [
                  HistoryProtocol(protocol: 'Performance Activation'),
                ],
              ),
              SessionHistoryItem(
                id: 's0',
                clientType: 'guest',
                createdAt: today,
              ),
            ]),
        protocolListProvider.overrideWith((ref) async => []),
        hubPairedDevicesProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AssistantWelcomePanel(
              university: university,
              onPrepUser: () => taps.add('prep'),
              onRecovery: () => taps.add('recovery'),
              onFindPads: () => taps.add('pads'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    return taps;
  }

  testWidgets('assistant panel: greeting, real numbers, pick up, tiles',
      (tester) async {
    final taps = await pumpPanel(tester, university: false);
    expect(find.textContaining('Marcus', findRichText: true), findsOneWidget);
    expect(find.textContaining('2 sessions today', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('27.5 credits left', findRichText: true),
        findsOneWidget);
    expect(find.text('▶  Start a session'), findsOneWidget);
    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsOneWidget);
    expect(find.text('Malik Carter'), findsOneWidget);
    expect(find.text('Performance Activation · today'), findsOneWidget);
    expect(find.text('Jaylen Brooks'), findsNothing);
    // Clinic: all six tiles; the squad two are placeholders.
    expect(find.text('Prep the squad'), findsOneWidget);
    expect(find.text('Game Ready board'), findsOneWidget);
    expect(find.text('Teams'), findsNWidgets(2));
    await tester.tap(find.text('Prep the squad'));
    await tester.pump();
    expect(find.text('Available on team accounts.'), findsOneWidget);
    await tester.tap(find.text('Prep a user'));
    await tester.tap(find.text('Recovery'));
    await tester.tap(find.text('Find pad placements'));
    expect(taps, ['prep', 'recovery', 'pads']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant panel: university adds the squad tiles',
      (tester) async {
    await pumpPanel(tester, university: true);
    expect(find.text('Prep the squad'), findsOneWidget);
    expect(find.text('Game Ready board'), findsOneWidget);
    expect(find.text('Teams'), findsNothing);
    // No players on the roster yet → sessions today, not "0 of 0 prepped".
    expect(find.textContaining('prepped today', findRichText: true),
        findsNothing);
    expect(find.textContaining('sessions today', findRichText: true),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant panel on a tablet: narrow greeting card, centred '
      'pick-up rows, tiles two across', (tester) async {
    await pumpPanel(tester,
        university: true, size: const Size(834, 1400));
    final card = tester.getSize(find
        .ancestor(
            of: find.text('▶  Start a session'), matching: find.byType(Container))
        .last);
    expect(card.width, lessThanOrEqualTo(420));
    final row = tester.getSize(find
        .ancestor(of: find.text('Malik Carter'), matching: find.byType(Material))
        .first);
    expect(row.width, lessThanOrEqualTo(680));
    final a = tester.getTopLeft(find.text('Prep a user'));
    final b = tester.getTopLeft(find.text('Prep the squad'));
    expect(b.dy, a.dy); // same row → two across
    expect(tester.takeException(), isNull);
  });
}
