/// Base URLs, links and app gates, served by the Node backend's public
/// `GET mobile-app-config` (admin edits it with `PUT`), so a URL can change
/// without a store release.
///
/// Every field is validated on its own: anything empty, malformed, `localhost`
/// or outside our own domains falls back to the built-in value in
/// [AppConfig.defaults] (today's hard-coded URLs). A bad or half-filled config
/// can therefore never point the app — or its login tokens — somewhere else.
library;

import 'package:flutter/foundation.dart';

class PlatformValue {
  final String ios;
  final String android;
  const PlatformValue({this.ios = '', this.android = ''});

  String get current =>
      defaultTargetPlatform == TargetPlatform.iOS ? ios : android;

  factory PlatformValue.fromJson(dynamic j) => j is Map
      ? PlatformValue(
          ios: (j['ios'] ?? '').toString().trim(),
          android: (j['android'] ?? '').toString().trim(),
        )
      : const PlatformValue();

  Map<String, dynamic> toJson() => {'ios': ios, 'android': android};
}

class AppLinks {
  final String helpCenter;
  final String buy;
  final String economics;
  final String privacy;
  final String terms;

  const AppLinks({
    required this.helpCenter,
    required this.buy,
    required this.economics,
    required this.privacy,
    required this.terms,
  });

  Map<String, dynamic> toJson() => {
        'helpCenter': helpCenter,
        'buy': buy,
        'economics': economics,
        'privacy': privacy,
        'terms': terms,
      };
}

class AppConfig {
  final int version;

  /// Django (`javaBaseUrl` on the server). No trailing slash: Django paths
  /// start with `/`.
  final String djangoBaseUrl;

  /// Node REST base. Ends with `/`: Node paths are relative.
  final String nodeBaseUrl;

  /// Socket.IO origin (`scheme://host[:port]`).
  final String socketOrigin;

  final String deviceControlUrl;
  final String onboardingProxyUrl;
  final String websitePlanUrl;
  final AppLinks links;

  final PlatformValue minAppVersion;
  final PlatformValue latestAppVersion;
  final PlatformValue storeUrl;
  final bool maintenance;
  final String maintenanceMessage;

  const AppConfig({
    required this.version,
    required this.djangoBaseUrl,
    required this.nodeBaseUrl,
    required this.socketOrigin,
    required this.deviceControlUrl,
    required this.onboardingProxyUrl,
    required this.websitePlanUrl,
    required this.links,
    this.minAppVersion = const PlatformValue(),
    this.latestAppVersion = const PlatformValue(),
    this.storeUrl = const PlatformValue(),
    this.maintenance = false,
    this.maintenanceMessage = '',
  });

  /// Today's built-in values — first launch, offline, and any field the
  /// server leaves empty or invalid.
  static const defaults = AppConfig(
    version: 0,
    djangoBaseUrl: 'http://54.241.236.53:8080/api/v1',
    nodeBaseUrl: 'https://api.hydrawav3.studio/api/hydrawav/v1/',
    socketOrigin: 'https://api.hydrawav3.studio',
    deviceControlUrl: 'https://hydrawav3.app',
    onboardingProxyUrl: 'https://hydrawav3.app/proxy_create_user.php',
    websitePlanUrl: 'https://api.hydrawav3.studio/practitioner/subscription',
    links: AppLinks(
      helpCenter: 'https://www.hydrawav3.com/help-center',
      buy: 'https://www.hydrawav3.com/buy',
      economics: 'https://www.hydrawav3.com/economics',
      privacy: 'https://www.hydrawav3.com/privacy',
      terms: 'https://www.hydrawav3.com/terms',
    ),
  );

  // ── validation ────────────────────────────────────────────────────────────

  static const _domains = ['hydrawav3.com', 'hydrawav3.studio', 'hydrawav3.app'];

  /// The Django server has no domain name yet; this one IP is allowed (and is
  /// the only host allowed over plain http).
  static const _djangoIp = '54.241.236.53';

