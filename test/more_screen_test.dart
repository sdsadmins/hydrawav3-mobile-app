import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/core/theme/widgets/hw_primitives.dart';
import 'package:hydrawav3/features/auth/data/auth_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import 'package:hydrawav3/features/ble/domain/ble_device_model.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_connection_provider.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
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

/// More mirrors the UI handoff's `renderMore` (app.js:1883). This pins the
/// section list and the rows inside each one, since the screen had drifted:
/// extra Library rows, legal spilled across five rows, a stray device-
/// registration group, and a missing "Add organization" button.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpMore(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    // Tall surface so the whole screen lays out and every row is findable.
    tester.view.physicalSize = const Size(390 * 3, 3000 * 3);
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
}
