import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/utils/logger.dart';
import '../domain/onboarding_models.dart';

final onboardingRemoteSourceProvider = Provider<OnboardingRemoteSource>((ref) {
  return OnboardingRemoteSource();
});

/// Talks to the practitioner-onboarding endpoints. Uses a DEDICATED, clean Dio
/// (no auth interceptor): the user isn't logged in during onboarding, and the
/// request is authorized with an admin token fetched from a public proxy.
class OnboardingRemoteSource {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  /// GET the admin token from the public proxy (parity with web). The proxy may
  /// return JSON (`JWT_ACCESS_TOKEN`/`accessToken`/`token`) or a raw token string.
  Future<String> fetchAdminToken() async {
    try {
      final res = await _dio.get(
        ApiEndpoints.proxyCreateUserUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'ngrok-skip-browser-warning': 'true'},
        ),
      );
      final token = _extractToken(res.data);
      if (token == null || token.isEmpty) {
        throw const ServerException('Could not start account creation.');
      }
      return token;
    } on DioException catch (e) {
      appLogger.e('Onboarding: proxy token failed (${e.response?.statusCode})');
      throw ServerException(
        'Could not start account creation. Please try again.',
        statusCode: e.response?.statusCode,
      );
    }
  }

  String? _extractToken(dynamic raw) {
    if (raw == null) return null;
    // Try JSON first.
    if (raw is Map) {
      return _firstNonEmpty(raw);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        final fromJson = _firstNonEmpty(decoded);
        if (fromJson != null) return fromJson;
      }
    } catch (_) {
      // Not JSON — treat the body itself as the token.
    }
    return s;
  }

  String? _firstNonEmpty(Map map) {
    for (final key in const ['JWT_ACCESS_TOKEN', 'accessToken', 'token']) {
      final v = map[key]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// POST the onboarding application as multipart/form-data, authorized with the
  /// admin token. `data` is the JSON payload; the optional business logo and any
  /// certification documents are attached as files.
  Future<void> submitOnboarding({
    required Map<String, dynamic> data,
    required String adminToken,
    String? businessLogoPath,
    List<OnboardingCertification> certifications = const [],
  }) async {
    try {
      final formData = FormData();
      formData.fields.add(MapEntry('data', jsonEncode(data)));

      if (businessLogoPath != null && businessLogoPath.isNotEmpty) {
        formData.files.add(MapEntry(
          'businessLogo',
          await MultipartFile.fromFile(businessLogoPath),
        ));
      }
      for (final cert in certifications) {
        final path = cert.documentPath;
        if (path != null && path.isNotEmpty) {
          formData.files.add(MapEntry(
            'certifications',
            await MultipartFile.fromFile(path),
          ));
        }
      }

      const url =
          '${ApiEndpoints.djangoBaseUrl}${ApiEndpoints.practitionerOnboarding}';
      final res = await _dio.post(
        url,
        data: formData,
        options: Options(
          headers: {'Authorization': adminToken},
          // The endpoint accepts the application; don't throw on 2xx.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      appLogger.i('Onboarding: submitted (status ${res.statusCode})');
    } on DioException catch (e) {
      appLogger.e(
        'Onboarding: submit failed (status=${e.response?.statusCode}) '
        '${e.response?.data}',
      );
      final msg = (e.response?.data is Map
              ? e.response?.data['message']?.toString()
              : null) ??
          'Failed to submit. Please check your details and try again.';
      throw ServerException(msg, statusCode: e.response?.statusCode);
    }
  }
}