  /// True when [url] is one of ours: https on our domains (or a subdomain),
  /// or the Django IP.
  static bool isAllowed(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) return false;
    final host = u.host.toLowerCase();
    if (host == _djangoIp) return u.scheme == 'http' || u.scheme == 'https';
    if (u.scheme != 'https') return false;
    return _domains.any((d) => host == d || host.endsWith('.$d'));
  }

  static String _pick(dynamic raw, String fallback) {
    final v = (raw ?? '').toString().trim();
    return v.isNotEmpty && isAllowed(v) ? v : fallback;
  }

  static String _origin(String url) {
    final u = Uri.parse(url);
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  /// Server JSON → config. [useTestNode]: debug builds read `nodetestBaseUrl`
  /// first; store builds read `nodeBaseUrl`.
  factory AppConfig.fromServer(Map<String, dynamic> j,
      {required bool useTestNode}) {
    const d = defaults;
    var django = _pick(j['javaBaseUrl'] ?? j['djangoBaseUrl'], d.djangoBaseUrl);
    django = django.replaceFirst(RegExp(r'/+$'), '');

    final nodeRaw = useTestNode
        ? _pick(j['nodetestBaseUrl'], _pick(j['nodeBaseUrl'], ''))
        : _pick(j['nodeBaseUrl'], '');
    var node = nodeRaw.isEmpty ? d.nodeBaseUrl : nodeRaw;
    if (!node.endsWith('/')) node = '$node/';

    // The socket follows the Node host unless the server names its own.
    final socket = _pick(j['socketUrl'], '');
    final links = j['links'] is Map ? j['links'] as Map : const {};

    final maintenance = j['maintenance'] is Map ? j['maintenance'] as Map : const {};
    return AppConfig(
      version: (j['version'] as num?)?.toInt() ?? 0,
      djangoBaseUrl: django,
      nodeBaseUrl: node,
      socketOrigin: socket.isNotEmpty ? _origin(socket) : _origin(node),
      deviceControlUrl: _pick(j['deviceControlUrl'], d.deviceControlUrl)
          .replaceFirst(RegExp(r'/+$'), ''),
      onboardingProxyUrl: _pick(j['onboardingProxyUrl'], d.onboardingProxyUrl),
      websitePlanUrl: _pick(j['websitePlanUrl'], d.websitePlanUrl),
      links: AppLinks(
        helpCenter: _pick(links['helpCenter'], d.links.helpCenter),
        buy: _pick(links['buy'], d.links.buy),
        economics: _pick(links['economics'], d.links.economics),
        privacy: _pick(links['privacy'], d.links.privacy),
        terms: _pick(links['terms'], d.links.terms),
      ),
      minAppVersion: PlatformValue.fromJson(j['minAppVersion']),
      latestAppVersion: PlatformValue.fromJson(j['latestAppVersion']),
      storeUrl: () {
        final s = PlatformValue.fromJson(j['storeUrl']);
        bool store(String u) {
          final h = Uri.tryParse(u)?.host ?? '';
          return u.startsWith('https://') &&
              (h == 'apps.apple.com' || h == 'play.google.com');
        }

        return PlatformValue(
          ios: store(s.ios) ? s.ios : '',
          android: store(s.android) ? s.android : '',
        );
      }(),
      maintenance: maintenance['enabled'] == true,
      maintenanceMessage: (maintenance['message'] ?? '').toString(),
    );
  }

  // ── the saved copy (already validated; re-validated on load anyway) ───────

  Map<String, dynamic> toCache() => {
        'version': version,
        'javaBaseUrl': djangoBaseUrl,
        'nodeBaseUrl': nodeBaseUrl,
        'socketUrl': socketOrigin,
        'deviceControlUrl': deviceControlUrl,
        'onboardingProxyUrl': onboardingProxyUrl,
        'websitePlanUrl': websitePlanUrl,
        'links': links.toJson(),
        'minAppVersion': minAppVersion.toJson(),
        'latestAppVersion': latestAppVersion.toJson(),
        'storeUrl': storeUrl.toJson(),
        'maintenance': {'enabled': maintenance, 'message': maintenanceMessage},
      };

  factory AppConfig.fromCache(Map<String, dynamic> j) =>
      AppConfig.fromServer(j, useTestNode: false);
}

/// `1.2.10` vs `1.2.9` → positive. Missing parts count as 0; non-numeric
/// parts (`1.0.9+12`, `1.0.9-beta`) use their leading digits.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p.trim()) ?? '') ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}
