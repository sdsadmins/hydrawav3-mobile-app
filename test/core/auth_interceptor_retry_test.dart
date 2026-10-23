// [FIX-15] A request that keeps returning 401 (e.g. a role with no access to
// the endpoint) triggers exactly ONE token refresh and ONE retry, marked with
// `__authRetried__`; the second 401 then propagates to the caller instead of
// looping 401 → refresh → retry → 401 → … forever.
//
// The interceptor builds its own `Dio` for the refresh call, so that request
// is answered through `HttpOverrides` (a fake HttpClient) while the original
// request and its retry go through FakeHttp.

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

import '../helpers/fake_http.dart';

// ── fakes ───────────────────────────────────────────────────────────────────

class _MemStorage implements SecureStorageService {
  _MemStorage({String? access, String? refresh})
      : _access = access,
        _refresh = refresh;

  String? _access;
  String? _refresh;
  int saveCalls = 0;
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
    saveCalls++;
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
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Answers the interceptor's internal refresh `Dio` with [respond]; records
/// every URL.
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
    // The refresh succeeds and hands back a new token pair.
    http = _FakeHttpOverrides((url) => url.path.endsWith(ApiEndpoints.refreshToken)
        ? (
            200,
            jsonEncode({
              'JWT_ACCESS_TOKEN': 'Bearer new-access',
              'JWT_REFRESH_TOKEN': 'Bearer new-refresh',
            }),
          )
        : (404, '{}'));
    HttpOverrides.global = http;
  });
  tearDown(() => HttpOverrides.global = null);

  test(
    '[FIX-15] a persistent 401 refreshes once, retries once, then propagates',
    () async {
      final storage = _MemStorage(access: 'old-access', refresh: 'old-refresh');
      // The endpoint rejects every call, including the retried one. The retry
      // re-sends the SAME RequestOptions object (mutated in place), so the
      // header and the retry mark are captured as each request arrives.
      final authHeaders = <Object?>[];
      final retryMarks = <Object?>[];
      final server = FakeHttp()
        ..on('GET', '/admin/sensors', (req) {
          authHeaders.add(req.headers['Authorization']);
          retryMarks.add(req.options.extra['__authRetried__']);
          return FakeReply.status(401);
        });

      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(storage),
        djangoDioProvider.overrideWith((ref) {
          final dio = server.dio();
          dio.interceptors.add(ref.read(authInterceptorProvider));
          return dio;
        }),
      ]);
      addTearDown(container.dispose);

      final dio = container.read(djangoDioProvider);

      // Completes (with the 401) instead of spinning forever.
      await expectLater(
        dio.get('/admin/sensors').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)),
      );

      // Exactly one refresh...
      final refreshes =
          http.calls.where((u) => u.path.endsWith(ApiEndpoints.refreshToken));
      expect(refreshes, hasLength(1));
      expect(storage.saveCalls, 1);
      expect(await storage.getAccessToken(), 'new-access');

      // ...and exactly one retry: the original request plus one more.
      expect(server.requestsTo('/admin/sensors'), hasLength(2));
      expect(authHeaders, ['Bearer old-access', 'Bearer new-access'],
          reason: 'the retry must carry the refreshed token');
      expect(retryMarks[0], isNot(true));
      expect(retryMarks[1], isTrue,
          reason: 'the retry is marked so a second 401 cannot refresh again');

      // The second 401 did not clear the fresh tokens or start another cycle.
      expect(storage.clearCalls, 0);
      expect(http.calls, hasLength(1));
    },
  );

  test('[FIX-15] a request that succeeds on retry resolves normally', () async {
    final storage = _MemStorage(access: 'stale', refresh: 'r');
    var calls = 0;
    final server = FakeHttp()
      ..on('GET', '/admin/sensors', (req) {
        calls++;
        return req.headers['Authorization'] == 'Bearer new-access'
            ? FakeReply.json(200, {'data': []})
            : FakeReply.status(401);
      });

    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      djangoDioProvider.overrideWith((ref) {
        final dio = server.dio();
        dio.interceptors.add(ref.read(authInterceptorProvider));
        return dio;
      }),
    ]);
    addTearDown(container.dispose);

    final res = await container
        .read(djangoDioProvider)
        .get('/admin/sensors')
        .timeout(const Duration(seconds: 5));

    expect(res.statusCode, 200);
    expect(calls, 2);
    expect(http.calls, hasLength(1));
  });
}
