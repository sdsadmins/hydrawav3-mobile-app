// [AUTH-19] When the token refresh fails after a 401, the interceptor must
// clear the stored tokens AND sign the practitioner out (authStateProvider
// unauthenticated) so the router sends them to login instead of leaving a
// signed-in shell with no working session.
//
// KNOWN BUG (qa-known-bug): lib/core/network/auth_interceptor.dart:78-82
// clears the tokens but never resets the auth state, so this fails today.
//
// The interceptor builds its own `Dio` for the refresh call, so that request
// is answered through `HttpOverrides` (a fake HttpClient) while the original
// request goes through FakeHttp.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/core/network/auth_interceptor.dart';
import 'package:hydrawav3/core/network/dio_client.dart';
import 'package:hydrawav3/core/storage/secure_storage.dart';
import 'package:hydrawav3/features/auth/data/auth_repository.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';

import '../helpers/fake_http.dart';

// ── fakes ───────────────────────────────────────────────────────────────────

class _MemStorage implements SecureStorageService {
  _MemStorage({String? access, String? refresh})
      : _access = access,
        _refresh = refresh;

  String? _access;
  String? _refresh;
  int clearCalls = 0;

  @override
  Future<String?> getAccessToken() async => _access;
  @override
  Future<String?> getRefreshToken() async => _refresh;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    clearCalls++;
    _access = null;
    _refresh = null;
  }

  @override
  Future<bool> hasTokens() async => _access != null;
  @override
  Future<void> clearAll() async {
    _access = null;
    _refresh = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Answers the interceptor's internal refresh `Dio` (and anything else that
/// uses `dart:io`'s HttpClient) with [respond]; records every URL.
class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.respond);
  final (int, String) Function(Uri url) respond;
  final calls = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.owner);
  final _FakeHttpOverrides owner;

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    owner.calls.add(url);
    final (status, body) = owner.respond(url);
    return _FakeRequest(_FakeResponse(status, body));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  final _map = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _map[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_map[name.toLowerCase()] ??= []).add('$value');
  @override
  List<String>? operator [](String name) => _map[name.toLowerCase()];
  @override
  String? value(String name) => _map[name.toLowerCase()]?.join(', ');
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _map.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.response);
  final _FakeResponse response;

  @override
  final HttpHeaders headers = _FakeHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, String body) : _bytes = utf8.encode(body) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }

  final List<int> _bytes;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers = _FakeHeaders();
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  String get reasonPhrase => '';
  @override
  X509Certificate? get certificate => null;
  @override
  int get contentLength => _bytes.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([_bytes]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ── test ────────────────────────────────────────────────────────────────────

void main() {
  late _FakeHttpOverrides http;

  setUp(() {
    // The refresh endpoint rejects the stored refresh token.
    http = _FakeHttpOverrides((url) => url.path.endsWith(ApiEndpoints.refreshToken)
        ? (401, '{"message":"Token expired"}')
        : (404, '{}'));
    HttpOverrides.global = http;
  });
  tearDown(() => HttpOverrides.global = null);

  test(
    '[AUTH-19] failed refresh clears tokens AND signs the practitioner out',
    () async {
      final storage = _MemStorage(access: 'old-access', refresh: 'old-refresh');
      final server = FakeHttp()..onStatus('GET', '/admin/sensors', 401);

      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        djangoDioProvider.overrideWith((ref) {
          final dio = server.dio();
          dio.interceptors.add(ref.read(authInterceptorProvider));
          return dio;
        }),
      ]);
      addTearDown(container.dispose);

      // A signed-in practitioner.
      container.read(authStateProvider.notifier).enterDemoMode();
      expect(container.read(authStateProvider).isAuthenticated, isTrue);

      final dio = container.read(djangoDioProvider);
      await expectLater(
        dio.get('/admin/sensors').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)),
      );

      // One refresh attempt was made and rejected.
      expect(
        http.calls.where((u) => u.path.endsWith(ApiEndpoints.refreshToken)),
        hasLength(1),
      );
      // No retry of the original request without a fresh token.
      expect(server.requestsTo('/admin/sensors'), hasLength(1));

      // Tokens are gone...
      expect(storage.clearCalls, greaterThanOrEqualTo(1));
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);

      // ...and so is the session: the app must not stay "signed in" with no
      // usable token (auth_interceptor.dart:80 never resets this today).
      final auth = container.read(authStateProvider);
      expect(auth.isAuthenticated, isFalse,
          reason: 'a failed refresh must sign the practitioner out');
      expect(auth.isInitialized, isTrue,
          reason: 'router should go straight to login, not splash');
    },
    tags: ['qa-known-bug'],
  );
}
