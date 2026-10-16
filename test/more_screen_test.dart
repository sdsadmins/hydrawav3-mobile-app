import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/core/theme/widgets/hw_primitives.dart';
import 'package:hydrawav3/features/auth/data/auth_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import 'package:hydrawav3/features/ble/domain/ble_device_model.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_connection_provider.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';
import 'package:hydrawav3/features/payments/domain/plan_model.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/presets/presentation/providers/preset_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/settings/presentation/screens/settings_screen.dart';

/// Stands in for the profile fetch the Edit-profile sheet makes on open, so
/// the test doesn't finish with a request still in flight.
class _FakeAuthSource implements AuthRemoteSource {
  @override
  Future<UserProfile> getProfile() async =>
      const UserProfile(id: '1', firstName: 'Marcus', lastName: 'Ellison');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Signed in to org 1 as the primary-account admin.
class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth()
      : super(const AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          user: UserProfile(
            id: '1',
            firstName: 'Marcus',
            lastName: 'Ellison',
            roles: ['PRIMARY ACCOUNT - ADMIN'],
          ),
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A fixed credit balance, with no polling.
class _FakeTokens extends StateNotifier<double?>
    implements TokenBalanceNotifier {
  _FakeTokens(super.v);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// More mirrors the UI handoff's `renderMore` (app.js:1883). This pins the
/// section list and the rows inside each one, since the screen had drifted:
/// extra Library rows, legal spilled across five rows, a stray device-
/// registration group, and a missing "Add organization" button.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpMore(WidgetTester tester,
      {List<Override> extra = const [], double width = 390}) async {
    final prefs = await SharedPreferences.getInstance();
    // Tall surface so the whole screen lays out and every row is findable.
    tester.view.physicalSize = Size(width * 3, 3600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          organizationProvider.overrideWith((ref) async => [
                {'id': 1, 'name': 'Miami Dolphins', 'description': 'NFL team'},
              ]),
          currentPlanProvider.overrideWith((ref) async => null),
          // Stub every network/BLE read the screen makes, so the test measures
          // structure and leaves no Dio clients or poll timers running.
          wifiDevicesByOrgProvider.overrideWith((ref) async => []),
          bleConnectionStatesProvider.overrideWith(
            (ref) => Stream.value(<String, BleConnectionStatus>{}),
          ),
          notificationsProvider.overrideWith((ref) async => []),
          protocolListProvider.overrideWith((ref) async => []),
          authRemoteSourceProvider.overrideWithValue(_FakeAuthSource()),
          ...extra,
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('renders the spec\'s sections in order', (tester) async {
    await pumpMore(tester);
    expect(tester.takeException(), isNull);

    for (final heading in [
      'More',
      'YOUR ORGANIZATIONS',
      'APPEARANCE',
      'PLAN',
      'LIBRARY & INTELLIGENCE',
      'DEVICES',
      'SESSION DEFAULTS',
      'SETTINGS & SUPPORT',
      'COMING ONLINE',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
  });

  testWidgets('Library & intelligence has exactly the spec\'s four rows',
      (tester) async {
    await pumpMore(tester);

    expect(find.text('Protocol Library'), findsOneWidget);
    expect(find.text('AI Hub'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Quick Presets'), findsOneWidget);

    // These had crept in as separate rows and belong elsewhere.
    expect(find.text('AI Reports'), findsNothing);
    expect(find.text('AI Chat'), findsNothing);
  });

  testWidgets('Settings & support carries Notifications and one legal row',
      (tester) async {
    await pumpMore(tester);

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Legal & licenses'), findsOneWidget);

    // Legal lives behind that one row, not spread across the group.
    expect(find.text('Privacy policy'), findsNothing);
    expect(find.text('Terms & conditions'), findsNothing);
    expect(find.text('Acknowledgements'), findsNothing);
    expect(find.text('Help & support'), findsNothing);
  });

  testWidgets('profile and password open as sheets, not screens',
      (tester) async {
    await pumpMore(tester);

    await tester.tap(find.text('Edit profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    // The spec opens these as sheets, not screens — that's the redirect under
    // test. (The profile fields sit behind a profile fetch, so this asserts
    // the surface, not the form.)
    expect(find.byType(HwSheet), findsOneWidget);
    expect(find.text('Edit profile'), findsWidgets);
  });

  testWidgets('organizations offer a way to add one', (tester) async {
    await pumpMore(tester);

    expect(find.text('Miami Dolphins'), findsOneWidget);
    expect(find.text('Add organization'), findsOneWidget);
  });

  testWidgets('Devices is a single card, registration lives inside it',
      (tester) async {
    await pumpMore(tester);

    expect(find.text('Device Center'), findsOneWidget);
    expect(find.text('Device registration'), findsNothing);
  });

  testWidgets('Session defaults uses the spec\'s row copy', (tester) async {
    await pumpMore(tester);

    expect(find.text('Default protocol'), findsOneWidget);
    expect(find.text('Default session music'), findsOneWidget);
    expect(find.text('Labs · Readiness Score'), findsOneWidget);
    expect(find.text('Session music'), findsNothing);
  });

  testWidgets('v6 adds Resources & business and Labs & insights',
      (tester) async {
    await pumpMore(tester);
    expect(find.text('RESOURCES & BUSINESS'), findsOneWidget);
    expect(find.text('LABS & INSIGHTS'), findsOneWidget);
    for (final row in [
      'Call Customer Support',
      'Business & Educational Resources',
      'START HERE',
      'Buy More Products',
      'Rent & Earn',
      'AI Mobility Report',
      'This Week',
      'Last Session',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Rental Economics'), findsOneWidget);
    expect(find.text('Labs · Measure Breath'), findsOneWidget);
    // Coming online is the one v6 item.
    expect(find.text('Breath Sync + Endurance Breathing'), findsOneWidget);
    expect(find.text('Mirror Placements'), findsNothing);
    expect(find.text('Calming Recipes'), findsNothing);
  });

  testWidgets('plan shows its price and presets their real count',
      (tester) async {
    await pumpMore(tester, extra: [
      currentPlanProvider.overrideWith((ref) async => const SubscriptionPlan(
            name: 'Sports plan',
            amount: 99,
            currency: 'usd',
            billingCycle: 'monthly',
          )),
      presetListProvider.overrideWith((ref) => Stream.value(const [])),
    ]);
    expect(find.text(r'Sports plan · $99/month'), findsOneWidget);
    expect(find.text('0 saved one-tap setups'), findsOneWidget);
    expect(find.text('3 saved one-tap setups'), findsNothing);
  });

  testWidgets('role card, and the active organization shows its credits',
      (tester) async {
    await pumpMore(tester, extra: [
      authStateProvider.overrideWith((ref) => _FakeAuth()),
      tokenBalanceProvider.overrideWith((ref) => _FakeTokens(27.5)),
    ]);
    expect(find.text('Main admin'), findsOneWidget);
    expect(find.text('Full control across every organization'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('organization credits'), findsOneWidget);
    expect(find.text('27.5 left'), findsOneWidget);
    // Signed in, the screen's history/stat reads start retry timers; let
    // them run out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('lays out on a tablet', (tester) async {
    await pumpMore(tester, width: 834);
    expect(tester.takeException(), isNull);
    expect(find.text('LABS & INSIGHTS'), findsOneWidget);
  });

  for (final width in [390.0, 834.0])
  testWidgets(
      'Labs & insights rows open their sheets '
      '(${width > 600 ? 'tablet' : 'phone'})', (tester) async {
    await pumpMore(tester, width: width);

    Future<void> open(String row) async {
      await tester.ensureVisible(find.text(row));
      await tester.pump();
      await tester.tap(find.text(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> close() async {
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await open('Labs · Measure Breath');
    expect(find.text('Ever measured your readiness from your own breath?'),
        findsOneWidget);
    await tester.tap(find.text('How it works'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Readiness from breath — how it works'), findsOneWidget);
    expect(find.text('Your breath becomes numbers'), findsOneWidget);
    await close();

    await open('AI Mobility Report');
    expect(find.text('Uncover your full mobility picture'), findsOneWidget);
    expect(find.text('▶  Generate my AI report'), findsOneWidget);
    await close();

    await open('This Week');
    expect(find.text('measured, not estimated'), findsOneWidget);
    expect(find.text('Outcome Pulse'), findsOneWidget);
    expect(find.text('Active days · 7d'), findsOneWidget);
    await close();

    if (find.text('Game Day').evaluate().isNotEmpty) {
      await open('Game Day');
      expect(find.text('Activate'), findsOneWidget);
      await close();
    }

    // No history in the test, so Last Session says so instead of opening.
    await open('Last Session');
    expect(find.text('Last session'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
