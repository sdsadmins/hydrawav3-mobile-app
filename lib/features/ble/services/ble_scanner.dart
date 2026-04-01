import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';

final bleScannerProvider = Provider<BleScanner>((ref) {
  return BleScanner();
});

class BleScanner {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final _resultsController = StreamController<List<ScanResult>>.broadcast();
  bool _isScanning = false;

  Stream<List<ScanResult>> get scanResults => _resultsController.stream;
  bool get isScanning => _isScanning;

  /// Start scanning for Hydrawav3 devices.
  Future<void> startScan({Duration? timeout}) async {
    if (_isScanning) return;

    _isScanning = true;
    appLogger.i('BLE: Starting scan...');

    try {
      // Check if Bluetooth is on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        appLogger.w('BLE: Bluetooth is not enabled');
        _isScanning = false;
        return;
      }

      // Start scan with filter
      await FlutterBluePlus.startScan(
        timeout: timeout ?? BleConstants.scanTimeout,
        withNames: [BleConstants.deviceNamePrefix],
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          // Filter for Hydrawav3 devices
          final filtered = results.where((r) {
            final name = r.device.platformName;
            return name.isNotEmpty &&
                name.toLowerCase().startsWith(
                    BleConstants.deviceNamePrefix.toLowerCase());
          }).toList();

          if (filtered.isNotEmpty) {
            _resultsController.add(filtered);
            appLogger.d('BLE: Found ${filtered.length} device(s)');
          }
        },
        onError: (error) {
          appLogger.e('BLE: Scan error: $error');
        },
      );

      // Auto-stop after timeout
      FlutterBluePlus.isScanning.listen((scanning) {
        _isScanning = scanning;
        if (!scanning) {
          appLogger.i('BLE: Scan completed');
        }
      });
    } catch (e) {
      appLogger.e('BLE: Failed to start scan: $e');
      _isScanning = false;
    }
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    if (!_isScanning) return;
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    appLogger.i('BLE: Scan stopped');
  }

  /// Get all currently discovered devices (one-shot).
  Future<List<ScanResult>> quickScan({Duration? timeout}) async {
    final completer = Completer<List<ScanResult>>();
    final results = <ScanResult>[];

    await FlutterBluePlus.startScan(
      timeout: timeout ?? BleConstants.scanTimeout,
    );

    final sub = FlutterBluePlus.onScanResults.listen((scanResults) {
      for (final r in scanResults) {
        final name = r.device.platformName;
        if (name.isNotEmpty &&
            name.toLowerCase().startsWith(
                BleConstants.deviceNamePrefix.toLowerCase())) {
          // Avoid duplicates
          if (!results.any(
              (existing) => existing.device.remoteId == r.device.remoteId)) {
            results.add(r);
          }
        }
      }
    });

    // Wait for scan to complete
    await FlutterBluePlus.isScanning
        .where((scanning) => !scanning)
        .first;
    await sub.cancel();

    if (!completer.isCompleted) {
      completer.complete(results);
    }

    return completer.future;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _resultsController.close();
  }
}
