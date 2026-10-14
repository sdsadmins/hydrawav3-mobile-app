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

  /// This build's version (`package_info_plus`), for the update gate.
  static String appVersion = '';

  /// The one hard-coded address: the public config endpoint on the stable
  /// domain. Debug/profile builds can point elsewhere with
  /// `--dart-define=HW_CONFIG_URL=...`.
  static const _defaultConfigUrl =
      'https://api.hydrawav3.studio/api/hydrawav/v1/mobile-app-config';
  static const _overrideUrl = String.fromEnvironment('HW_CONFIG_URL');
  static String get configUrl =>
      !kReleaseMode && _overrideUrl.isNotEmpty ? _overrideUrl : _defaultConfigUrl;

  static const _cacheKey = 'mobile_app_config_v1';

  /// Debug builds use the server's `nodetestBaseUrl`; store builds use
  /// `nodeBaseUrl`.
  static bool get useTestNode => !kReleaseMode;

  /// Saved copy first, then the server — waiting at most [wait] so a slow
  /// network can't hold the launch. A fetch that finishes later is still
  /// saved for the next launch.
  static Future<void> load(
    SharedPreferences prefs, {
    Duration wait = const Duration(milliseconds: 2500),
    Dio? dio,
  }) async {
    current = _saved(prefs) ?? AppConfig.defaults;
    try {
      final fresh = await fetch(prefs, dio: dio).timeout(wait);
      if (fresh != null) current = fresh;
    } catch (_) {
      // Timeout or offline: keep the saved copy for this run.
    }
    if (kDebugMode) {
      debugPrint('APP CONFIG v${current.version} · node ${current.nodeBaseUrl}'
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
      final config = AppConfig.fromServer(Map<String, dynamic>.from(data),
          useTestNode: useTestNode);
      await prefs.setString(_cacheKey, jsonEncode(config.toCache()));
      return config;
    } catch (_) {
      return null;
    }
  }

  /// Below the server's minimum for this platform → the update gate.
  static bool get updateRequired {
    final min = current.minAppVersion.current;
    if (min.isEmpty || appVersion.isEmpty) return false;
    return compareVersions(appVersion, min) < 0;
  }

  /// Below the latest (but at/above the minimum) → "update available".
  static bool get updateAvailable {
    final latest = current.latestAppVersion.current;
    if (latest.isEmpty || appVersion.isEmpty) return false;
    return compareVersions(appVersion, latest) < 0;
  }
}
