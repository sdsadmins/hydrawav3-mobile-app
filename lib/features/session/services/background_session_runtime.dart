import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../advanced_settings/domain/advanced_settings_model.dart';
import '../../ble/services/ble_connector.dart';
import '../../../../core/storage/preferences.dart';
import '../../../../core/utils/logger.dart';

const _snapshotPrefsKey = 'live_session_snapshot_v1';

class LiveSessionSnapshot {
  final String protocolId;
  final String protocolName;
  final List<String> deviceIds;
  final String transport;
  final int startedAtEpochMs;
  final String? delayedDeviceId;
  final Map<String, String> protocolByDeviceId;
  final AdvancedSettings advancedSettings;
  final Map<String, AdvancedSettings> advancedSettingsByDevice;
  final bool fromBackgroundService;

  const LiveSessionSnapshot({
    required this.protocolId,
    required this.protocolName,
    required this.deviceIds,
    required this.transport,
    required this.startedAtEpochMs,
    required this.protocolByDeviceId,
    required this.advancedSettings,
    required this.advancedSettingsByDevice,
    this.delayedDeviceId,
    this.fromBackgroundService = false,
  });

  Map<String, dynamic> toJson() => {
        'protocolId': protocolId,
        'protocolName': protocolName,
        'deviceIds': deviceIds,
        'transport': transport,
        'startedAtEpochMs': startedAtEpochMs,
        'delayedDeviceId': delayedDeviceId,
        'protocolByDeviceId': protocolByDeviceId,
        'advancedSettings': advancedSettings.toJson(),
        'advancedSettingsByDevice': {
          for (final entry in advancedSettingsByDevice.entries)
            entry.key: entry.value.toJson(),
        },
        'fromBackgroundService': fromBackgroundService,
      };

  factory LiveSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final byDeviceRaw = (json['advancedSettingsByDevice'] as Map?) ?? const {};
    final byDevice = <String, AdvancedSettings>{};
    for (final entry in byDeviceRaw.entries) {
      final key = entry.key?.toString();
      final value = entry.value;
      if (key == null || value is! Map) continue;
      byDevice[key] =
          AdvancedSettings.fromJson(Map<String, dynamic>.from(value));
    }
    final protocolByDeviceRaw =
        (json['protocolByDeviceId'] as Map?) ?? const {};
    final protocolByDevice = <String, String>{};
    for (final entry in protocolByDeviceRaw.entries) {
      final key = entry.key?.toString();
      final value = entry.value?.toString();
      if (key == null || value == null) continue;
      protocolByDevice[key] = value;
    }

    return LiveSessionSnapshot(
      protocolId: json['protocolId']?.toString() ?? '',
      protocolName: json['protocolName']?.toString() ?? '',
      deviceIds: ((json['deviceIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      transport: json['transport']?.toString() ?? 'ble',
      startedAtEpochMs: (json['startedAtEpochMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      delayedDeviceId: json['delayedDeviceId']?.toString(),
      protocolByDeviceId: protocolByDevice,
      advancedSettings: json['advancedSettings'] is Map
          ? AdvancedSettings.fromJson(
              Map<String, dynamic>.from(json['advancedSettings'] as Map),
            )
          : const AdvancedSettings(),
      advancedSettingsByDevice: byDevice,
      fromBackgroundService: json['fromBackgroundService'] as bool? ?? false,
    );
  }
}

class BackgroundSessionState {
  final String status;
  final int startedAtEpochMs;
  final int elapsedMs;
  final LiveSessionSnapshot? snapshot;

  const BackgroundSessionState({
    this.status = 'idle',
    this.startedAtEpochMs = 0,
    this.elapsedMs = 0,
    this.snapshot,
  });

  bool get isLive => status == 'running' || status == 'paused';

  BackgroundSessionState copyWith({
    String? status,
    int? startedAtEpochMs,
    int? elapsedMs,
    LiveSessionSnapshot? snapshot,
    bool clearSnapshot = false,
  }) {
    return BackgroundSessionState(
      status: status ?? this.status,
      startedAtEpochMs: startedAtEpochMs ?? this.startedAtEpochMs,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
    );
  }
}

final backgroundSessionRuntimeProvider =
    StateNotifierProvider<BackgroundSessionRuntime, BackgroundSessionState>(
        (ref) {
  final runtime = BackgroundSessionRuntime(ref);
  runtime.initialize();
  ref.onDispose(runtime.dispose);
  return runtime;
});

class BackgroundSessionRuntime extends StateNotifier<BackgroundSessionState> {
  BackgroundSessionRuntime(this._ref) : super(const BackgroundSessionState());

  final Ref _ref;
  static const _methods = MethodChannel('hydrawav3/background_session/methods');
  static const _events = EventChannel('hydrawav3/background_session/events');

  StreamSubscription<dynamic>? _eventsSub;

  Future<void> initialize() async {
    await _restoreSnapshot();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _eventsSub ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        appLogger.w('BG session events stream error: $error\n$stackTrace');
      },
    );
  }

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    super.dispose();
  }

  Future<void> startService(LiveSessionSnapshot snapshot) async {
    state = state.copyWith(
      status: 'running',
      startedAtEpochMs: snapshot.startedAtEpochMs,
      snapshot: snapshot.copyWith(fromBackgroundService: true),
    );
    await _persistSnapshot(state.snapshot);

    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // Request notification permission for Android 13+
      // Temporarily disabled as requested.
      // await _requestNotificationPermission();

      await _methods.invokeMethod<void>('startService', {
        'startedAtEpochMs': snapshot.startedAtEpochMs,
        'deviceIds': snapshot.deviceIds,
        'deviceNames': snapshot.deviceIds
            .map((id) => 'Device ${id.substring(id.length - 4)}')
            .toList(),
        'protocolName': snapshot.protocolName,
      });
      appLogger.i('Background service started successfully');
    } catch (e, st) {
      appLogger.w('Failed to start bg service: $e\n$st');
    }
  }

