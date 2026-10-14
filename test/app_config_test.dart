import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/config/app_config.dart';
import 'package:hydrawav3/core/config/app_config_gate.dart';
import 'package:hydrawav3/core/config/app_config_store.dart';
import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/core/storage/preferences.dart';

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
    AppConfigStore.appVersion = '';
  });

  group('parsing the live config', () {
    test('localhost fields fall back to the built-in URLs', () {
      final c = AppConfig.fromServer(_liveJson, useTestNode: false);
      const d = AppConfig.defaults;
      expect(c.deviceControlUrl, d.deviceControlUrl);
      expect(c.onboardingProxyUrl, d.onboardingProxyUrl);
      expect(c.websitePlanUrl, d.websitePlanUrl);
      expect(c.links.privacy, d.links.privacy);
      expect(c.version, 1);
    });

    test('Django: trailing slash trimmed to the app\'s format', () {
      final c = AppConfig.fromServer(_liveJson, useTestNode: false);
      expect(c.djangoBaseUrl, 'http://54.241.236.53:8080/api/v1');
    });

    test('store builds read nodeBaseUrl, debug builds nodetestBaseUrl', () {
      final rel = AppConfig.fromServer(_liveJson, useTestNode: false);
      final dbg = AppConfig.fromServer(_liveJson, useTestNode: true);
      expect(rel.nodeBaseUrl, 'https://www.hydrawav3.studio/api/hydrawav/v1/');
      expect(dbg.nodeBaseUrl, 'https://api.hydrawav3.studio/api/hydrawav/v1/');
      // socketUrl is localhost → the socket follows the Node host
      expect(rel.socketOrigin, 'https://www.hydrawav3.studio');
      expect(dbg.socketOrigin, 'https://api.hydrawav3.studio');
    });

    test('a foreign or plain-http host is never accepted', () {
      final c = AppConfig.fromServer({
        'javaBaseUrl': 'http://evil.example.com/api/v1',
        'nodeBaseUrl': 'http://api.hydrawav3.studio/api/hydrawav/v1/',
        'websitePlanUrl': 'https://hydrawav3.studio.evil.com/plans',
        'links': {'buy': 'https://shop.hydrawav3.com/buy'},
        'storeUrl': {'ios': 'https://evil.com/app'},
      }, useTestNode: false);
      const d = AppConfig.defaults;
      expect(c.djangoBaseUrl, d.djangoBaseUrl);
      expect(c.nodeBaseUrl, d.nodeBaseUrl);
      expect(c.websitePlanUrl, d.websitePlanUrl);
      expect(c.links.buy, 'https://shop.hydrawav3.com/buy'); // our subdomain
      expect(c.storeUrl.ios, '');
    });

    test('an empty object is exactly the defaults', () {
      final c = AppConfig.fromServer(const {}, useTestNode: false);
      expect(c.toCache(), AppConfig.defaults.toCache()..['version'] = 0);
    });

    test('the saved copy round-trips', () {
      final c = AppConfig.fromServer(_liveJson, useTestNode: true);
      final back = AppConfig.fromCache(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(c.toCache())) as Map));
      expect(back.toCache(), c.toCache());
    });
  });

  test('ApiEndpoints read the loaded config', () {
    AppConfigStore.current =
        AppConfig.fromServer(_liveJson, useTestNode: true);
    expect(ApiEndpoints.nodeBaseUrl,
        'https://api.hydrawav3.studio/api/hydrawav/v1/');
    expect(ApiEndpoints.djangoBaseUrl, 'http://54.241.236.53:8080/api/v1');
    expect(ApiEndpoints.baseUrl, 'http://54.241.236.53:8080');
    expect(ApiEndpoints.socketOrigin, 'https://api.hydrawav3.studio');
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
        'mobile_app_config_v1': jsonEncode(
            AppConfig.fromServer(_liveJson, useTestNode: false).toCache()),
      });
      final prefs = await SharedPreferences.getInstance();
      await AppConfigStore.load(prefs, wait: const Duration(milliseconds: 1));
      expect(AppConfigStore.current.version, 1);
      expect(AppConfigStore.current.nodeBaseUrl,
          'https://www.hydrawav3.studio/api/hydrawav/v1/');
    });
  });

  group('gate', () {
    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: AppConfigGate(child: Text('the app')),
        ),
      ));
    }

    testWidgets('current version passes through', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      AppConfigStore.current =
          AppConfig.fromServer(_liveJson, useTestNode: false);
      await pump(tester);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('below minAppVersion → Update required', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      AppConfigStore.current = AppConfig.fromServer({
        ..._liveJson,
        'minAppVersion': {'ios': '1.2.0', 'android': '1.2.0'},
        'storeUrl': {
          'android': 'https://play.google.com/store/apps/details?id=x',
          'ios': 'https://apps.apple.com/app/id1',
        },
      }, useTestNode: false);
      await pump(tester);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('the app'), findsNothing);
    });

    testWidgets('maintenance shows its message', (tester) async {
      AppConfigStore.appVersion = '1.0.0';
      AppConfigStore.current = AppConfig.fromServer({
        ..._liveJson,
        'maintenance': {'enabled': true, 'message': 'Back at 6 PM.'},
      }, useTestNode: false);
      await pump(tester);
      expect(find.text('Down for maintenance'), findsOneWidget);
      expect(find.text('Back at 6 PM.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
