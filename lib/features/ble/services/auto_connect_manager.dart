import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../../session/presentation/providers/session_target_provider.dart';
import '../data/ble_repository.dart';
import '../domain/ble_device_model.dart';
import '../presentation/providers/auto_connect_provider.dart';
import 'ble_connector.dart';

/// App-scoped auto-connect / reconnect manager.
///
/// Drives connects from the (continuous) BLE scan results — NOT from a screen —
/// so it works everywhere, including the live Session screen, and reconnects
/// ALL matching Hydrawave devices concurrently (capped) instead of one-at-a-time.
/// Gated by [autoConnectEnabledProvider]; deduped via [bleConnectingIdsProvider]
/// plus a local in-flight set.
///
/// CRITICAL: every `connectDevice` stops the scan (and suppresses auto-restart),
/// so after devices connect there is no scan running. To reconnect a device that
/// drops mid-session we therefore keep a scan ALIVE while any device is pending
/// reconnect (tracked in [_wantReconnect]) via a watchdog timer.
final autoConnectManagerProvider = Provider<AutoConnectManager>((ref) {
  final manager = AutoConnectManager(ref);
  ref.onDispose(manager.dispose);
  manager.start();
  return manager;
});

class AutoConnectManager {
  AutoConnectManager(this._ref);

  final Ref _ref;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<Map<String, BleConnectionStatus>>? _connSub;
  Timer? _watchdog;

  /// Cap simultaneous connects to avoid BLE radio thrash on some Android stacks.
  static const int _maxConcurrent = 3;

  /// Connects we kicked off and are awaiting.
  final Set<String> _inFlight = <String>{};

  /// Devices that were connected and then dropped — we keep scanning until they
  /// come back. Cleared per-device on successful (re)connect.
  final Set<String> _wantReconnect = <String>{};

  Map<String, BleConnectionStatus> _lastStates = {};

  void start() {
    final repo = _ref.read(bleRepositoryProvider);
    _scanSub ??= repo.scanResults.listen(_onScanResults);
    _connSub ??= _ref
        .read(bleConnectorProvider)
        .connectionStates
        .listen(_onConnStates);
    // Keep a scan alive while something is pending reconnect (every connect
    // stops the scan, so we must re-arm it). Cheap when nothing is pending.
    _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_wantReconnect.isEmpty) return;
      _ensureScanning();
    });
    appLogger.i('AutoConnect: manager started');
  }

  /// Track connected→disconnected (start wanting a reconnect, kick a scan) and
  /// disconnected→connected (stop wanting it).
  void _onConnStates(Map<String, BleConnectionStatus> states) {
    final autoOn = _ref.read(autoConnectEnabledProvider);
    for (final entry in states.entries) {
      final id = entry.key;
      final now = entry.value;
      final prev = _lastStates[id];
      if (now == BleConnectionStatus.connected) {
        _wantReconnect.remove(id);
      } else if (now == BleConnectionStatus.disconnected &&
          prev == BleConnectionStatus.connected &&
          autoOn) {
        _wantReconnect.add(id);
        appLogger.i('AutoConnect: $id dropped — will rescan to reconnect');
        _ensureScanning();
      }
    }
    _lastStates = Map.of(states);
  }

  /// Ask the manager to (re)connect [deviceId] now — the manual counterpart to
  /// the automatic connected→disconnected trigger in [_onConnStates].
  ///
  /// Goes through the same scan-then-connect path rather than connecting to a
  /// constructed MAC, which is the only form that works on iOS: there
  /// `remoteId` is an opaque per-install UUID, and you can only connect to a
  /// peripheral the scan actually discovered.
  void requestReconnect(String deviceId) {
    if (_ref.read(bleConnectorProvider).isConnected(deviceId)) return;
    _wantReconnect.add(deviceId);
    appLogger.i('AutoConnect: manual reconnect requested for $deviceId');
    // `force`: an explicit user tap must scan even when auto-connect is off.
    _ensureScanning(force: true);
  }

  void _ensureScanning({bool force = false}) {
    if (!force && !_ref.read(autoConnectEnabledProvider)) return;
    if (_inFlight.isNotEmpty) return; // don't scan during active connects
    final repo = _ref.read(bleRepositoryProvider);
    if (repo.isScanning) return;
    appLogger.i('AutoConnect: starting scan to (re)connect devices');
    unawaited(repo.startScan());
  }

  void _onScanResults(List<ScanResult> results) {
    // With auto-connect off we still honour an EXPLICIT reconnect request
    // (the live card's SCAN button) — but nothing else.
    final autoOn = _ref.read(autoConnectEnabledProvider);
    if (!autoOn && _wantReconnect.isEmpty) return;

    const expectedUuid = BleConstants.preferredServiceUuid;
    if (expectedUuid == null || expectedUuid.isEmpty) return;
    final targetUuid = BleConstants.normalizeUuid(expectedUuid);
    final connector = _ref.read(bleConnectorProvider);
    final connecting = _ref.read(bleConnectingIdsProvider);

    for (final result in results) {
      if (_inFlight.length >= _maxConcurrent) break; // free slots next tick

      final id = result.device.remoteId.str;
      if (_inFlight.contains(id)) continue;
      if (connecting.contains(id)) continue;
      if (connector.isConnected(id)) continue;
      if (!autoOn && !_wantReconnect.contains(id)) continue;

      final isHydrawave = result.advertisementData.serviceUuids.any(
        (u) => BleConstants.normalizeUuid(u.str) == targetUuid,
      );
      if (!isHydrawave) continue;

      unawaited(_connect(result.device));
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    final id = device.remoteId.str;
    _inFlight.add(id);
    _ref.read(bleConnectingIdsProvider.notifier).state = {
      ..._ref.read(bleConnectingIdsProvider),
      id,
    };
    appLogger.i('AutoConnect: connecting $id (${_inFlight.length} in flight)');
    try {
      final ok = await _ref.read(bleRepositoryProvider).connectDevice(device);
      if (ok) {
        _wantReconnect.remove(id);
        _ref.read(sessionTargetProvider.notifier).ensureSelected(id);
        appLogger.i('AutoConnect: connected $id');
      } else {
        appLogger.w('AutoConnect: connect returned false for $id');
      }
    } catch (e) {
      appLogger.w('AutoConnect: failed for $id: $e');
    } finally {
      _inFlight.remove(id);
      final current = _ref.read(bleConnectingIdsProvider);
      _ref.read(bleConnectingIdsProvider.notifier).state = {...current}
        ..remove(id);
      // connectDevice stopped the scan; re-arm it if anything is still pending
      // (e.g. a second device that dropped at the same time).
      if (_inFlight.isEmpty && _wantReconnect.isNotEmpty) {
        _ensureScanning();
      }
    }
  }

  void dispose() {
    _scanSub?.cancel();
    _scanSub = null;
    _connSub?.cancel();
    _connSub = null;
    _watchdog?.cancel();
    _watchdog = null;
  }
}
