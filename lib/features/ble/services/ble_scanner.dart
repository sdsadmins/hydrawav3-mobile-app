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
  Timer? _autoRestartTimer;
  final _resultsController = StreamController<List<ScanResult>>.broadcast();
  final Map<String, ScanResult> _knownResultsById = {};
  final Map<String, DateTime> _lastSeenAtById = {};
  final List<String> _orderedDeviceIds = [];
  bool _isScanning = false;
  bool _autoScanEnabled = true;
  bool _suppressNextAutoRestart = false;
  Function(ScanResult result)? onDeviceFound;
  static const Duration _staleDeviceThreshold = Duration(seconds: 14);

  Stream<List<ScanResult>> get scanResults => _resultsController.stream;
  bool get isScanning => _isScanning;

  void _emitKnownResults() {
    final now = DateTime.now();
    final staleIds = _orderedDeviceIds.where((id) {
      final lastSeen = _lastSeenAtById[id];
      return lastSeen == null ||
          now.difference(lastSeen) > _staleDeviceThreshold;
    }).toList();

    for (final id in staleIds) {
      _knownResultsById.remove(id);
      _lastSeenAtById.remove(id);
      _orderedDeviceIds.remove(id);
    }

    final stableList = _orderedDeviceIds
        .map((id) => _knownResultsById[id])
        .whereType<ScanResult>()
        .toList(growable: false);

    _resultsController.add(stableList);
  }

  void _mergeScanResults(List<ScanResult> results) {
    final now = DateTime.now();

    for (final result in results) {
      final id = result.device.remoteId.str;
      final isNewDevice = !_knownResultsById.containsKey(id);

      _knownResultsById[id] = result;
      _lastSeenAtById[id] = now;

      if (isNewDevice) {
        _orderedDeviceIds.remove(id);
        _orderedDeviceIds.insert(0, id);
      } else if (!_orderedDeviceIds.contains(id)) {
        _orderedDeviceIds.add(id);
      }
    }

    _emitKnownResults();
  }

  void _scheduleAutoRestart() {
    if (!_autoScanEnabled || _suppressNextAutoRestart) return;

    _autoRestartTimer?.cancel();
    _autoRestartTimer = Timer(const Duration(milliseconds: 900), () async {
      _autoRestartTimer = null;
      if (_isScanning || _globalScanActive) return;

      try {
        final state = await FlutterBluePlus.adapterState
            .where((s) => s != BluetoothAdapterState.unknown)
            .first;
        if (state == BluetoothAdapterState.on) {
          appLogger.i('BLE: Auto-restarting scan after completion');
          await startScan();
        }
      } catch (e) {
        appLogger.w('BLE: Failed to auto-restart scan: $e');
      }
    });
  }

  /// Initialize Bluetooth state monitoring for auto-scan
  void initializeAutoScan() {
    if (_autoScanEnabled && _adapterSub == null) {
      _adapterSub = FlutterBluePlus.adapterState.listen((state) {
        appLogger.i('BLE: Bluetooth adapter state changed to: $state');
        if (state == BluetoothAdapterState.on && !_isScanning) {
          // Auto-start scan when Bluetooth turns on
          appLogger.i('BLE: Bluetooth turned on, auto-starting scan');
          Future.delayed(const Duration(milliseconds: 500), () {
            startScan();
          });
        } else if (state == BluetoothAdapterState.off) {
          // Stop scan when Bluetooth turns off
          appLogger.i('BLE: Bluetooth turned off, stopping scan');
          stopScan();
        }
      });

      // Also check the current adapter state once on initialization so the
      // first visit to the Devices screen can auto-scan without needing an
      // app restart or a later adapter-state change event.
      Future.microtask(() async {
        try {
          final state = await FlutterBluePlus.adapterState
              .where((s) => s != BluetoothAdapterState.unknown)
              .first;
          if (state == BluetoothAdapterState.on &&
              !_isScanning &&
              !_globalScanActive) {
            appLogger.i('BLE: Adapter already on, starting initial auto-scan');
            await startScan();
          }
        } catch (e) {
          appLogger.w('BLE: Failed initial adapter state check: $e');
        }
      });
    }
  }

  /// Start a single scan to discover new devices
  Future<void> quickScanForNewDevices({Duration? timeout}) async {
    if (_isScanning) return;

    appLogger.i('BLE: Starting quick scan for new devices');

    _knownResultsById.clear();
    _lastSeenAtById.clear();
    _orderedDeviceIds.clear();
    _resultsController.add(const <ScanResult>[]);

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    await FlutterBluePlus.startScan(
      timeout: timeout ?? const Duration(seconds: 10),
      androidUsesFineLocation: true,
    );

    // Listen for results and stop when we get any
    StreamSubscription<List<ScanResult>>? scanSub;
    scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isNotEmpty) {
        appLogger.i('BLE: Quick scan found ${results.length} devices');
        scanSub?.cancel();
        _scanSubscription = null;
        _isScanning = false;
        _globalScanActive = false;
      }
    }, onError: (error) {
      appLogger.e('BLE: Quick scan error: $error');
      scanSub?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _globalScanActive = false;
    });

    _scanSubscription = scanSub;
  }

  /// Start scanning for Hydrawav3 devices.
  Future<void> startScan({Duration? timeout}) async {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;
    _suppressNextAutoRestart = false;

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

          _mergeScanResults(results);
          for (final result in results) {
            onDeviceFound?.call(result);
          }
        },
        onError: (error) {
          appLogger.e('BLE: Scan error: $error');
          _isScanning = false;
          _globalScanActive = false;
        },
      );

      // Track scanning state (and avoid leaving dangling listeners).
      await _isScanningSub?.cancel();
      _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        _isScanning = scanning;
        if (!scanning) {
          _globalScanActive = false;
          _emitKnownResults();
          appLogger.i('BLE: Scan completed');
          final shouldAutoRestart = !_suppressNextAutoRestart;
          _suppressNextAutoRestart = false;
          if (shouldAutoRestart) {
            _scheduleAutoRestart();
          }
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
    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;
    _suppressNextAutoRestart = true;

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
    _autoRestartTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterSub?.cancel();
    _isScanningSub?.cancel();
    _resultsController.close();
  }
}
