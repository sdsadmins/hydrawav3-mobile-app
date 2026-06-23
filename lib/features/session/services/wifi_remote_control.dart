import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/mqtt_publish_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/active_session_model.dart';
import 'session_sync_service.dart';

final wifiRemoteControlProvider = Provider<WifiRemoteControl>((ref) {
  return WifiRemoteControl(ref);
});

/// Controls a live session this phone does NOT own (started on the web or
/// another phone) when its devices are Wi-Fi. Wi-Fi devices are reachable from
/// any client through the cloud MQTT broker, so control mirrors the local
/// engine: publish the same `playCmd` the engine uses AND call the backend
/// state endpoint so every client's live feed stays in sync.
///
/// BLE sessions are intentionally NOT controllable here — a phone can't reach a
/// BLE device it isn't bonded to.
class WifiRemoteControl {
  final Ref _ref;
  WifiRemoteControl(this._ref);

  // Same playCmd values the SessionEngine uses for Wi-Fi.
  static const int _stopCmd = 2;
  static const int _pauseCmd = 3;
  static const int _resumeCmd = 4;

  Future<void> stop(ActiveSession session) => _control(
        session,
        playCmd: _stopCmd,
        backend: (sync, id) => sync.stopServerSession(id),
      );

  Future<void> pause(ActiveSession session) => _control(
        session,
        playCmd: _pauseCmd,
        backend: (sync, id) => sync.pauseServerSession(id),
      );

  Future<void> resume(ActiveSession session) => _control(
        session,
        playCmd: _resumeCmd,
        backend: (sync, id) => sync.resumeServerSession(id),
      );

  // ─────────────────────────── per-device control ───────────────────────────
  // Command a SINGLE Wi-Fi device of a foreign session: publish the playCmd to
  // just that device's mac over the broker AND target it on the backend by
  // macAddress (the rest of the session keeps running). Mirrors the web's
  // per-device pause/resume/stop.

  Future<void> stopDevice(ActiveSession session, String deviceId) =>
      _controlDevice(
        session,
        deviceId,
        playCmd: _stopCmd,
        backend: (sync, id, mac) => sync.stopServerSessionDevice(id, mac),
      );

  Future<void> pauseDevice(ActiveSession session, String deviceId) =>
      _controlDevice(
        session,
        deviceId,
        playCmd: _pauseCmd,
        backend: (sync, id, mac) => sync.pauseServerSessionDevice(id, mac),
      );

  Future<void> resumeDevice(ActiveSession session, String deviceId) =>
      _controlDevice(
        session,
        deviceId,
        playCmd: _resumeCmd,
        backend: (sync, id, mac) => sync.resumeServerSessionDevice(id, mac),
      );

  Future<void> _control(
    ActiveSession session, {
    required int playCmd,
    required Future<void> Function(SessionSyncService, String) backend,
  }) async {
    // Command each Wi-Fi device directly over the broker.
    final dio = _ref.read(djangoDioProvider);
    final wifiDevices =
        session.liveDevices.where((d) => d.transport == 'wifi').toList();
    final macs = wifiDevices.isNotEmpty
        ? wifiDevices.map((d) => d.deviceId)
        : session.deviceIds; // fallback when liveDevices isn't populated
    for (final mac in macs) {
      if (mac.isEmpty) continue;
      final payload = jsonEncode({'mac': mac, 'playCmd': playCmd});
      try {
        await postMqttPublishRequest(
          dio,
          data: {'topic': 'HydraWav3Pro/config', 'payload': payload},
        );
        appLogger.i('WifiRemoteControl: playCmd=$playCmd → $mac');
      } catch (e) {
        appLogger.e('WifiRemoteControl: publish failed for $mac: $e');
      }
    }

    // Update backend state + broadcast so every client's live feed reconciles.
    await backend(_ref.read(sessionSyncServiceProvider), session.id);
  }

  Future<void> _controlDevice(
    ActiveSession session,
    String deviceId, {
    required int playCmd,
    required Future<void> Function(SessionSyncService, String, String) backend,
  }) async {
    if (deviceId.isEmpty) return;
    // Command just this device over the broker.
    final dio = _ref.read(djangoDioProvider);
    final payload = jsonEncode({'mac': deviceId, 'playCmd': playCmd});
    try {
      await postMqttPublishRequest(
        dio,
        data: {'topic': 'HydraWav3Pro/config', 'payload': payload},
      );
      appLogger.i('WifiRemoteControl: playCmd=$playCmd → $deviceId (device)');
    } catch (e) {
      appLogger.e('WifiRemoteControl: device publish failed for $deviceId: $e');
    }

    // Target only this device on the backend so the rest of the session runs on.
    await backend(_ref.read(sessionSyncServiceProvider), session.id, deviceId);
  }
}
