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

/// Mirrors the web app's `getUserRole()` (Hydrawav3-ai/lib/rbac.ts) so mobile
/// classifies the same access-token claims the same way: a client token
/// carries a singular `role: "client"` claim; staff tokens carry a `roles`
/// array whose first entry is collapsed to `'ADMIN'`/`'PRACTITIONER'` when it
/// contains those words (e.g. `'PRIMARY ACCOUNT - ADMIN'` → `'ADMIN'`), or
/// returned as-is otherwise. Returns `null` when the token has no role claim.
String? userRoleFromClaims(Map<String, dynamic>? claims) {
  if (claims == null) return null;

  final singularRole = claims['role'];
  if (singularRole is String && singularRole.trim().toLowerCase() == 'client') {
    return 'CLIENT';
  }

  final rolesClaim = claims['roles'];
  final roles = rolesClaim is List
      ? rolesClaim.map((e) => e.toString()).toList()
      : const <String>[];
  if (roles.isEmpty) return null;

  final first = roles.first;
  final upper = first.toUpperCase();
  if (upper.contains('ADMIN')) return 'ADMIN';
  if (upper.contains('PRACTITIONER')) return 'PRACTITIONER';
  return first;
}

/// Exact match for the `'PRIMARY ACCOUNT - ADMIN'` role — [userRoleFromClaims]
/// collapses that (and every other admin variant) down to `'ADMIN'`, so this
/// is the only way to tell a primary account admin apart from a plain admin
/// or practitioner. Mirrors the web app's `isPrimaryAccountAdmin()`.
bool isPrimaryAccountAdminFromClaims(Map<String, dynamic>? claims) {
  final rolesClaim = claims?['roles'];
  if (rolesClaim is! List) return false;
  return rolesClaim.any((role) =>
      role is String && role.trim().toUpperCase() == 'PRIMARY ACCOUNT - ADMIN');
}
