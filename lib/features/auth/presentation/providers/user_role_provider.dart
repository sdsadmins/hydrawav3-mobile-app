import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/jwt.dart';

/// The signed-in account's role, read straight from the stored access
/// token's claims — mirrors the web app's `getUserRole()`
/// (Hydrawav3-ai/lib/rbac.ts): `'ADMIN'`, `'PRACTITIONER'`, `'CLIENT'`, or
/// `null` when signed out / no role claim. `'PRIMARY ACCOUNT - ADMIN'`
/// collapses into `'ADMIN'` here — see [isPrimaryAccountAdminProvider] for
/// the exact-match check that distinguishes it.
final userRoleProvider = FutureProvider<String?>((ref) async {
  final token = await ref.read(secureStorageProvider).getAccessToken();
  return userRoleFromClaims(decodeJwtPayload(token));
});

/// True only for the exact `'PRIMARY ACCOUNT - ADMIN'` role claim — the
/// practitioner-org owner account, distinct from a plain `'ADMIN'` or
/// `'PRACTITIONER'`. Mirrors the web app's `isPrimaryAccountAdmin()`.
final isPrimaryAccountAdminProvider = FutureProvider<bool>((ref) async {
  final token = await ref.read(secureStorageProvider).getAccessToken();
  return isPrimaryAccountAdminFromClaims(decodeJwtPayload(token));
});