  Future<void> _requestNotificationPermission() async {
    // Only request on Android 13+ (API 33+)
    if (defaultTargetPlatform != TargetPlatform.android) {
      appLogger.i('Skipping permission request - not Android platform');
      return;
    }

    try {
      appLogger.i('Requesting notification permission from Flutter...');
      final result =
          await _methods.invokeMethod<bool>('requestNotificationPermission');
      appLogger.i('Permission request result: $result');
    } catch (e) {
      appLogger.w('Failed to request notification permission: $e');
    }
  }

  Future<void> pauseService() async {
    state = state.copyWith(status: 'paused');
    await _persistSnapshot(state.snapshot);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _methods.invokeMethod<void>('pauseService');
    } catch (e, st) {
      appLogger.w('Failed to pause bg service: $e\n$st');
    }
  }

  Future<void> resumeService() async {
    state = state.copyWith(status: 'running');
    await _persistSnapshot(state.snapshot);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _methods.invokeMethod<void>('resumeService');
    } catch (e, st) {
      appLogger.w('Failed to resume bg service: $e\n$st');
    }
  }

  Future<void> stopService() async {
    state =
        state.copyWith(status: 'stopped', clearSnapshot: true, elapsedMs: 0);
    await _persistSnapshot(null);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _methods.invokeMethod<void>('stopService');
    } catch (e, st) {
      appLogger.w('Failed to stop bg service: $e\n$st');
    }
  }

  Future<void> cacheSnapshotOnly(LiveSessionSnapshot snapshot) async {
    state = state.copyWith(
      snapshot: snapshot,
      startedAtEpochMs: snapshot.startedAtEpochMs,
    );
    await _persistSnapshot(snapshot);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);

    // Handle BLE commands from Android notification
    if (event['type'] == 'ble_command') {
      _handleBleCommand(event);
      return;
    }

    final status = event['status']?.toString() ?? state.status;
    final startedAt =
        (event['startedAtEpochMs'] as num?)?.toInt() ?? state.startedAtEpochMs;
    final elapsed = (event['elapsedMs'] as num?)?.toInt() ?? state.elapsedMs;
    state = state.copyWith(
      status: status,
      startedAtEpochMs: startedAt,
      elapsedMs: elapsed,
    );
  }

  Future<void> _handleBleCommand(Map<String, dynamic> event) async {
    final deviceId = event['deviceId']?.toString();
    final command = event['command'] as int?;

    if (deviceId == null || command == null) {
      appLogger.w('Invalid BLE command event: $event');
      return;
    }

    appLogger.i(
        'Received BLE command 0x${command.toRadixString(16)} for device $deviceId');

    // Send command to BLE connector
    try {
      final bleConnector = _ref.read(bleConnectorProvider);
      final success = await bleConnector.writeToDevice(deviceId, [command]);
      appLogger.i('BLE command sent to $deviceId: $success');
    } catch (e) {
      appLogger.e('Failed to send BLE command to $deviceId: $e');
    }
  }

  Future<void> _restoreSnapshot() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final encoded = prefs.getString(_snapshotPrefsKey);
      if (encoded == null || encoded.isEmpty) return;
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final snapshot = LiveSessionSnapshot.fromJson(json);
      final elapsed =
          (DateTime.now().millisecondsSinceEpoch - snapshot.startedAtEpochMs)
              .clamp(0, 1 << 31);
      state = state.copyWith(
        status: 'running',
        startedAtEpochMs: snapshot.startedAtEpochMs,
        elapsedMs: elapsed as int,
        snapshot: snapshot,
      );
    } catch (e, st) {
      appLogger.w('Failed to restore live session snapshot: $e\n$st');
    }
  }

  Future<void> _persistSnapshot(LiveSessionSnapshot? snapshot) async {
    final prefs = _ref.read(sharedPreferencesProvider);
    if (snapshot == null) {
      await prefs.remove(_snapshotPrefsKey);
      return;
    }
    await prefs.setString(_snapshotPrefsKey, jsonEncode(snapshot.toJson()));
  }
}

extension on LiveSessionSnapshot {
  LiveSessionSnapshot copyWith({
    bool? fromBackgroundService,
  }) {
    return LiveSessionSnapshot(
      protocolId: protocolId,
      protocolName: protocolName,
      deviceIds: deviceIds,
      transport: transport,
      startedAtEpochMs: startedAtEpochMs,
      delayedDeviceId: delayedDeviceId,
      protocolByDeviceId: protocolByDeviceId,
      advancedSettings: advancedSettings,
      advancedSettingsByDevice: advancedSettingsByDevice,
      fromBackgroundService:
          fromBackgroundService ?? this.fromBackgroundService,
    );
  }
}
