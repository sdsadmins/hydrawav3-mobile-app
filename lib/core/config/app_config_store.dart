import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Holds the [AppConfig] for this run.
///
/// Loaded ONCE in `main()`, before the app starts, and fixed for the whole
/// run: the URLs never change under a live session. A newer config fetched
/// late is saved and used from the next launch.
class AppConfigStore {
  AppConfigStore._();

  /// The config every base URL / link reads (via `ApiEndpoints` getters).
  static AppConfig current = AppConfig.defaults;

  /// The config the update check reads. Starts as [current]; a fetch that
  /// answers after the launch wait still lands here this run (only the
  /// update check uses it — URLs stay fixed for the run).
  static final versionGate = ValueNotifier<AppConfig>(AppConfig.defaults);

  /// This build's version (`package_info_plus`), for the update gate.
  static String appVersion = '';

  /// True for a test install (APK, TestFlight, a debug run): Node and the
  /// socket go to the test server (`nodetestBaseUrl`). Set in `main()` from
  /// [isTestInstall] before [load].
  static bool testInstall = false;

  /// Where the app was installed from (`PackageInfo.installerStore`): only
  /// the App Store (`com.apple`) and Google Play (`com.android.vending`) are
  /// store installs. TestFlight reports `com.apple.testflight`, a sideloaded
  /// APK or a debug run none — so the same build turns live once it's
  /// released on the store.
  static bool isTestInstall(String? installerStore) =>
      installerStore != 'com.apple' && installerStore != 'com.android.vending';

  static AppConfig _forThisInstall(AppConfig c) =>
      testInstall ? c.forTestInstall() : c;

  /// The one hard-coded address: the public config endpoint on the stable
  /// domain. Debug/profile builds can point elsewhere with
  /// `--dart-define=HW_CONFIG_URL=...`.
  static const _defaultConfigUrl =
      'https://hydrawav3.studio/api/hydrawav/v1/mobile-app-config';
  static const _overrideUrl = String.fromEnvironment('HW_CONFIG_URL');
  static String get configUrl =>
      !kReleaseMode && _overrideUrl.isNotEmpty ? _overrideUrl : _defaultConfigUrl;

  /// v2: v1 copies saved by debug builds could hold the old test host
  /// (`nodetestBaseUrl`), so they are ignored.
  static const _cacheKey = 'mobile_app_config_v2';

  /// Saved copy first, then the server — waiting at most [wait] so a slow
  /// network can't hold the launch. A fetch that finishes later is still
  /// saved for the next launch.
  static Future<void> load(
    SharedPreferences prefs, {
    Duration wait = const Duration(milliseconds: 2500),
    Dio? dio,
  }) async {
    current = _forThisInstall(_saved(prefs) ?? AppConfig.defaults);
    final pending = fetch(prefs, dio: dio);
    var late = false;
    try {
      final fresh = await pending.timeout(wait);
      if (fresh != null) current = _forThisInstall(fresh);
    } catch (_) {
      // Timeout or offline: keep the saved copy for this run.
      late = true;
    }
    versionGate.value = current;
    if (late) {
      // Checked once per app start: a slow answer still reaches the update
      // check this run instead of waiting for the next launch.
      unawaited(pending.then((fresh) {
        if (fresh != null) versionGate.value = fresh;
      }));
    }
    if (kDebugMode) {
      debugPrint('APP CONFIG v${current.version}'
          '${testInstall ? ' (test install)' : ''} · node ${current.nodeBaseUrl}'
          ' · django ${current.djangoBaseUrl} · socket ${current.socketOrigin}'
          ' · app $appVersion');
    }
  }

  static AppConfig? _saved(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      return j is Map ? AppConfig.fromCache(Map<String, dynamic>.from(j)) : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches, validates and saves the server config. Null on any failure
  /// (offline, not created yet → 404, bad JSON).
  static Future<AppConfig?> fetch(SharedPreferences prefs, {Dio? dio}) async {
    try {
      final client = dio ??
          Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
          ));
      final res = await client.get(configUrl);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is! Map) return null;
      final config = AppConfig.fromServer(Map<String, dynamic>.from(data));
      await prefs.setString(_cacheKey, jsonEncode(config.toCache()));
      return config;
    } catch (_) {
      return null;
    }
  }

  /// Must update, no skip: this build is older than the server's
  /// `latestAppVersion` (every new release is required) or below
  /// `minAppVersion`, for this platform.
  static bool get updateRequired => updateRequiredFor(versionGate.value);

  static bool updateRequiredFor(AppConfig c) {
    if (appVersion.isEmpty) return false;
    bool below(String v) => v.isNotEmpty && compareVersions(appVersion, v) < 0;
    return below(c.latestAppVersion.current) || below(c.minAppVersion.current);
  }
}
