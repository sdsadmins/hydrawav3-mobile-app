import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/config/app_config.dart';
import 'package:hydrawav3/core/config/app_config_gate.dart';
import 'package:hydrawav3/core/config/app_config_store.dart';
import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/core/router/app_router.dart';
import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/session/domain/active_session_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/active_sessions_provider.dart';

/// Exactly what `GET mobile-app-config` returned on 2026-10-12.
const _live = '''
{"_id":"6acc8a3ff34e3cb9066aca76","key":"mobile","__v":0,
"deviceControlUrl":"http://localhost:5002",
"javaBaseUrl":"http://54.241.236.53:8080/api/v1/",
"latestAppVersion":{"android":"1.0.0","ios":"1.0.0"},"links":{},
"maintenance":{"enabled":false,"message":""},
"minAppVersion":{"android":"1.0.0","ios":"1.0.0"},
"nodeBaseUrl":"https://www.hydrawav3.studio/api/hydrawav/v1/",
"nodetestBaseUrl":"https://api.hydrawav3.studio/api/hydrawav/v1/",
"onboardingProxyUrl":"http://localhost:5003","socketUrl":"http://localhost:5000",
"storeUrl":{},"version":1,"websitePlanUrl":"http://localhost:3000/plans"}
''';

Map<String, dynamic> get _liveJson =>
    Map<String, dynamic>.from(jsonDecode(_live) as Map);

