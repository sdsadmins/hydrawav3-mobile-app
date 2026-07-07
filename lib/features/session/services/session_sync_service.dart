import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/logger.dart';
import '../../ble/data/ble_repository.dart';
import '../../ble/services/ble_connector.dart';
import '../../devices/presentation/providers/wifi_devices_provider.dart';

/// Thrown when the backend refuses a session start because the organization
/// has insufficient tokens or no active subscription. The launch path catches
/// this to BLOCK the run (web parity) instead of letting the device run for
/// free. All other (transient) failures stay tolerant — they never throw this.
class InsufficientTokensException implements Exception {
  final String message;
  const InsufficientTokensException([
    this.message =
        'Insufficient tokens. Please top up your subscription to start a session.',
  ]);
  @override
  String toString() => message;
}

/// True when a Dio 400 is the backend's token/subscription rejection.
///
/// Nest `BadRequestException` body is `{statusCode, message, error}`; `message`
/// may be a `String` or a `List<String>` (validation errors).
bool isTokenOrSubscriptionError(DioException e) {
  if (e.response?.statusCode != 400) return false;
  final data = e.response?.data;
  String text;
  if (data is Map) {
    final m = data['message'];
    text = m is List ? m.join(' ') : (m?.toString() ?? data.toString());
  } else {
    text = data?.toString() ?? '';
  }
  final t = text.toLowerCase();
  return t.contains('insufficient token') ||
      t.contains('no remaining token') ||
      t.contains('subscription payment record not found') ||
      t.contains('subscription');
}

/// One normal (non-Protocol-Plus) device's spec for a backend session start.
class NormalDeviceSpec {
  /// Local write target — BLE remoteId / Wi-Fi macAddress.
  final String localMac;

  /// Backend protocol `_id` to run on this device.
  final String protocolId;

  /// Protocol template name — the backend DeviceDto requires this `protocol`
  /// field (not just the id).
  final String protocolName;

  /// Advanced settings to register with the server (cycle overrides, etc.).
  final Map<String, dynamic> advancedSettings;

  /// Per-device total run length — used by the backend to lock tokens.
  final int totalDurationSeconds;

  final String? bodyPart;
  final String? slotId;

  const NormalDeviceSpec({
    required this.localMac,
    required this.protocolId,
    required this.protocolName,
    required this.advancedSettings,
    required this.totalDurationSeconds,
    this.bodyPart,
    this.slotId,
  });
}

final sessionSyncServiceProvider = Provider<SessionSyncService>((ref) {
  return SessionSyncService(ref);
});

/// Delivery channel for the backend `sessionId` of a normal run, keyed by the
/// LOCAL engine/session id. The session screen opens immediately on launch —
/// before the (network) `/sessions/start` POST returns — so the backend id is
/// published here and the screen watches it to drive pause/resume/stop.
///
/// Not auto-disposed: writer (launch) and reader (screen) may subscribe in
/// either order, so the value must survive until the screen reads it.
final normalServerSessionIdProvider =
    StateProvider.family<String?, String>((ref, localSessionId) => null);

/// Maps a backend `sessionId` (as it appears in the org-wide live feed) back to
/// the LOCAL engine/session id for runs this phone started. Lets the History
/// live tab re-open an own session against its real local engine instead of the
/// backend id (which would spin up a fresh engine and re-issue device commands).
final ownBackendToLocalSessionProvider =
    StateProvider<Map<String, String>>((ref) => const {});

/// Creates and reconciles a BACKEND session for normal (single-protocol) runs,
/// so they appear in the org-wide live-session feed (parity with the web app).
///
/// Protocol Plus runs already do this via `/protocol-plus/start`; this is the
/// missing half for normal BLE / Wi-Fi runs. Every method is failure-tolerant:
/// the physical device run has already started locally, so a failed POST only
/// means the run won't be visible to other clients — it must never throw into
/// the launch path.
class SessionSyncService {
  final Ref _ref;

