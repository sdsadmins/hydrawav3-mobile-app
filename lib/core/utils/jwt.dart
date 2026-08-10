import 'dart:convert';

/// Decode the payload (2nd segment) of a JWT without verifying its signature.
///
/// Verification is the server's job — the app only reads claims the backend
/// already put there (e.g. the client token's `leaseId`). Returns `null` for
/// anything that isn't a well-formed three-part JWT with a JSON object payload,
/// so callers can fall back rather than crash on an unexpected token shape.
Map<String, dynamic>? decodeJwtPayload(String? token) {
  final raw = token?.trim();
  if (raw == null || raw.isEmpty) return null;

  final parts = raw.split('.');
  if (parts.length != 3) return null;

  try {
    // JWT uses base64url WITHOUT padding; base64Url.decode requires it.
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final json = jsonDecode(decoded);
    return json is Map ? Map<String, dynamic>.from(json) : null;
  } catch (_) {
    return null;
  }
}

/// Read a single string claim from [token]'s payload. Returns `null` when the
/// token can't be decoded, the claim is absent, or it decodes to an empty
/// string.
String? jwtStringClaim(String? token, String claim) {
  final value = decodeJwtPayload(token)?[claim];
  if (value == null) return null;
  final str = value.toString().trim();
  return str.isEmpty ? null : str;
}
