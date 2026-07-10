import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';

final organizationRepositoryProvider = Provider<OrganizationRepository>(
  (ref) => OrganizationRepository(ref),
);

/// Write-path for organisations (the read stays inline in the page's
/// `organizationProvider`). Mirrors the web's create flow on the org-selection
/// page: create an org, then attach it to the logged-in account.
///
/// Uses the authenticated [djangoDioProvider] (its interceptor attaches the
/// token) — the user is already logged in on this screen, unlike the onboarding
/// flow which runs before login with a dedicated no-auth Dio.
class OrganizationRepository {
  final Ref _ref;
  OrganizationRepository(this._ref);

  /// Create an org and link it to [userId]'s account (web parity — the web's
  /// `handleCreateOrganization` does createOrganization → getUserByUserId →
  /// updateUserAccount with `addOrganisations`).
  ///
  /// [orgBody] = `{ name, mail, address, age, phone }`. Returns the new org id.
  Future<String> createAndLinkOrganization({
    required String userId,
    required Map<String, dynamic> orgBody,
  }) async {
    final dio = _ref.read(djangoDioProvider);

    // 1) Create the org.
    final String orgId;
    try {
      final res = await dio.post(ApiEndpoints.organizations, data: orgBody);
      final extracted = _extractOrgId(res.data);
      if (extracted == null) {
        appLogger.e('CreateOrg: org create missing id in ${res.data}');
        throw const ServerException('Could not read the created business id.');
      }
      orgId = extracted;
      appLogger.i('CreateOrg: organization created (id=$orgId)');
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to create your organization.');
    }

    // 2) Fetch the current account, then 3) PUT it back with the org attached
    //    (web spreads the fetched account + addOrganisations/removeOrganisations).
    try {
      final acc = await dio.get(ApiEndpoints.userAccountById(userId));
      final account = Map<String, dynamic>.from(acc.data as Map);
      final body = {
        ...account,
        'addOrganisations': [int.tryParse(orgId) ?? orgId],
        'removeOrganisations': const <Object>[],
      };
      await dio.put(ApiEndpoints.userAccountById(userId), data: body);
      appLogger.i('CreateOrg: account linked to org (userId=$userId)');
    } on DioException catch (e) {
      throw _asServerException(e, 'Failed to link the organization to your account.');
    }

    return orgId;
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  ServerException _asServerException(DioException e, String fallback) {
    appLogger.e(
      'CreateOrg: request failed (status=${e.response?.statusCode}) '
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

  /// Created-org id (web: `od?.id ?? od?.organizationId ?? od?.organisation?.id ?? od?.data?.id`).
  static String? _extractOrgId(dynamic d) {
    if (d is! Map) return null;
    return _str(d['id']) ??
        _str(d['organizationId']) ??
        _str((d['organisation'] is Map) ? d['organisation']['id'] : null) ??
        _str((d['data'] is Map) ? d['data']['id'] : null);
  }
}
