import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import '../storage/secure_storage.dart';
import '../utils/extensions.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

class AuthInterceptor extends Interceptor {
  final Ref _ref;
  bool _isRefreshing = false;
  final _refreshCompleter = <Completer<void>>[];

  AuthInterceptor(this._ref);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    print("FINAL HEADERS: ${options.headers}"); // 🔥 DEBUG
//     if (token != null && token.isNotEmpty) {
//   if (token.startsWith('Bearer ')) {
//     options.headers['Authorization'] = token;
//   } else {
//     options.headers['Authorization'] = 'Bearer $token';
//   }
// }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final success = await _refreshTokens();
      if (success) {
        // Retry the original request with new token
        final storage = _ref.read(secureStorageProvider);
        final newToken = await storage.getAccessToken();
        if (newToken != null) {
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          try {
            final response = await Dio().fetch(err.requestOptions);
            return handler.resolve(response);
          } catch (e) {
            return handler.next(err);
          }
        }
      }
      // Token refresh failed - clear tokens and let the error propagate
      final storage = _ref.read(secureStorageProvider);
      await storage.clearTokens();
    }
    handler.next(err);
  }

  Future<bool> _refreshTokens() async {
    if (_isRefreshing) {
      // Wait for the ongoing refresh to complete
      final completer = Completer<void>();
      _refreshCompleter.add(completer);
      await completer.future;
      return true;
    }

    _isRefreshing = true;

    try {
      final storage = _ref.read(secureStorageProvider);
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken == null) return false;

      final dio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.djangoBaseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $refreshToken',
        },
      ));

      final response = await dio.get(ApiEndpoints.refreshToken);
      final data = response.data;

      final newAccessToken =
          (data['JWT_ACCESS_TOKEN'] as String).withoutBearerPrefix;
      final newRefreshToken =
          (data['JWT_REFRESH_TOKEN'] as String).withoutBearerPrefix;

      await storage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );

      // Notify all waiting requests
      for (final completer in _refreshCompleter) {
        completer.complete();
      }
      _refreshCompleter.clear();

      return true;
    } catch (e) {
      // Notify all waiting requests of failure
      for (final completer in _refreshCompleter) {
        completer.completeError(e);
      }
      _refreshCompleter.clear();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }
}
