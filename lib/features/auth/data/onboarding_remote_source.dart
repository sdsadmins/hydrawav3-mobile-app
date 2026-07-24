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
///   1) [createPractitioner]  → POST {node}user/onboarding (no auth)
///   2) [createOrganization]  → POST {node}user/organizations (raw token)
///   3) [uploadCertificate]   → POST {primary-api}/certificates/upload (raw token)
///   4) [updateUserAccount]   → PUT  {node}user/accounts/{id} (raw token)
///
/// Calls 1, 2 and 4 used to live on Django (`/admin/...`); the web moved them to
/// the Node backend under `user/*`, and this mirrors that. The certificate
/// upload is the only step still served by Django.
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

  // ── Account types (public) ──────────────────────────────────────────────────
  /// GET {node}user/account-types — JSON, no auth. Populates the Account Type
  /// select on step 1. The list comes back either at the top level or wrapped in
  /// `data` (web parity), and only `id` + `name` are read off each item.
  Future<List<AccountTypeOption>> getAccountTypes() async {
    try {
      final res = await _dio.get(
        '${ApiEndpoints.nodeBaseUrl}${ApiEndpoints.onboardingAccountTypes}',
        options: Options(headers: const {'Content-Type': 'application/json'}),
      );
      final body = res.data;
      final list = body is List
          ? body
          : (body is Map && body['data'] is List)
              ? body['data'] as List
              : const [];
      return [
        for (final raw in list)
          if (raw is Map)
            AccountTypeOption(
              id: _str(raw['id']) ?? '',
              name: _str(raw['name']) ?? '',
            ),
      ].where((a) => a.id.isNotEmpty).toList();
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to load account types.');
    }
  }

  // ── Sports catalogue (needs the create-step token) ──────────────────────────
  /// GET {node}sports?page=1&perPage=100 — raw token. Only active sports are
  /// returned to the caller; the list sits under `data` (web parity).
  Future<List<SportOption>> getSports(String token) async {
    try {
      final res = await _dio.get(
        '${ApiEndpoints.nodeBaseUrl}${ApiEndpoints.sports}',
        queryParameters: const {'page': 1, 'perPage': 100},
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        }),
      );
      final body = res.data;
      final list = body is List
          ? body
          : (body is Map && body['data'] is List)
              ? body['data'] as List
              : const [];
      final sports = <SportOption>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        // `isActive` absent → treat as active rather than hiding the sport.
        if (raw['isActive'] == false) continue;
        final id = _str(raw['_id']) ?? _str(raw['id']);
        if (id == null) continue;
        sports.add(SportOption(id: id, name: _str(raw['name']) ?? id));
      }
      return sports;
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to load sports.');
    }
  }

  // ── Call 1: create the practitioner account (returns userId + token) ─────────
  /// POST {node}user/onboarding — JSON, no auth. Returns the created `userId`
  /// and the auth `token` used to authorize calls 2–4.
  Future<({String userId, String token})> createPractitioner(
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _dio.post(
        '${ApiEndpoints.nodeBaseUrl}${ApiEndpoints.onboardingCreate}',
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
  /// POST {node}user/organizations — JSON, raw token. Returns the org id.
  Future<String> createOrganization(
    Map<String, dynamic> data,
    String token,
  ) async {
    try {
      final res = await _dio.post(
        '${ApiEndpoints.nodeBaseUrl}${ApiEndpoints.onboardingOrganizations}',
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
  /// PUT {node}user/accounts/{userId} — JSON, raw token.
  Future<void> updateUserAccount(
    String userId,
    Map<String, dynamic> data,
    String token,
  ) async {
    try {
      await _dio.put(
        '${ApiEndpoints.nodeBaseUrl}${ApiEndpoints.onboardingAccountById(userId)}',
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
    final raw = data is Map ? data['message'] : null;
    // Nest's ValidationPipe returns `message` as a LIST of field errors —
    // `toString()` on that renders a raw Dart list ("[a, b]") in the UI, so
    // join it into a sentence instead.
    final msg = raw is List
        ? raw.map((m) => m.toString()).where((m) => m.isNotEmpty).join('. ')
        : raw?.toString();
    return ServerException(
      (msg == null || msg.isEmpty) ? fallback : msg,
      statusCode: e.response?.statusCode,
    );
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
