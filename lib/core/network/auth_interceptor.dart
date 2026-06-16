import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import '../storage/secure_storage.dart';
import '../utils/extensions.dart';
import 'dio_client.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

class AuthInterceptor extends Interceptor {
  final Ref _ref;
  bool _isRefreshing = false;
  final _refreshCompleters = <Completer<void>>[];

  AuthInterceptor(this._ref);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // The login and token-refresh endpoints never need a stored token. Skipping
    // the secure-storage read for them keeps a hung/corrupted Android keystore
    // from ever freezing sign-in: otherwise the read could block here, the HTTP
    // request would never start, Dio's timeouts wouldn't apply, and the user
    // would see an infinite login spinner with no error.
    final path = options.path;
    final isAuthRoute = path.contains(ApiEndpoints.login) ||
        path.contains(ApiEndpoints.refreshToken);

    if (!isAuthRoute) {
      try {
        final storage = _ref.read(secureStorageProvider);
        final token = await storage.getAccessToken();
        final cleanToken = token?.withoutBearerPrefix;

        if (cleanToken != null && cleanToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $cleanToken';
        }
      } catch (e) {
        // Never let token attachment block the request — proceed unauthenticated
        // and let the normal 401 flow handle it.
        print('🔵 AUTH INTERCEPTOR: token read failed, proceeding: $e');
      }
    }

    print('🔵 REQUEST: ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Helpful for diagnosing Samsung "spinner" reports: log status + body.
    print('🔴 ERROR: ${err.requestOptions.method} ${err.requestOptions.path}');
    print('🔴 STATUS: ${err.response?.statusCode}');
    print('🔴 RESPONSE: ${err.response?.data}');
    print('🔴 MESSAGE: ${err.message}');

    // Only attempt a refresh+retry once per request. Retrying via
    // `djangoDio.fetch()` re-runs the whole interceptor chain, so a request
    // that keeps returning 401 (e.g. a role with no access to the endpoint)
    // would otherwise loop forever — 401 → refresh → retry → 401 → … — and
    // the caller's Future would never complete (infinite spinner). Once we've
    // retried, propagate the 401 so the caller can handle it (e.g. show an
    // empty device list).
    if (err.response?.statusCode != 401 ||
        err.requestOptions.extra['__authRetried__'] == true) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      final storage = _ref.read(secureStorageProvider);
      await storage.clearTokens();
      handler.next(err);
      return;
    }

    final storage = _ref.read(secureStorageProvider);
    final newToken = await storage.getAccessToken();
    final cleanToken = newToken?.withoutBearerPrefix;

    if (cleanToken == null || cleanToken.isEmpty) {
      handler.next(err);
      return;
    }

    err.requestOptions.headers['Authorization'] = 'Bearer $cleanToken';
    // Mark so a second 401 on the retry won't trigger another refresh loop.
    err.requestOptions.extra['__authRetried__'] = true;

    try {
      // Reuse the original configured Dio instance with all interceptors and settings
      final response =
          await _ref.read(djangoDioProvider).fetch<dynamic>(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      print(
          'RETRY AFTER TOKEN REFRESH FAILED: ${retryErr.response?.statusCode}');
      handler.next(retryErr);
    }
  }

  Future<bool> _refreshTokens() async {
    if (_isRefreshing) {
      final completer = Completer<void>();
      _refreshCompleters.add(completer);
      try {
        await completer.future;
        return true;
      } catch (_) {
        return false;
      }
    }

    _isRefreshing = true;

    try {
      final storage = _ref.read(secureStorageProvider);
      final refreshToken = await storage.getRefreshToken();
      final cleanRefreshToken = refreshToken?.withoutBearerPrefix;

      final dio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.djangoBaseUrl,
        headers: const {'Content-Type': 'application/json'},
      ));

      Response<dynamic> response;

      try {
        response = await dio.get(
          ApiEndpoints.refreshToken,
          options: Options(
            headers: {
              if (cleanRefreshToken != null && cleanRefreshToken.isNotEmpty)
                'Authorization': 'Bearer $cleanRefreshToken',
            },
          ),
        );
      } on DioException catch (e) {
        print(
            'REFRESH TOKEN FAILED WITH AUTH: ${e.response?.statusCode} - ${e.response?.data}');
        rethrow;
      }

      print('REFRESH RESPONSE RAW: ${response.data}');

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Refresh token response is null');
      }

      // Try multiple key patterns to handle backend contract variations
      String? newAccessToken = data['JWT_ACCESS_TOKEN'] as String?;
      String? newRefreshToken = data['JWT_REFRESH_TOKEN'] as String?;

      // Fallback to alternative key names if primary keys not found
      if (newAccessToken == null) {
        newAccessToken = data['access'] as String? ??
            data['token'] as String? ??
            data['accessToken'] as String?;
      }
      if (newRefreshToken == null) {
        newRefreshToken = data['JWT_REFRESH_TOKEN'] as String? ??
            data['refresh'] as String? ??
            data['refresh_token'] as String? ??
            data['refreshToken'] as String?;
      }

      if (newAccessToken == null || newAccessToken.isEmpty) {
        throw Exception(
            'No access token in refresh response: ${data.keys.toList()}');
      }

      final cleanAccessToken = newAccessToken.withoutBearerPrefix;
      final cleanRefreshTokenResult =
          (newRefreshToken ?? cleanRefreshToken)?.withoutBearerPrefix;

      await storage.saveTokens(
        accessToken: cleanAccessToken,
        refreshToken: cleanRefreshTokenResult ?? '',
      );

      print('✅ TOKENS REFRESHED SUCCESSFULLY');

      for (final completer in _refreshCompleters) {
        completer.complete();
      }
      _refreshCompleters.clear();

      return true;
    } catch (e) {
      print('❌ TOKEN REFRESH FAILED: $e');
      for (final completer in _refreshCompleters) {
        completer.completeError(e);
      }
      _refreshCompleters.clear();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }
}
