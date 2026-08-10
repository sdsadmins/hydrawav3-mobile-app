import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/core/utils/jwt.dart';
import 'package:hydrawav3/features/auth/data/client_auth_remote_source.dart';

/// Build an unsigned-but-well-formed JWT around [payload] (signature is never
/// verified client-side).
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

// The real client access-token payload shape.
const _leasePayload = <String, dynamic>{
  'id': '6a72cf3c2e55905f23f250f9',
  'leaseId': '6a72cf3c2e55905f23f250f9a4269267',
  'organizationId': 493,
  'role': 'client',
  'type': 'access',
  'iat': 1785928901,
  'exp': 1786015301,
};

void main() {
  group('decodeJwtPayload', () {
    test('reads the claims of a well-formed token', () {
      expect(decodeJwtPayload(_jwt(_leasePayload)), _leasePayload);
    });

    test('returns null for malformed / empty tokens', () {
      expect(decodeJwtPayload(null), isNull);
      expect(decodeJwtPayload(''), isNull);
      expect(decodeJwtPayload('not-a-jwt'), isNull);
      expect(decodeJwtPayload('a.b'), isNull);
      expect(decodeJwtPayload('a.!!!not-base64!!!.c'), isNull);
    });

    test('jwtStringClaim stringifies and trims, null when absent', () {
      final token = _jwt(_leasePayload);
      expect(jwtStringClaim(token, 'leaseId'),
          '6a72cf3c2e55905f23f250f9a4269267');
      expect(jwtStringClaim(token, 'organizationId'), '493');
      expect(jwtStringClaim(token, 'nope'), isNull);
    });
  });

  group('ClientSession.fromJson', () {
    test('takes leaseId from the access-token claim', () {
      final session = ClientSession.fromJson({
        'accessToken': 'Bearer ${_jwt(_leasePayload)}',
        'refreshToken': _jwt(_leasePayload),
        'client': {
          '_id': '6a72cf3c2e55905f23f250f9',
          'clientName': 'home-user',
          'macAddress': 'AA:BB:CC:DD:EE:FF',
        },
      });

      expect(session.leaseId, '6a72cf3c2e55905f23f250f9a4269267');
      expect(session.organizationId, '493');
      expect(session.clientName, 'home-user');
    });

    test('falls back to the client record when the token carries no claim', () {
      final session = ClientSession.fromJson({
        'accessToken': _jwt(const {'id': 'x', 'role': 'client'}),
        'refreshToken': '',
        'client': {
          '_id': 'x',
          'clientName': 'home-user',
          'leaseId': '6a4503ee4bef3d827421ee6cac801c33',
        },
      });

      expect(session.leaseId, '6a4503ee4bef3d827421ee6cac801c33');
    });

    test('leaseId is null when neither source has one', () {
      final session = ClientSession.fromJson({
        'accessToken': '',
        'refreshToken': '',
        'client': {'_id': 'x', 'clientName': 'home-user', 'leaseId': ''},
      });

      expect(session.leaseId, isNull);
    });
  });
}
