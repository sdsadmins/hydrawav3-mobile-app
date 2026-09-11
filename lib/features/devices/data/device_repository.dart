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

  /// Hydra units advertise BLE on a MAC adjacent (±1 in the last byte) to the
  /// registered WiFi MAC, and the BLE cache/connection is keyed by that BLE
  /// MAC. So to fully disconnect + forget a device we must target the
  /// registered MAC *and* its adjacent variants.
  List<String> _macCandidates(String macAddress) {
    final normalized = _normalizeMac(macAddress);
    final candidates = <String>{normalized};
    final parts = normalized.split(':');
    if (parts.length == 6) {
      final last = int.tryParse(parts.last, radix: 16);
      if (last != null) {
        for (final delta in const [1, -1]) {
          final next = (last + delta) & 0xFF;
          final variant = [...parts]
            ..[5] = next.toRadixString(16).padLeft(2, '0').toUpperCase();
          candidates.add(variant.join(':'));
        }
      }
    }
    return candidates.toList();
  }

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
    for (final mac in _macCandidates(macAddress)) {
      await _bleRepository.removePairedDevice(mac);
    }
  }

  /// Watch paired devices from local DB.
  Stream<List<PairedDevice>> watchPairedDevices() => _db.watchPairedDevices();

  /// Remove a paired device (and its adjacent BLE MAC variants).
  Future<void> forgetDevice(String macAddress) async {
    for (final mac in _macCandidates(macAddress)) {
      await _bleRepository.removePairedDevice(mac);
    }
  }

  /// Locate over BLE: JSON write `{"beeping": beeping}` to whichever of this
  /// device's MAC candidates (see [_macCandidates]) is currently connected.
  /// Used by the Device List screen, where the card is only shown for a
  /// BLE-connected unit. Works mid-session too (the write is a plain JSON
  /// frame the firmware handles alongside a running protocol).
  Future<void> locateDeviceViaBle(String macAddress,
      {bool beeping = true}) async {
    for (final mac in _macCandidates(macAddress)) {
      if (_bleRepository.isConnected(mac)) {
        final ok =
            await _bleRepository.writeJsonToDevice(mac, {'beeping': beeping});
        if (!ok) throw Exception('BLE write failed for $macAddress');
        return;
      }
    }
    throw Exception('Device not connected over BLE');
  }

  /// Locate over the server's MQTT bridge (web parity — `mqttConnect` on the
  /// web devices page): POST /mqtt/publish `{mac, beeping}`. Used by the
  /// Devices Fleet (register) screen, which lists WiFi-registered units that
  /// may not have a live BLE link to this phone.
  Future<void> locateDeviceViaMqtt(String macAddress,
      {bool beeping = true}) async {
    await _remoteSource.publishMqttPayload({
      'mac': _normalizeMac(macAddress),
      'beeping': beeping,
    });
  }

  /// Backwards-compatible alias — BLE locate (its long-standing behavior).
  Future<void> locateDevice(String macAddress, {bool beeping = true}) =>
      locateDeviceViaBle(macAddress, beeping: beeping);

  Future<void> runDiagnostics(String macAddress, {bool selfCheck = true}) =>
      _remoteSource.publishMqttPayload({
        'mac': _normalizeMac(macAddress),
        'selfCheck': selfCheck,
      });
}
