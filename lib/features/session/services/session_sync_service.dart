import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/logger.dart';
import '../../ble/services/ble_connector.dart';
import '../../devices/presentation/providers/wifi_devices_provider.dart';

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
        if (transport == 'ble') {
          final fwId =
              _ref.read(bleConnectorProvider).getFirmwareSessionId(d.localMac);
          if (fwId != null && fwId.isNotEmpty) serverDeviceId = fwId;
        }
        final deviceName =
            nameByDevice[d.localMac.trim().toUpperCase()] ?? d.localMac;
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
          'isGuestMode': true,
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

    try {
      final registered = await _ref.read(wifiDevicesByOrgProvider.future);
      final nameByMac = <String, String>{
        for (final d in registered)
          if (d.name.trim().isNotEmpty) norm(d.macAddress): d.name,
      };
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
    } catch (e) {
      appLogger.w('SessionSync: could not resolve device names: $e');
    }
    return nameByDevice;
  }
}
