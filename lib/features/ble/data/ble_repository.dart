import 'package:drift/drift.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../domain/ble_command.dart';
import '../domain/ble_device_model.dart';
import '../services/ble_connector.dart';
import '../services/ble_scanner.dart';
import '../services/ble_treatment_writer.dart';

final bleRepositoryProvider = Provider<BleRepository>((ref) {
  return BleRepository(
    scanner: ref.read(bleScannerProvider),
    connector: ref.read(bleConnectorProvider),
    writer: ref.read(bleTreatmentWriterProvider),
    db: ref.read(databaseProvider),
  );
});

class BleRepository {
  final BleScanner _scanner;
  final BleConnector _connector;
  final BleTreatmentWriter _writer;
  final AppDatabase _db;

  BleRepository({
    required BleScanner scanner,
    required BleConnector connector,
    required BleTreatmentWriter writer,
    required AppDatabase db,
  })  : _scanner = scanner,
        _connector = connector,
        _writer = writer,
        _db = db;

  // --- Scanning ---

  Stream<List<ScanResult>> get scanResults => _scanner.scanResults;
  bool get isScanning => _scanner.isScanning;

  Future<void> startScan() => _scanner.startScan();
  Future<void> stopScan() => _scanner.stopScan();

  // --- Connection ---

  Stream<Map<String, BleConnectionStatus>> get connectionStates =>
      _connector.connectionStates;

  Future<bool> connectDevice(BluetoothDevice device) async {
    final success = await _connector.connect(device);
    if (success) {
      // Save to paired devices cache
      await _db.upsertPairedDevice(PairedDevicesCompanion(
        id: Value(device.remoteId.str),
        macAddress: Value(device.remoteId.str),
        name: Value(device.platformName.isNotEmpty
            ? device.platformName
            : 'Unknown Device'),
        autoReconnect: const Value(true),
        lastConnected: Value(DateTime.now()),
      ));
    }
    return success;
  }

  Future<void> disconnectDevice(String deviceId) =>
      _connector.disconnect(deviceId);

  Future<void> disconnectAll() => _connector.disconnectAll();

  bool isConnected(String deviceId) => _connector.isConnected(deviceId);

  List<String> get connectedDeviceIds => _connector.connectedDeviceIds;

  // --- Auto-reconnect ---

  /// Attempt to reconnect to all previously paired devices.
  Future<void> autoReconnectPairedDevices() async {
    final paired = await _db.getAllPairedDevices();
    final connectedSystemDevices = await FlutterBluePlus.systemDevices([]);

    for (final device in paired) {
      if (!device.autoReconnect) continue;

      // Find matching system device or create reference
      BluetoothDevice? systemDevice;
      for (final d in connectedSystemDevices) {
        if (d.remoteId.str == device.macAddress) {
          systemDevice = d;
          break;
        }
      }
      systemDevice ??= BluetoothDevice(remoteId: DeviceIdentifier(device.macAddress));

      appLogger.i('BLE: Auto-reconnecting to ${device.name}...');
      await _connector.connect(systemDevice);
    }
  }

  // --- Commands ---

  Future<bool> sendCommand(BleCommand command) async {
    final success = await _writer.sendCommand(command);
    if (!success) {
      // Queue for later
      await _db.insertCommand(CommandQueueCompanion(
        macAddress: Value(command.macAddress),
        commandJson: Value(command.toJson()),
      ));
      appLogger.w('BLE: Command queued for later delivery');
    }
    return success;
  }

  Future<Map<String, bool>> sendToAll(
    CommandType type, {
    Map<String, dynamic>? payload,
  }) =>
      _writer.sendToAll(type, payload: payload);

  // --- Command Queue Sync ---

  Future<void> flushCommandQueue() async {
    final unsynced = await _db.getUnsyncedCommands();
    for (final cmd in unsynced) {
      try {
        final command = BleCommand.fromJson(cmd.commandJson);
        final success = await _writer.sendCommand(command);
        if (success) {
          await _db.markCommandSynced(cmd.id);
        }
      } catch (e) {
        appLogger.e('BLE: Failed to flush command ${cmd.id}: $e');
      }
    }
    await _db.clearSyncedCommands();
  }

  // --- Paired Devices ---

  Future<List<PairedDevice>> getPairedDevices() => _db.getAllPairedDevices();
  Stream<List<PairedDevice>> watchPairedDevices() => _db.watchPairedDevices();

  Future<void> removePairedDevice(String macAddress) async {
    await _connector.disconnect(macAddress);
    await _db.removePairedDevice(macAddress);
  }

  Future<void> renamePairedDevice(String macAddress, String newName) async {
    await _db.upsertPairedDevice(PairedDevicesCompanion(
      id: Value(macAddress),
      macAddress: Value(macAddress),
      name: Value(newName),
    ));
  }

  void dispose() {
    _scanner.dispose();
    _connector.dispose();
  }
}
