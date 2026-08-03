import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/services/ble_connector.dart';

/// A device's last-reported firmware run state (`rs` in the telemetry frame:
/// "Stop" / "Play" / "Pause" / "Fault"). Only "play"/"pause" mean the unit is
/// mid-session and therefore in use.
enum BleRunState { stop, play, pause, fault, unknown }

BleRunState _parseRunState(String? rs) {
  switch (rs?.trim().toLowerCase()) {
    case 'play':
      return BleRunState.play;
    case 'pause':
      return BleRunState.pause;
    case 'stop':
      return BleRunState.stop;
    case 'fault':
      return BleRunState.fault;
    default:
      return BleRunState.unknown;
  }
}

class _RunStateEntry {
  final BleRunState state;
  final DateTime at;
  const _RunStateEntry(this.state, this.at);
}

/// Tracks the latest firmware run state per BLE device, straight off the
/// connector's notify stream — independent of any active [SessionEngine], so
/// the device-selection screen can tell whether a unit is already running
/// (e.g. started from another controller) BEFORE a session exists here.
///
/// Emits the set of device ids currently reporting play/pause. Entries go stale
/// after [_freshness]: telemetry streams every ~3s, so a unit that stops
/// reporting (without a clean "Stop" frame) shouldn't stay "in use" forever.
final bleRunStateMonitorProvider =
    StateNotifierProvider<BleRunStateMonitor, Set<String>>((ref) {
  final monitor = BleRunStateMonitor(ref.read(bleConnectorProvider));
  ref.onDispose(monitor.dispose);
  return monitor;
});

class BleRunStateMonitor extends StateNotifier<Set<String>> {
  final BleConnector _connector;
  StreamSubscription? _sub;
  Timer? _sweep;

  /// A play/pause older than this is treated as stale (no longer in use).
  static const Duration _freshness = Duration(seconds: 12);

  final Map<String, _RunStateEntry> _byDevice = {};

  BleRunStateMonitor(this._connector) : super(const {}) {
    _sub = _connector.notifications.listen((n) {
      final rs = _extractRunState(n.value);
      if (rs == null) return; // frame carried no run state — ignore
      _byDevice[n.deviceId] = _RunStateEntry(rs, DateTime.now());
      _recompute();
    });
    // Sweep stale entries so a device that silently stops streaming clears.
    _sweep = Timer.periodic(const Duration(seconds: 3), (_) => _recompute());
  }

  /// The device is running (play or paused) and its report is still fresh.
  bool isBusy(String deviceId) => state.contains(deviceId);

  void _recompute() {
    final now = DateTime.now();
    final busy = <String>{};
    // Drop stale entries as we go so the map doesn't grow unbounded.
    _byDevice.removeWhere((_, e) => now.difference(e.at) > _freshness);
    for (final entry in _byDevice.entries) {
      if (entry.value.state == BleRunState.play ||
          entry.value.state == BleRunState.pause) {
        busy.add(entry.key);
      }
    }
    if (busy.length != state.length || !busy.containsAll(state)) {
      if (mounted) state = busy;
    }
  }

  /// Decode a notify frame and pull out `rs`, mirroring the engine's parsing
  /// (UTF-8 JSON, optional single-key `{"<id>": {...}}` wrapper). Returns null
  /// when the frame isn't JSON or carries no `rs`.
  BleRunState? _extractRunState(List<int> value) {
    Map<String, dynamic> json;
    try {
      final s = utf8.decode(value, allowMalformed: true).trim();
      if (s.isEmpty || !s.startsWith('{')) return null;
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      json = decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    if (json.length == 1) {
      final only = json.values.first;
      if (only is Map) json = only.cast<String, dynamic>();
    }
    final rs = json['rs'];
    if (rs is! String || rs.trim().isEmpty) return null;
    return _parseRunState(rs);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sweep?.cancel();
    super.dispose();
  }
}
