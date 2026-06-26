import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/utils/logger.dart';
import '../domain/onboarding_models.dart';

final onboardingRemoteSourceProvider = Provider<OnboardingRemoteSource>((ref) {
  return OnboardingRemoteSource();
});

/// Talks to the practitioner-onboarding endpoints, replicating the web's exact
/// 4-call sequence (see [OnboardingController.submit]):
///   1) [createPractitioner]  → POST {node}/practitioners/onboarding (no auth)
///   2) [createOrganization]  → POST {primary}/admin/organizations (raw token)
///   3) [uploadCertificate]   → POST {primary-api}/certificates/upload (raw token)
///   4) [updateUserAccount]   → PUT  {primary}/admin/user/accounts/{id} (raw token)
///
/// Uses a DEDICATED, clean Dio (no auth interceptor): the user isn't logged in
/// during onboarding; calls 2–4 are authorized with the token returned by call 1
/// — sent as a RAW token (no `Bearer ` prefix), exactly like the web.
class OnboardingRemoteSource {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  /// The certificate-upload base: the primary base URL with its `/api/v1` suffix
  /// reduced to `/api/` (web: `BASE_URL.replace(/api\/v1\/?$/, "api/")`).
  static String get _certBaseUrl =>
      ApiEndpoints.djangoBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '/api/');

  // ── Call 1: create the practitioner account (returns userId + token) ─────────
  /// POST {node}/practitioners/onboarding — JSON, no auth. Returns the created
  /// `userId` and the auth `token` used to authorize calls 2–4.
  Future<({String userId, String token})> createPractitioner(
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _dio.post(
        '${ApiEndpoints.nodeBaseUrl}practitioners/onboarding',
        data: data,
        options: Options(headers: const {'Content-Type': 'application/json'}),
      );
      final body = res.data;
      final userId = _extractUserId(body);
      final token = _extractToken(body);
      if (userId == null || token == null) {
        appLogger.e('Onboarding: create missing userId/token in ${res.data}');
        throw const ServerException(
            'Account was created but the server response was incomplete.');
      }
      appLogger.i('Onboarding: practitioner created (userId=$userId)');
      return (userId: userId, token: token);
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to create your account.');
    }
  }

  // ── Call 2: create the organization (returns orgId) ──────────────────────────
  /// POST {primary}/admin/organizations — JSON, raw token. Returns the org id.
  Future<String> createOrganization(
    Map<String, dynamic> data,
    String token,
  ) async {
    try {
      final res = await _dio.post(
        '${ApiEndpoints.djangoBaseUrl}${ApiEndpoints.organizations}',
        data: data,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        }),
      );
      final orgId = _extractOrgId(res.data);
      if (orgId == null) {
        appLogger.e('Onboarding: org create missing id in ${res.data}');
        throw const ServerException('Could not read the created business id.');
      }
      appLogger.i('Onboarding: organization created (id=$orgId)');
      return orgId;
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to create your business.');
    }
  }

  // ── Call 3: upload a certificate document (optional, best-effort) ────────────
  /// POST {primary-api}/certificates/upload?... — multipart `file`, raw token.
  /// Returns true on success; never throws (certs are optional on the web too).
  Future<bool> uploadCertificate({
    required String userId,
    required OnboardingCertification cert,
    required String token,
  }) async {
    final path = cert.documentPath;
    if (path == null || path.isEmpty) return false;
    try {
      final query = <String, dynamic>{
        'userId': userId,
        'certificationName': cert.name,
        if (cert.issuingOrganization.isNotEmpty)
          'issuingOrganization': cert.issuingOrganization,
        if (cert.issueDate.isNotEmpty) 'issueDate': cert.issueDate,
        if (cert.expirationDate.isNotEmpty)
          'expirationDate': cert.expirationDate,
      };
      final formData = FormData()
        ..files.add(MapEntry('file', await MultipartFile.fromFile(path)));
      await _dio.post(
        '${_certBaseUrl}certificates/upload',
        data: formData,
        queryParameters: query,
        options: Options(headers: {'Authorization': token}),
      );
      appLogger.i('Onboarding: certificate uploaded (${cert.name})');
      return true;
    } catch (e) {
      // Optional — warn but don't block onboarding (web parity).
      appLogger.w('Onboarding: certificate upload failed (${cert.name}): $e');
      return false;
    }
  }

  // ── Call 4: link the organization to the practitioner account ────────────────
  /// PUT {primary}/admin/user/accounts/{userId} — JSON, raw token.
  Future<void> updateUserAccount(
    String userId,
    Map<String, dynamic> data,
    String token,
  ) async {
    try {
      await _dio.put(
        '${ApiEndpoints.djangoBaseUrl}${ApiEndpoints.userAccountById(userId)}',
        data: data,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        }),
      );
      appLogger.i('Onboarding: account linked to org (userId=$userId)');
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to finish setting up your account.');
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────────
  ServerException _asServerException(DioException e, String fallback) {
    appLogger.e(
      'Onboarding: request failed (status=${e.response?.statusCode}) '
      '${e.response?.data}',
    );
    final data = e.response?.data;
    final msg = (data is Map ? data['message']?.toString() : null) ?? fallback;
    return ServerException(msg, statusCode: e.response?.statusCode);
  }

  static String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Created-practitioner id (web reads `data.userId`).
  static String? _extractUserId(dynamic d) {
    if (d is! Map) return null;
    return _str(d['userId']) ??
        _str(d['id']) ??
        _str((d['data'] is Map) ? d['data']['userId'] : null);
  }

  /// Auth token from the create response (web fallback chain).
  static String? _extractToken(dynamic d) {
    if (d is! Map) return null;
    final direct = _str(d['JWT_ACCESS_TOKEN']) ??
        _str(d['accessToken']) ??
        _str(d['access_token']) ??
        _str(d['token']);
    if (direct != null) return direct;
    final nested = d['data'];
    if (nested is Map) {
      final n = _str(nested['JWT_ACCESS_TOKEN']) ??
          _str(nested['accessToken']) ??
          _str(nested['token']);
      if (n != null) return n;
    }
    final tokens = d['tokens'];
    if (tokens is Map) {
      final t = _str(tokens['accessToken']) ?? _str(tokens['access']);
      if (t != null) return t;
    }
    return null;
  }

  /// Created-org id (web: `od?.id ?? od?.organizationId ?? od?.organisation?.id ?? od?.data?.id`).
  static String? _extractOrgId(dynamic d) {
    if (d is! Map) return null;
    return _str(d['id']) ??
        _str(d['organizationId']) ??
        _str((d['organisation'] is Map) ? d['organisation']['id'] : null) ??
        _str((d['data'] is Map) ? d['data']['id'] : null);
  }
}
