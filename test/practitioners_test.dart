import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/data/auth_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import 'package:hydrawav3/features/ble/domain/ble_device_model.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_connection_provider.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/practitioners/data/practitioner_repository.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/settings/presentation/screens/settings_screen.dart';

class _FakeAuthSource implements AuthRemoteSource {
  @override
  Future<UserProfile> getProfile() async =>
      const UserProfile(id: '1', firstName: 'Kt', lastName: 'Admin');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth(List<String> roles)
      : super(AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          user: UserProfile(id: '737', firstName: 'Kt', roles: roles),
        ));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRepo extends PractitionerRepository {
  _FakeRepo() : super(Dio());
  final created = <NewPractitioner>[];
  final team = const [
    Practitioner(
        id: 801,
        firstName: 'Dana',
        lastName: 'Whitfield',
        userName: 'danaw',
        title: 'Physiotherapist',
        mail: 'dana@clinic.com'),
    Practitioner(id: 802, firstName: 'Leo', lastName: 'Park', userName: 'leop'),
  ];

  @override
  Future<List<Practitioner>> byOrg(String orgId) async => team;

  @override
  Future<void> create(NewPractitioner p) async => created.add(p);
}

/// Main-admin team management on More (v5 `50-admin` look, web
/// Practitioners behaviour): only the account owner sees it, the team lists
/// `practitioners/by-org`, and Create sends the web's `secondary/create` body.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('roles are read from the JWT claim', () {
    String seg(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final token = '${seg({'alg': 'HS256'})}.'
        '${seg({'roles': ['PRIMARY ACCOUNT - ADMIN']})}.sig';
    expect(rolesFromJwt(token), ['PRIMARY ACCOUNT - ADMIN']);
    expect(rolesFromJwt('garbage'), isEmpty);
    expect(rolesFromJwt(null), isEmpty);
  });

  test('create body matches the web / backend field names', () {
    final json = const NewPractitioner(
      firstName: 'Jane',
      lastName: 'Doe',
      userName: 'janedoe',
      password: 'abcd2345',
      email: 'jane@x.com',
      phone: '555',
      title: 'PT',
      address: '1 Main',
      city: 'LA',
      country: 'USA',
      organizationIds: [1, 2],
    ).toJson();
    expect(json['firstname'], 'Jane');
    expect(json['lastname'], 'Doe');
    expect(json['practitionerType'], 'PT');
    expect(json['addOrganisations'], [1, 2]);
    expect(json.containsKey('state'), isFalse);
  });

  Future<_FakeRepo> pumpMore(WidgetTester tester, List<String> roles,
      {double width = 390}) async {
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRepo();
    tester.view.physicalSize = Size(width * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        organizationProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'Gulf Coast Tarpons'},
              {'id': 2, 'name': 'Northgate Ironworks'},
            ]),
        currentPlanProvider.overrideWith((ref) async => null),
        wifiDevicesByOrgProvider.overrideWith((ref) async => []),
        bleConnectionStatesProvider.overrideWith(
            (ref) => Stream.value(<String, BleConnectionStatus>{})),
        notificationsProvider.overrideWith((ref) async => []),
        protocolListProvider.overrideWith((ref) async => []),
        authRemoteSourceProvider.overrideWithValue(_FakeAuthSource()),
        authStateProvider.overrideWith((ref) => _FakeAuth(roles)),
        practitionerRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return repo;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  // Signed in, the screen's history reads start retry timers; let them end.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a practitioner does not see Manage users', (tester) async {
    await pumpMore(tester, ['PRACTITIONER']);
    expect(find.text('Manage users'), findsNothing);
    await drain(tester);
  });

  for (final width in [390.0, 834.0])
  testWidgets(
      'main admin manages the team and creates a login '
      '(${width > 600 ? 'tablet' : 'phone'})', (tester) async {
    final repo =
        await pumpMore(tester, ['PRIMARY ACCOUNT - ADMIN'], width: width);
    expect(find.text('Manage users'), findsNWidgets(2));
    expect(find.text('2 practitioners'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Manage users').first);
    await tester.tap(find.text('Manage users').first);
    await settle(tester);
    expect(find.text('Dana Whitfield'), findsOneWidget);
    expect(find.text('danaw · Physiotherapist'), findsOneWidget);
    expect(find.text('PRACTITIONERS · 2'), findsOneWidget);

    // View — the web's details.
    await tester.tap(find.text('Dana Whitfield'));
    await settle(tester);
    expect(find.text('#801'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close').last);
    await settle(tester);

    await tester.tap(find.text('Create practitioner login'));
    await settle(tester);
    expect(find.text('New practitioner'), findsOneWidget);

    // Same checks as the web form.
    await tester.ensureVisible(find.text('Create login'));
    await tester.tap(find.text('Create login'));
    await tester.pump();
    expect(find.text('First name is required'), findsOneWidget);

    final fields = find.byType(TextField);
    const values = [
      'Jane',
      'Doe',
      'jane@clinic.com',
      '5551234567',
      'Physiotherapist',
      '123 Main St',
      'Los Angeles',
      '',
      '',
      'USA',
    ];
    for (var i = 0; i < values.length; i++) {
      if (values[i].isEmpty) continue;
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.pump();
    await tester.ensureVisible(find.text('Create login'));
    await tester.tap(find.text('Create login'));
    await settle(tester);

    expect(repo.created, hasLength(1));
    final sent = repo.created.single;
    expect(sent.userName, 'janedoe');
    expect(sent.password.length, greaterThanOrEqualTo(8));
    expect(sent.organizationIds, [1]);
    expect(find.text('Practitioner login created'), findsOneWidget);
    expect(find.text('janedoe'), findsOneWidget);
    expect(find.text(sent.password), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });
}
