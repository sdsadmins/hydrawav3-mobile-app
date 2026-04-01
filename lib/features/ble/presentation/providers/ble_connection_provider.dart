import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ble_repository.dart';
import '../../domain/ble_device_model.dart';

final bleConnectionStatesProvider =
    StreamProvider<Map<String, BleConnectionStatus>>((ref) {
  return ref.read(bleRepositoryProvider).connectionStates;
});

final connectedDeviceIdsProvider = Provider<List<String>>((ref) {
  return ref.read(bleRepositoryProvider).connectedDeviceIds;
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
