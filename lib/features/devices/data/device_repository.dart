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

  String _normalizeMac(String macAddress) => macAddress.trim().toUpperCase();

  /// Get all registered devices from backend.
  Future<List<DeviceInfo>> getRegisteredDevices() => _remoteSource.getDevices();

  /// Get devices for a specific organization.
  Future<List<DeviceInfo>> getDevicesByOrg(String orgId) =>
      _remoteSource.getDevicesByOrg(orgId);

  /// Register a new device.
  Future<void> registerDevice({
    required String name,
    required String macAddress,
    required List<int> organizationIds,
  }) async {
    final normalizedMac = _normalizeMac(macAddress);
    // Match web flow: if sensor already exists globally, update it by adding
    // org mapping instead of creating again via POST /admin/sensors.
    final existing = (await _remoteSource.getDevices()).where((device) {
      return _normalizeMac(device.macAddress) == normalizedMac;
    }).toList();

    if (existing.isNotEmpty && existing.first.id != null) {
      await _remoteSource.updateDevice(
        sensorId: existing.first.id!,
        name: name,
        macAddress: normalizedMac,
        addOrgIds: organizationIds,
        removeOrgIds: const [],
      );
      return;
    }

    await _remoteSource.registerDevice(
      name: name,
      macAddress: normalizedMac,
      organizationIds: organizationIds,
    );
  }

  /// Update device name.
  Future<DeviceInfo> renameDevice(String sensorId, String newName) =>
      _remoteSource.updateDevice(sensorId: sensorId, name: newName);

  /// Remove a device from the current organization and clear local BLE pairing.
  Future<void> removeDeviceFromOrganization({
    required String sensorId,
    required int organizationId,
    required String macAddress,
  }) async {
    await _remoteSource.updateDevice(
      sensorId: sensorId,
      removeOrgIds: [organizationId],
    );
    await _bleRepository.removePairedDevice(_normalizeMac(macAddress));
  }

  /// Watch paired devices from local DB.
  Stream<List<PairedDevice>> watchPairedDevices() => _db.watchPairedDevices();

  /// Remove a paired device.
  Future<void> forgetDevice(String macAddress) =>
      _bleRepository.removePairedDevice(_normalizeMac(macAddress));

  Future<void> locateDevice(String macAddress, {bool beeping = true}) =>
      _remoteSource.publishMqttPayload({
        'mac': _normalizeMac(macAddress),
        'beeping': beeping,
      });

  Future<void> runDiagnostics(String macAddress, {bool selfCheck = true}) =>
      _remoteSource.publishMqttPayload({
        'mac': _normalizeMac(macAddress),
        'selfCheck': selfCheck,
      });
}
