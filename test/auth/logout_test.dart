// [FIX-16] Logging out while something is listening to
// `wifiDevicesByOrgProvider` must complete — the provider watches
// authStateProvider and re-runs on its own, so the auth notifier must not
// invalidate it (that used to raise a CircularDependencyError and abort the
// logout) — and must leave the practitioner signed out.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/data/auth_repository.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/ble/data/ble_repository.dart';
import 'package:hydrawav3/features/devices/data/device_repository.dart';
import 'package:hydrawav3/features/devices/domain/device_model.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/splash/presentation/providers/app_bootstrap_provider.dart';

class _FakeAuthRepo implements AuthRepository {
  int logoutCalls = 0;
  int clearOrgCalls = 0;

  @override
  Future<void> logout() async => logoutCalls++;
  @override
  Future<void> clearSelectedOrganization() async => clearOrgCalls++;
  @override
  Future<void> saveSelectedOrganization(String orgId, String orgName) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeBle implements BleRepository {
  int disconnects = 0;

  @override
  Future<void> disconnectAll() async => disconnects++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDevices implements DeviceRepository {
  final fetchedOrgs = <String>[];

  @override
  Future<List<DeviceInfo>> getDevicesByOrg(String orgId) async {
    fetchedOrgs.add(orgId);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test(
    '[FIX-16] logout completes while wifiDevicesByOrgProvider is listened to '
    'and ends unauthenticated',
    () async {
      final repo = _FakeAuthRepo();
      final ble = _FakeBle();
      final devices = _FakeDevices();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        bleRepositoryProvider.overrideWithValue(ble),
        deviceRepositoryProvider.overrideWithValue(devices),
      ]);
      addTearDown(container.dispose);

      // Signed in with an organization, so the devices provider has an org
      // to fetch for.
      final auth = container.read(authStateProvider.notifier);
      auth.enterDemoMode();
      await auth.setOrganization('1', 'Gulf Coast Tarpons');
      container.read(appWarmedUpProvider.notifier).state = true;

      // Something (the Session Plan screen, in the app) is watching the
      // devices for this org the whole time.
      final seen = <AsyncValue<List<DeviceInfo>>>[];
      container.listen<AsyncValue<List<DeviceInfo>>>(
        wifiDevicesByOrgProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      await container.read(wifiDevicesByOrgProvider.future);
      expect(devices.fetchedOrgs, ['1']);

      // The logout itself: must not throw (CircularDependencyError or
      // otherwise) and must finish.
      await expectLater(auth.logout(), completes);

      final state = container.read(authStateProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.isInitialized, isTrue,
          reason: 'router goes straight to login, not splash');
      expect(state.selectedOrgId, isNull);
      expect(state.user, isNull);

      expect(repo.logoutCalls, 1);
      expect(repo.clearOrgCalls, 1);
      expect(ble.disconnects, 1);
      expect(container.read(appWarmedUpProvider), isFalse);

      // The devices provider re-ran off the auth change by itself: with no
      // org it resolves to an empty list without another fetch.
      expect(await container.read(wifiDevicesByOrgProvider.future), isEmpty);
      expect(devices.fetchedOrgs, ['1']);
      expect(seen.last.hasValue, isTrue);
      expect(seen.last.value, isEmpty);
    },
  );
}