  SessionSyncService(this._ref);

  /// POST /sessions/start for the given normal devices. Returns the backend
  /// `sessionId`, or null on any failure.
  Future<String?> startServerSession({
    required List<NormalDeviceSpec> devices,
    required String transport,
    String? clientId,
  }) async {
    if (devices.isEmpty) return null;
    try {
      final storage = _ref.read(secureStorageProvider);
      final token = await storage.getAccessToken();
      final userId = await storage.getUserId();
      final orgId = await storage.getSelectedOrgId();
      if (orgId == null || orgId.isEmpty) {
        appLogger.w('SessionSync: no organizationId — skipping server start');
        return null;
      }

      final nameByDevice =
          await _resolveRegisteredNames(devices.map((d) => d.localMac).toList());

      final devicePayload = devices.map((d) {
        // BLE registers by the firmware-reported bluetoothId; Wi-Fi by mac.
        var serverDeviceId = d.localMac;
        String? connectedName;
        if (transport == 'ble') {
          final connector = _ref.read(bleConnectorProvider);
          final fwId = connector.getFirmwareSessionId(d.localMac);
          if (fwId != null && fwId.isNotEmpty) serverDeviceId = fwId;
          // The live "Connected to <name>" advertised name — the most direct
          // human name for a BLE device, used when neither the org registry nor
          // the paired list resolved one.
          connectedName = connector.getConnectedDeviceName(d.localMac);
        }
        // Send the device's NAME (never the raw mac/bluetoothId): registered
        // name → live connected name → mac as last resort.
        final deviceName = nameByDevice[d.localMac.trim().toUpperCase()] ??
            connectedName ??
            d.localMac;
        return {
          'deviceName': deviceName,
          if (transport == 'ble')
            'bluetoothId': serverDeviceId
          else
            'macAddress': serverDeviceId,
          // The backend DeviceDto requires `protocol` (template name) as well
          // as `protocolId` — omitting it fails validation (400).
          'protocol': d.protocolName,
          'protocolId': d.protocolId,
          'advancedSettings': d.advancedSettings,
          // Backend requires totalDurationSeconds >= 1.
          'totalDurationSeconds':
              d.totalDurationSeconds > 0 ? d.totalDurationSeconds : 1,
          if (d.bodyPart != null) 'bodyPart': d.bodyPart,
          if (d.slotId != null) 'slotId': d.slotId,
        };
      }).toList();

      final dio = _ref.read(nodeDioProvider);
      final res = await dio.post(
        ApiEndpoints.sessionStart,
        data: {
          'organizationId': int.tryParse(orgId),
          // Client mode (clientId present) registers the run under the client so
          // the backend resolves the client name/demographics and the live feed
          // shows the client (not "Guest"). Guest mode → null id + guest flag.
          if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
          'isGuestMode': clientId == null || clientId.isEmpty,
          'isMobile': true,
          'devices': devicePayload,
        },
        options: Options(
          headers: {
            if (userId != null) 'x-user-id': userId,
            if (token != null) 'Authorization': token,
          },
        ),
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final sessionId = data['sessionId']?.toString();
      appLogger.i('SessionSync: ⇐ POST /sessions/start sessionId=$sessionId');
      return (sessionId != null && sessionId.isNotEmpty) ? sessionId : null;
    } on DioException catch (e) {
      appLogger.e(
        'SessionSync: start failed (status=${e.response?.statusCode}) '
        '${e.response?.data}',
      );
      // Token/subscription rejection must BLOCK the run (web parity); all other
      // failures stay tolerant so flaky networks don't brick the device.
      if (isTokenOrSubscriptionError(e)) {
        throw const InsufficientTokensException();
      }
      return null;
    } catch (e) {
      appLogger.e('SessionSync: start failed: $e');
      return null;
    }
  }

  /// POST /sessions/:sessionId/pause/:organizationId for the whole session.
  Future<void> pauseServerSession(String backendSessionId) =>
      _post(ApiEndpoints.sessionPause, backendSessionId, const {});

  /// POST /sessions/:sessionId/resume/:organizationId for the whole session.
  Future<void> resumeServerSession(String backendSessionId) =>
      _post(ApiEndpoints.sessionResume, backendSessionId, const {});

  /// POST /sessions/:sessionId/stop/:organizationId — ends the whole session.
  Future<void> stopServerSession(String backendSessionId) =>
      _post(ApiEndpoints.sessionStop, backendSessionId, const {'stopAll': true});

  /// Per-device backend control: targets a SINGLE device of the session by its
  /// [macAddress] (the backend pause/resume/stop DTOs accept `macAddress` and
  /// act on only that device, leaving the rest of the session running). Used
  /// both for remote control of foreign Wi-Fi sessions and to mirror a local
  /// per-device completion to the backend so it stops/deducts only that device
  /// instead of the whole session.
  Future<void> pauseServerSessionDevice(
          String backendSessionId, String macAddress) =>
      _post(ApiEndpoints.sessionPause, backendSessionId,
          {'macAddress': macAddress});

  Future<void> resumeServerSessionDevice(
          String backendSessionId, String macAddress) =>
      _post(ApiEndpoints.sessionResume, backendSessionId,
          {'macAddress': macAddress});

  Future<void> stopServerSessionDevice(
          String backendSessionId, String macAddress) =>
      _post(ApiEndpoints.sessionStop, backendSessionId,
          {'macAddress': macAddress});

  // ─────────── firmware-reported per-device lifecycle (rs:stop/pause/play) ───────────
  // Mirror a FIRMWARE-reported run-state change for ONE device to the backend,
  // the way the web does. The backend pairs a device by macAddress OR deviceName
  // OR slotId, BUT: (a) a BLE device has no macAddress server-side (it registered
  // by bluetoothId + deviceName), and (b) RESUME matches with AND-logic, so a
  // non-matching macAddress would FAIL the match. The only field that matches
  // across stop/pause/resume for a BLE device is the registered deviceName — so
  // we resolve it (the SAME mapping used at session start) and send only that
  // (+ slotId when known).

  /// Registered-name identity body for [localMac] (BLE-safe; deviceName + slotId).
  /// When [deviceName] is given (e.g. the registered name from the org-wide live
  /// feed for a FOREIGN device this phone never paired), it's used verbatim and
  /// no local lookup is attempted — that's the only way to target a foreign BLE
  /// device, which isn't in this phone's local registry.
  Future<Map<String, dynamic>> _deviceIdentityBody(
    String localMac, {
    String? slotId,
    String? deviceName,
  }) async {
    final String resolved;
    if (deviceName != null && deviceName.isNotEmpty) {
      resolved = deviceName;
    } else {
      final names = await _resolveRegisteredNames([localMac]);
      resolved = names[localMac.trim().toUpperCase()] ?? localMac;
    }
    return {
      'deviceName': resolved,
      if (slotId != null && slotId.isNotEmpty) 'slotId': slotId,
    };
  }

  Future<void> stopServerSessionDeviceByIdentity(
    String backendSessionId,
    String localMac, {
    String? slotId,
    String? deviceName,
  }) async {
    if (backendSessionId.isEmpty || localMac.isEmpty) return;
    final body = await _deviceIdentityBody(localMac,
        slotId: slotId, deviceName: deviceName);
    await _post(ApiEndpoints.sessionStop, backendSessionId, {
      ...body,
      'stopAll': false,
    });
  }

  Future<void> pauseServerSessionDeviceByIdentity(
    String backendSessionId,
    String localMac, {
    String? slotId,
    String? deviceName,
  }) async {
    if (backendSessionId.isEmpty || localMac.isEmpty) return;
    final body = await _deviceIdentityBody(localMac,
        slotId: slotId, deviceName: deviceName);
    await _post(ApiEndpoints.sessionPause, backendSessionId, body);
  }

  Future<void> resumeServerSessionDeviceByIdentity(
    String backendSessionId,
    String localMac, {
    String? slotId,
    String? deviceName,
  }) async {
    if (backendSessionId.isEmpty || localMac.isEmpty) return;
    final body = await _deviceIdentityBody(localMac,
        slotId: slotId, deviceName: deviceName);
    await _post(ApiEndpoints.sessionResume, backendSessionId, body);
  }

  Future<void> _post(
    String Function(String, String) endpoint,
    String backendSessionId,
    Map<String, dynamic> body,
  ) async {
    if (backendSessionId.isEmpty) return;
    try {
      final storage = _ref.read(secureStorageProvider);
      final token = await storage.getAccessToken();
      final userId = await storage.getUserId();
      final orgId = await storage.getSelectedOrgId();
      if (orgId == null || orgId.isEmpty) return;
      final dio = _ref.read(nodeDioProvider);
      await dio.post(
        endpoint(backendSessionId, orgId),
        data: body,
        options: Options(
          headers: {
            if (userId != null) 'x-user-id': userId,
            if (token != null) 'Authorization': token,
          },
        ),
      );
    } on DioException catch (e) {
      appLogger.e(
        'SessionSync: lifecycle post failed (status=${e.response?.statusCode}) '
        '${e.response?.data}',
      );
    } catch (e) {
      appLogger.e('SessionSync: lifecycle post failed: $e');
    }
  }

  /// Best-effort map of (normalized device id) → registered org device name.
  /// BLE units advertise on a MAC ±1 (last byte) from the registered hardware
  /// MAC, so each id and its ±1 variants are matched. Display-only — falls back
  /// to the device id when no match is found.
  Future<Map<String, String>> _resolveRegisteredNames(
    List<String> deviceIds,
  ) async {
    final nameByDevice = <String, String>{};
    if (deviceIds.isEmpty) return nameByDevice;
    String norm(String s) => s.trim().toUpperCase();
    String? adjacentMac(String mac, int delta) {
      final parts = norm(mac).split(':');
      if (parts.length != 6) return null;
      final last = int.tryParse(parts.last, radix: 16);
      if (last == null) return null;
      parts[5] = ((last + delta) & 0xFF)
          .toRadixString(16)
          .padLeft(2, '0')
          .toUpperCase();
      return parts.join(':');
    }

    // Friendly names are the name the device was CONNECTED/registered with, and
    // come from BOTH sources (one per transport): the org WiFi/cloud registry
    // AND this phone's locally-paired BLE devices. The WiFi org provider
    // deliberately excludes BLE, so without the paired list a BLE device's name
    // would wrongly fall back to its raw mac/bluetoothId.
    final nameByMac = <String, String>{};
    try {
      final registered = await _ref.read(wifiDevicesByOrgProvider.future);
      for (final d in registered) {
        if (d.name.trim().isNotEmpty) nameByMac[norm(d.macAddress)] = d.name;
      }
    } catch (e) {
      appLogger.w('SessionSync: could not load WiFi device names: $e');
    }
    try {
      final paired = await _ref.read(bleRepositoryProvider).getPairedDevices();
      for (final p in paired) {
        if (p.name.trim().isNotEmpty) {
          nameByMac.putIfAbsent(norm(p.macAddress), () => p.name);
        }
      }
    } catch (e) {
      appLogger.w('SessionSync: could not load paired BLE device names: $e');
    }

    for (final deviceId in deviceIds) {
      final id = norm(deviceId);
      final candidates = <String>[id];
      final plusOne = adjacentMac(id, 1);
      if (plusOne != null) candidates.add(plusOne);
      final minusOne = adjacentMac(id, -1);
      if (minusOne != null) candidates.add(minusOne);
      for (final c in candidates) {
        final name = nameByMac[c];
        if (name != null) {
          nameByDevice[id] = name;
          break;
        }
      }
    }
    return nameByDevice;
  }
}
