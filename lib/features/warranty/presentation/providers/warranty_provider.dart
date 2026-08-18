import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/warranty_remote_source.dart';
import '../../domain/warranty_model.dart';

/// Warranty status for every device in the current org.
///
/// Org resolution matches every other org-scoped fetch in the app
/// (`wifiDevicesByOrgProvider`): the explicitly-selected org first, then the
/// org on the user's own profile. No org resolved → empty list rather than
/// guessing at "the first org available".
final warrantyByOrgProvider =
    FutureProvider.autoDispose<List<WarrantyRecord>>((ref) async {
  final auth = ref.watch(authStateProvider);
  final orgId = (auth.selectedOrgId?.isNotEmpty ?? false)
      ? auth.selectedOrgId
      : auth.user?.organizationId;
  if (orgId == null || orgId.isEmpty) return const <WarrantyRecord>[];
  return ref.read(warrantyRemoteSourceProvider).getWarranties(orgId);
});
