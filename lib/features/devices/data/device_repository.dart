import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_db.dart';
import '../../ble/data/ble_repository.dart';
import '../domain/device_model.dart';
import 'device_remote_source.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(
    remoteSource: ref.read(deviceRemoteSourceProvider),
    bleRepository: ref.read(bleRepositoryProvider),
    db: ref.read(databaseProvider),
  );
});

class DeviceRepository {
  final DeviceRemoteSource _remoteSource;
  final BleRepository _bleRepository;
  final AppDatabase _db;

  DeviceRepository({
    required DeviceRemoteSource remoteSource,
    required BleRepository bleRepository,
    required AppDatabase db,
  })  : _remoteSource = remoteSource,
        _bleRepository = bleRepository,
        _db = db;

  /// Get all registered devices from backend.
  Future<List<DeviceInfo>> getRegisteredDevices() =>
      _remoteSource.getDevices();

  /// Get devices for a specific organization.
  Future<List<DeviceInfo>> getDevicesByOrg(String orgId) =>
      _remoteSource.getDevicesByOrg(orgId);

  /// Register a new device.
  Future<DeviceInfo> registerDevice({
    required String name,
    required String macAddress,
    required List<int> organizationIds,
  }) async {
    final device = await _remoteSource.registerDevice(
      name: name,
      macAddress: macAddress,
      organizationIds: organizationIds,
    );

    // Also add to BLE paired devices
    await _bleRepository.renamePairedDevice(macAddress, name);

    return device;
  }

  /// Update device name.
  Future<DeviceInfo> renameDevice(String sensorId, String newName) =>
      _remoteSource.updateDevice(sensorId: sensorId, name: newName);

  /// Watch paired devices from local DB.
  Stream<List<PairedDevice>> watchPairedDevices() =>
      _db.watchPairedDevices();

  /// Remove a paired device.
  Future<void> forgetDevice(String macAddress) =>
      _bleRepository.removePairedDevice(macAddress);
}
