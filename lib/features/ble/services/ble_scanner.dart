import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';

final bleScannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScanner();
  // Prevent scanner re-creation across screen/provider lifecycles, and ensure
  // we dispose correctly if the provider scope is torn down.
  ref.keepAlive();
  ref.onDispose(() {
    scanner.dispose();
  });
  return scanner;
});

class BleScanner {
  // Global guard to prevent parallel scan attempts from multiple scanner
  // instances (e.g. due to Riverpod lifecycle / multiple ProviderScopes).
  static bool _globalScanActive = false;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _isScanningSub;
  final _resultsController = StreamController<List<ScanResult>>.broadcast();
  bool _isScanning = false;

  Stream<List<ScanResult>> get scanResults => _resultsController.stream;
  bool get isScanning => _isScanning;

  /// Start scanning for Hydrawav3 devices.
  Future<void> startScan({Duration? timeout}) async {
    if (_isScanning) return;
    if (_globalScanActive) {
      appLogger
          .w('BLE: Scan already active (global guard). Ignoring startScan().');
      return;
    }
    _globalScanActive = true;

    _isScanning = true;
    appLogger.i('BLE: Starting scan...');

    try {
      // Keep a lightweight adapter state log running (helps debug "empty scan").
      _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
        appLogger.d('BLE: Adapter state: $s');
      });

      if (Platform.isAndroid) {
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        // Some Android devices still require location permission and location
        // services enabled for scan results to appear.
        final location = await Permission.location.request();

        if (!scan.isGranted || !connect.isGranted) {
          appLogger.w('BLE: Missing bluetooth permissions (scan/connect)');
          _isScanning = false;
          _globalScanActive = false;
          return;
        }
        if (!location.isGranted) {
          appLogger
              .w('BLE: Location permission not granted (scan may be empty)');
        }
      }

      // Check if Bluetooth is on
      var adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        appLogger.w('BLE: Bluetooth is not enabled');

        // On Android, trigger the system prompt to enable Bluetooth.
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
            adapterState = await FlutterBluePlus.adapterState
                .where((s) => s != BluetoothAdapterState.unknown)
                .first;
          } catch (e) {
            appLogger.w('BLE: Failed to request Bluetooth enable: $e');
          }
        }

        if (adapterState != BluetoothAdapterState.on) {
          _isScanning = false;
          _globalScanActive = false;
          return;
        }
      }

      // Start scan WITHOUT name filters.
      // Many BLE bridges advertise with an empty name; filtering by name makes
      // scan results look "empty" even when scan works.
      // Safety: if something left an old subscription hanging, cancel it.
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      await FlutterBluePlus.startScan(
        timeout: timeout ?? BleConstants.scanTimeout,
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          appLogger.d('BLE: Scan tick — results: ${results.length}');
          if (results.isNotEmpty) {
            // Log a small sample to quickly see if names are empty.
            final sample = results.take(5).map((r) {
              final n = r.device.platformName;
              return "('${n.isEmpty ? '(no name)' : n}', ${r.device.remoteId.str}, rssi=${r.rssi})";
            }).join(', ');
            appLogger.d('BLE: Sample: $sample');
          }

          _resultsController.add(results);
        },
        onError: (error) {
          appLogger.e('BLE: Scan error: $error');
          _globalScanActive = false;
        },
      );

      // Track scanning state (and avoid leaving dangling listeners).
      await _isScanningSub?.cancel();
      _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        _isScanning = scanning;
        if (!scanning) {
          appLogger.i('BLE: Scan completed');
        }
      });
    } catch (e) {
      appLogger.e('BLE: Failed to start scan: $e');
      _isScanning = false;
      _globalScanActive = false;
    }
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    if (!_isScanning && !_globalScanActive) return;

    // Stop our log/stream listeners first, so we don't keep receiving "scan tick"
    // events from a lingering subscription.
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    await FlutterBluePlus.stopScan();
    await _isScanningSub?.cancel();
    _isScanningSub = null;
    _isScanning = false;
    _globalScanActive = false;
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
        if (name.isEmpty ||
            !name.toLowerCase().startsWith(
                  BleConstants.deviceNamePrefix.toLowerCase(),
                )) {
          continue;
        }

        // Avoid duplicates
        if (!results
            .any((existing) => existing.device.remoteId == r.device.remoteId)) {
          results.add(r);
        }
      }
    });

    // Wait for scan to complete
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    await sub.cancel();

    if (!completer.isCompleted) {
      completer.complete(results);
    }

    return completer.future;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _adapterSub?.cancel();
    _isScanningSub?.cancel();
    _resultsController.close();
  }
}
