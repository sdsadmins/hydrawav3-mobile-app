import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/device_repository.dart';
import '../../domain/device_model.dart';

/// WiFi/Cloud devices (sensors) for the logged-in user's organization.
///
/// These are NOT BLE devices; they are the backend-registered devices that can
/// receive commands via MQTT/API.
///
/// Org resolution order:
///   1. The org the user explicitly selected (`selectedOrgId`).
///   2. The org attached to the user's profile (`user.organizationId`).
/// If neither is available we return an empty list. We deliberately do NOT
/// fall back to "the first org in /admin/organizations" — that showed another
/// org's devices (i.e. "previous logged devices") whenever the profile didn't
/// carry an organization id.
final wifiDevicesByOrgProvider = FutureProvider<List<DeviceInfo>>((ref) async {
  final auth = ref.watch(authStateProvider);

  final orgId = (auth.selectedOrgId?.isNotEmpty ?? false)
      ? auth.selectedOrgId
      : auth.user?.organizationId;

  if (orgId == null || orgId.isEmpty) return const <DeviceInfo>[];

  final repo = ref.read(deviceRepositoryProvider);
  return repo.getDevicesByOrg(orgId);
});
