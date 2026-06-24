import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ble_repository.dart';
import '../../domain/ble_device_model.dart';

final bleConnectionStatesProvider =
    StreamProvider<Map<String, BleConnectionStatus>>((ref) async* {
  final repo = ref.read(bleRepositoryProvider);
  // The connection-state stream is a broadcast controller, which does NOT
  // replay its current value to a new listener. The connected-device card only
  // subscribes once the first paired device appears — which happens right after
  // a first-time connect, i.e. AFTER the "connected" event was already emitted.
  // Seed with the current snapshot so a late subscriber reflects the live state
  // immediately instead of waiting for the next change (card never appearing).
  yield repo.currentConnectionStates;
  yield* repo.connectionStates;
});

final bleBatteryLevelsProvider = StreamProvider<Map<String, int>>((ref) async* {
  final repo = ref.read(bleRepositoryProvider);
  yield repo.currentBatteryLevels;
  yield* repo.batteryLevels;
});

final connectedDeviceIdsProvider = Provider<List<String>>((ref) {
  return ref.read(bleRepositoryProvider).connectedDeviceIds;
});

final bleNotificationsProvider = StreamProvider((ref) {
  return ref.read(bleRepositoryProvider).notifications;
});

final bleProvisioningIdsProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});

final bleDeviceStatusProvider =
    Provider.family<BleConnectionStatus, String>((ref, deviceId) {
  final states = ref.watch(bleConnectionStatesProvider);
  return states.when(
    data: (map) => map[deviceId] ?? BleConnectionStatus.disconnected,
    loading: () => BleConnectionStatus.disconnected,
    error: (_, __) => BleConnectionStatus.error,
  );
});
