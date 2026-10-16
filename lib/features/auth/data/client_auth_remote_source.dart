import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/jwt.dart';

/// An authenticated at-home client session (parity with the web `/client`
/// login). Distinct from the practitioner [UserProfile] session — a client is
/// its own auth entity gated on an active device lease.
class ClientSession {
  final String accessToken;
  final String refreshToken;
  final String clientId;
  final String clientName;
  final String? leaseId;
  final String? organizationId;
  final String? macAddress;

  const ClientSession({
    required this.accessToken,
    required this.refreshToken,
    required this.clientId,
    required this.clientName,
    this.leaseId,
    this.organizationId,
    this.macAddress,
  });

  factory ClientSession.fromJson(Map<String, dynamic> json) {
    final client = json['client'];
    final c = client is Map ? Map<String, dynamic>.from(client) : const {};
    final accessToken =
        (json['accessToken'] as String? ?? '').withoutBearerPrefix;
    // The access token carries the authoritative `leaseId` claim for this
    // login (see the token payload: {id, leaseId, organizationId, role:
    // "client", ...}). Prefer it over the client record's copy, which is only
    // present when the login response embeds the lease fields.
    final tokenLeaseId = jwtStringClaim(accessToken, 'leaseId');
    final bodyLeaseId = c['leaseId']?.toString().trim();
    return ClientSession(
      accessToken: accessToken,
      refreshToken: (json['refreshToken'] as String? ?? '').withoutBearerPrefix,
      clientId: (c['_id'] ?? c['id'] ?? '').toString(),
      clientName: (c['clientName'] ?? '').toString(),
      leaseId: tokenLeaseId ??
          ((bodyLeaseId == null || bodyLeaseId.isEmpty) ? null : bodyLeaseId),
      organizationId: c['organizationId']?.toString() ??
          jwtStringClaim(accessToken, 'organizationId'),
      macAddress: c['macAddress']?.toString(),
    );
  }
}

final clientAuthRemoteSourceProvider =
    Provider<ClientAuthRemoteSource>((ref) => ClientAuthRemoteSource());

/// Talks to the Node client-auth endpoints. Uses a bare Dio (no auth
/// interceptor) so a failed client login can never trigger the practitioner
/// refresh/clear-token flow, and so the login itself is never blocked by a
/// stored-token read (same reasoning as the interceptor's auth-route skip).
class ClientAuthRemoteSource {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.nodeBaseUrl,
    connectTimeout: AppConstants.connectTimeout,
    receiveTimeout: AppConstants.receiveTimeout,
    headers: const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  /// `POST auth/login` with `{clientName, password}`.
  Future<ClientSession> login({
    required String clientName,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.clientAuthLogin,
        data: {'clientName': clientName, 'password': password},
      );
      return ClientSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw AuthException(
        _message(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Translate a client-login error, surfacing the backend "Lease is not
  /// active" message verbatim (the key signal for a deactivated lease).
  String _message(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Unable to reach the server. Please check your connection.';
      default:
        break;
    }

    final data = e.response?.data;
    final serverMessage = data is Map ? data['message'] : null;
    if (serverMessage is String && serverMessage.trim().isNotEmpty) {
      return serverMessage; // e.g. "Lease is not active" / "Invalid credentials"
    }
    if (e.response?.statusCode == 401) {
      return 'Invalid credentials or the lease is not active.';
    }
    return 'Login failed. Please try again.';
  }
}
