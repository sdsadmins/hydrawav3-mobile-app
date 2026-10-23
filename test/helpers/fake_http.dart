// A Dio [HttpClientAdapter] that routes by method + path, answers with JSON or
// a bare status code, and records every request it saw.
//
// ```dart
// final server = FakeHttp()
//   ..on('POST', '/rag-chat/message', (req) => FakeReply.json(201, {'conversationId': 'c1'}))
//   ..on('GET', '/clients/c1', (_) => FakeReply.status(404));
// final repo = SomeRepository(server.dio());
// ...
// expect(server.requests.single.json['message'], 'hi');
// ```
//
// A route's path matches the request path exactly, or as a whole-segment
// suffix (so a baseUrl prefix such as `/api/v1` doesn't need repeating, and
// `ApiEndpoints` constants can be used as-is), or — when given a [RegExp] —
// by `hasMatch`. Method `'*'` matches any method. Later routes win
// over earlier ones, so a test can override a default. An unmatched request
// gets [fallback] (404 by default) and is still recorded.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the fake server received.
class FakeRequest {
  FakeRequest(this.options);

  final RequestOptions options;

  String get method => options.method.toUpperCase();
  Uri get uri => options.uri;
  String get path => options.uri.path;
  Map<String, String> get query => options.uri.queryParameters;
  Map<String, dynamic> get headers => options.headers;

  /// The raw request body (`Map`, `List`, `String`, `FormData`, or null).
  Object? get data => options.data;

  /// The body as a JSON map: a Map body as-is, a String body decoded, else
  /// empty.
  Map<String, dynamic> get json {
    final d = options.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.isNotEmpty) {
      final decoded = jsonDecode(d);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  @override
  String toString() => '$method $uri';
}

/// What a route answers with.
class FakeReply {
  FakeReply._(this.status, this.body, this.headers);

  /// [data] JSON-encoded with a JSON content type.
  factory FakeReply.json(int status, Object? data) => FakeReply._(
        status,
        jsonEncode(data),
        {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  /// A status with an empty body, e.g. `FakeReply.status(204)` or `(500)`.
  factory FakeReply.status(int status) => FakeReply._(status, '', const {});

  /// A plain-text body, e.g. a proxy's HTML error page.
  factory FakeReply.text(int status, String body) => FakeReply._(
        status,
        body,
        {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );

  final int status;
  final String body;
  final Map<String, List<String>> headers;

  ResponseBody toResponseBody() =>
      ResponseBody.fromString(body, status, headers: headers);
}

/// Exact match, or a suffix match on whole segments: `clients/c1` matches
/// `/api/v1/clients/c1` but `ients/c1` does not. Leading slashes are optional.
bool _pathMatches(String requestPath, String route) {
  final r = route.startsWith('/') ? route : '/$route';
  return requestPath == r || requestPath.endsWith(r);
}

typedef FakeHandler = FutureOr<FakeReply> Function(FakeRequest request);

class _Route {
  _Route(this.method, this.path, this.handler);

  final String method;
  final Pattern path;
  final FakeHandler handler;

  bool matches(FakeRequest r) {
    if (method != '*' && method.toUpperCase() != r.method) return false;
    final p = path;
    if (p is RegExp) return p.hasMatch(r.path);
    return _pathMatches(r.path, p.toString());
  }
}

class FakeHttp implements HttpClientAdapter {
  FakeHttp({FakeHandler? fallback})
      : fallback = fallback ??
            ((r) => FakeReply.json(404, {'message': 'No fake route for $r'}));

  /// Answers any request no route matched.
  final FakeHandler fallback;

  final _routes = <_Route>[];

  /// Every request received, in order (matched or not).
  final requests = <FakeRequest>[];

  /// Route [method] (`'GET'`, `'POST'`, ..., or `'*'`) + [path] (a String
  /// exact/suffix match, or a [RegExp]) to [handler].
  void on(String method, Pattern path, FakeHandler handler) =>
      _routes.add(_Route(method, path, handler));

  /// Shorthand for a route that always answers [data] as JSON.
  void onJson(String method, Pattern path, Object? data, {int status = 200}) =>
      on(method, path, (_) => FakeReply.json(status, data));

  /// Shorthand for a route that always answers a bare [status].
  void onStatus(String method, Pattern path, int status) =>
      on(method, path, (_) => FakeReply.status(status));

  /// Requests that went to [path] (exact or suffix match), optionally with
  /// [method].
  List<FakeRequest> requestsTo(String path, {String? method}) => requests
      .where((r) =>
          _pathMatches(r.path, path) &&
          (method == null || r.method == method.toUpperCase()))
      .toList();

  /// A [Dio] wired to this server. Keep a trailing slash on [baseUrl]: Dio
  /// concatenates it with relative paths such as `ApiEndpoints` constants.
  Dio dio({String baseUrl = 'https://api.test.local/api/v1/'}) =>
      Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final req = FakeRequest(options);
    requests.add(req);
    for (final route in _routes.reversed) {
      if (route.matches(req)) {
        return (await route.handler(req)).toResponseBody();
      }
    }
    return (await fallback(req)).toResponseBody();
  }

  @override
  void close({bool force = false}) {}
}