void main() {
  tearDown(() {
    AppConfigStore.current = AppConfig.defaults;
    AppConfigStore.versionGate.value = AppConfig.defaults;
    AppConfigStore.appVersion = '';
  });

  group('parsing the live config', () {
    test('localhost fields fall back to the built-in URLs', () {
      final c = AppConfig.fromServer(_liveJson);
      const d = AppConfig.defaults;
      expect(c.deviceControlUrl, d.deviceControlUrl);
      expect(c.onboardingProxyUrl, d.onboardingProxyUrl);
      expect(c.websitePlanUrl, d.websitePlanUrl);
      expect(c.links.privacy, d.links.privacy);
      expect(c.version, 1);
    });

    test('Django: trailing slash trimmed to the app\'s format', () {
      final c = AppConfig.fromServer(_liveJson);
      expect(c.djangoBaseUrl, 'http://54.241.236.53:8080/api/v1');
    });

    test('a store install reads nodeBaseUrl', () {
      final c = AppConfig.fromServer(_liveJson);
      expect(c.nodeBaseUrl, 'https://www.hydrawav3.studio/api/hydrawav/v1/');
      // socketUrl is localhost → the socket follows the Node host
      expect(c.socketOrigin, 'https://www.hydrawav3.studio');
    });

    test('a test install (APK, TestFlight) uses nodetestBaseUrl', () {
      final c = AppConfig.fromServer(_liveJson).forTestInstall();
      expect(c.nodeBaseUrl, 'https://api.hydrawav3.studio/api/hydrawav/v1/');
      // the test server runs its own socket
      expect(c.socketOrigin, 'https://api.hydrawav3.studio');
      expect(c.djangoBaseUrl, 'http://54.241.236.53:8080/api/v1');
      // offline first launch: the built-in test host
      expect(AppConfig.defaults.forTestInstall().nodeBaseUrl,
          'https://api.hydrawav3.studio/api/hydrawav/v1/');
    });

    test('only App Store and Google Play installs are store installs', () {
      expect(AppConfigStore.isTestInstall('com.apple'), isFalse);
      expect(AppConfigStore.isTestInstall('com.android.vending'), isFalse);
      expect(AppConfigStore.isTestInstall('com.apple.testflight'), isTrue);
      expect(AppConfigStore.isTestInstall(null), isTrue); // sideloaded APK
      expect(AppConfigStore.isTestInstall('com.google.android.packageinstaller'),
          isTrue);
    });

    test('a foreign or plain-http host is never accepted', () {
      final c = AppConfig.fromServer({
        'javaBaseUrl': 'http://evil.example.com/api/v1',
        'nodeBaseUrl': 'http://api.hydrawav3.studio/api/hydrawav/v1/',
        'websitePlanUrl': 'https://hydrawav3.studio.evil.com/plans',
        'links': {'buy': 'https://shop.hydrawav3.com/buy'},
        'storeUrl': {'ios': 'https://evil.com/app'},
      });
      const d = AppConfig.defaults;
      expect(c.djangoBaseUrl, d.djangoBaseUrl);
      expect(c.nodeBaseUrl, d.nodeBaseUrl);
      expect(c.websitePlanUrl, d.websitePlanUrl);
      expect(c.links.buy, 'https://shop.hydrawav3.com/buy'); // our subdomain
      expect(c.storeUrl.ios, '');
    });

    test('an empty object is exactly the defaults', () {
      final c = AppConfig.fromServer(const {});
      expect(c.toCache(), AppConfig.defaults.toCache()..['version'] = 0);
    });

    test('the saved copy round-trips', () {
      final c = AppConfig.fromServer(_liveJson);
      final back = AppConfig.fromCache(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(c.toCache())) as Map));
      expect(back.toCache(), c.toCache());
    });
  });

  test('ApiEndpoints read the loaded config', () {
    AppConfigStore.current =
        AppConfig.fromServer(_liveJson);
    expect(ApiEndpoints.nodeBaseUrl,
        'https://www.hydrawav3.studio/api/hydrawav/v1/');
    expect(ApiEndpoints.djangoBaseUrl, 'http://54.241.236.53:8080/api/v1');
    expect(ApiEndpoints.baseUrl, 'http://54.241.236.53:8080');
    expect(ApiEndpoints.socketOrigin, 'https://www.hydrawav3.studio');
  });

  test('version compare', () {
    expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
    expect(compareVersions('1.1.0', '1.0.99'), greaterThan(0));
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('1.0.9+12', '1.0.9'), 0);
  });

  group('load', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('offline first launch → built-in URLs', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppConfigStore.load(prefs, wait: const Duration(milliseconds: 1));
      expect(AppConfigStore.current.nodeBaseUrl,
          AppConfig.defaults.nodeBaseUrl);
    });

    test('a saved copy is used when the server is slow', () async {
      SharedPreferences.setMockInitialValues({
        'mobile_app_config_v2': jsonEncode(
            AppConfig.fromServer(_liveJson).toCache()),
      });
      final prefs = await SharedPreferences.getInstance();
      await AppConfigStore.load(prefs, wait: const Duration(milliseconds: 1));
      expect(AppConfigStore.current.version, 1);
      expect(AppConfigStore.current.nodeBaseUrl,
          'https://www.hydrawav3.studio/api/hydrawav/v1/');
    });
  });

  group('update rule (every new release is required)', () {
    AppConfig cfg({String latest = '', String min = ''}) =>
        AppConfig.fromServer({
          ..._liveJson,
          'latestAppVersion': {'ios': latest, 'android': latest},
          'minAppVersion': {'ios': min, 'android': min},
        });

    test('older than latestAppVersion → required', () {
      AppConfigStore.appVersion = '1.0.10';
      expect(AppConfigStore.updateRequiredFor(cfg(latest: '1.0.11')), isTrue);
    });
    test('same or newer → not required', () {
      AppConfigStore.appVersion = '1.0.10';
      expect(AppConfigStore.updateRequiredFor(cfg(latest: '1.0.10')), isFalse);
      expect(AppConfigStore.updateRequiredFor(cfg(latest: '1.0.5')), isFalse);
    });
    test('below minAppVersion is still required', () {
      AppConfigStore.appVersion = '1.0.10';
      expect(AppConfigStore.updateRequiredFor(cfg(min: '1.1.0')), isTrue);
    });
    test('no versions in the config, or unknown app version → never', () {
      AppConfigStore.appVersion = '1.0.10';
      expect(AppConfigStore.updateRequiredFor(cfg()), isFalse);
      AppConfigStore.appVersion = '';
      expect(AppConfigStore.updateRequiredFor(cfg(latest: '9.0.0')), isFalse);
    });
  });

  group('gate', () {
    final newer = {
      ..._liveJson,
      'latestAppVersion': {'ios': '1.2.0', 'android': '1.2.0'},
      'storeUrl': {
        'android': 'https://play.google.com/store/apps/details?id=x',
        'ios': 'https://apps.apple.com/app/id1',
      },
    };

    Future<void> pump(
      WidgetTester tester, {
      String location = '/home',
      List<ActiveSession> sessions = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(initialLocation: location, routes: [
        GoRoute(path: '/', builder: (c, s) => const SizedBox()),
        GoRoute(path: '/home', builder: (c, s) => const SizedBox()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          routerProvider.overrideWithValue(router),
          activeSessionsProvider
              .overrideWith((ref) => _Sessions(prefs, sessions)),
        ],
        // Wired like the real app: the gate wraps the router's output.
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppConfigGate(
            child: Stack(children: [
              child ?? const SizedBox(),
              const Text('the app'),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    void serve(Map<String, dynamic> json) {
      AppConfigStore.current = AppConfig.fromServer(json);
      AppConfigStore.versionGate.value = AppConfigStore.current;
    }

    testWidgets('current version passes through', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve(_liveJson);
      await pump(tester);
      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Update required'), findsNothing);
    });

    testWidgets('newer release → no-skip card over the app', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve(newer);
      await pump(tester);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      // Only the Update button — nothing to close or skip.
      expect(find.byType(InkWell), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('not shown on the splash screen', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve(newer);
      await pump(tester, location: '/');
      expect(find.text('Update required'), findsNothing);
    });

    testWidgets('waits while a session is running', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve(newer);
      await pump(tester, sessions: [
        ActiveSession(
          id: 's1',
          protocolId: 'p1',
          protocolName: 'Deep-Tension Recovery',
          deviceIds: const ['AA'],
          transport: 'ble',
          createdAt: DateTime(2026, 10, 29),
          status: SessionStatus.running,
        ),
      ]);
      expect(find.text('Update required'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('a late config answer still shows the card', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve(_liveJson);
      await pump(tester);
      expect(find.text('Update required'), findsNothing);
      AppConfigStore.versionGate.value = AppConfig.fromServer(newer);
      await tester.pump(); // the change is noticed…
      await tester.pump(); // …and the card drawn on the next frame
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('maintenance shows its message', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      serve({
        ..._liveJson,
        'maintenance': {'enabled': true, 'message': 'Back at 6 PM.'},
      });
      await pump(tester);
      expect(find.text('Down for maintenance'), findsOneWidget);
      expect(find.text('Back at 6 PM.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

/// A fixed list of sessions running on this phone.
class _Sessions extends ActiveSessionsNotifier {
  _Sessions(super.prefs, List<ActiveSession> sessions) {
    state = sessions;
  }
}
