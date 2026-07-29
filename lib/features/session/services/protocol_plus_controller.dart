import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/router/route_names.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/logger.dart';
import '../../advanced_settings/domain/advanced_settings_model.dart';
import '../../intake/domain/intake_models.dart';
import '../../ble/data/ble_repository.dart';
import '../../ble/domain/ble_device_model.dart';
import '../../ble/services/ble_connector.dart';
import '../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../protocols/domain/protocol_model.dart';
import '../../protocols/domain/protocol_plus_model.dart';
import '../../protocols/presentation/providers/protocol_provider.dart';
import '../domain/session_model.dart';
import '../presentation/providers/active_sessions_provider.dart';
import '../presentation/providers/live_sessions_provider.dart';
import 'background_session_runtime.dart';
import 'session_engine.dart';
import 'session_sync_service.dart';
import 'sessions_socket.dart';

/// Result of starting a Protocol Plus run on the backend.
class ProtocolPlusStartResult {
  final String sessionId;
  final int protocolCount;

  const ProtocolPlusStartResult({
    required this.sessionId,
    required this.protocolCount,
  });
}

/// One device's wiring for a server-driven Protocol Plus run. A single session
/// can contain several of these — one per selected device, each with its own
/// server session and (possibly different) Protocol Plus template.
class ProtocolPlusBinding {
  /// Local write target — BLE remoteId / Wi-Fi macAddress (what [SessionEngine]
  /// and the BLE connector use to address the device).
  final String localMac;

  /// The id registered with the server (firmware bluetoothId for BLE,
  /// macAddress for Wi-Fi). The server echoes this in `START_PROTOCOL`.
  final String serverDeviceId;

  /// The server-generated sessionId for THIS device's run.
  final String serverSessionId;

  /// The Protocol Plus template id running on this device.
  final String plusId;

  const ProtocolPlusBinding({
    required this.localMac,
    required this.serverDeviceId,
    required this.serverSessionId,
    required this.plusId,
  });

  Map<String, String> toMap() => {
        'localMac': localMac,
        'serverDeviceId': serverDeviceId,
        'serverSessionId': serverSessionId,
        'plusId': plusId,
      };

  static ProtocolPlusBinding? fromMap(Map map) {
    final localMac = map['localMac']?.toString() ?? '';
    final serverSessionId = map['serverSessionId']?.toString() ?? '';
    if (localMac.isEmpty || serverSessionId.isEmpty) return null;
    return ProtocolPlusBinding(
      localMac: localMac,
      serverDeviceId: map['serverDeviceId']?.toString() ?? localMac,
      serverSessionId: serverSessionId,
      plusId: map['plusId']?.toString() ?? '',
    );
  }
}

final protocolPlusControllerProvider = Provider<ProtocolPlusController>((ref) {
  final controller = ProtocolPlusController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Lists all Protocol Plus templates for the selection screen.
final protocolPlusListProvider = FutureProvider<List<ProtocolPlus>>((ref) {
  return ref.read(protocolPlusControllerProvider).getProtocolPlusList();
});

/// Delivery channel for the server-generated Protocol Plus socket bindings,
/// keyed by the local sessionId (the engine key). The session screen now opens
/// IMMEDIATELY when devices start — before the (network) server registration
/// finishes — so the bindings can't travel in the route arguments. Background
/// registration publishes them here, and the session screen watches this
/// provider and wires its `/sessions` socket the moment they arrive.
///
/// Not auto-disposed on purpose: the writer (background registration) and the
/// reader (session screen) may subscribe in either order, so the value must
/// survive until the screen has read it regardless of timing.
final protocolPlusBindingsProvider =
    StateProvider.family<List<ProtocolPlusBinding>, String>(
        (ref, sessionId) => const <ProtocolPlusBinding>[]);

/// One device's registration request — what the background registration needs
/// to register a Plus run with the server. The server device id (BLE firmware
/// bluetoothId vs Wi-Fi mac) is resolved during registration.
class ProtocolPlusRegistration {
  /// Local write target — BLE remoteId / Wi-Fi macAddress.
  final String deviceId;

  /// The Protocol Plus template id to run.
  final String plusId;

  /// Advanced settings to register with the server (derived from protocol[0]).
  final AdvancedSettings advanced;

  const ProtocolPlusRegistration({
    required this.deviceId,
    required this.plusId,
    required this.advanced,
  });
}

/// Server-driven Protocol Plus orchestration (parity with the web app):
///   1. POST /protocol-plus/start  → server starts protocol[0] + schedules the
///      remaining protocol switches as delayed jobs.
///   2. Connect the `/sessions` socket and, on each `START_PROTOCOL` broadcast
///      for THIS session/device, re-send that protocol to the device via the
///      existing [SessionEngine] senders (BLE config+PLAY or WiFi MQTT).
///
/// This never touches the normal single-protocol run — protocol[0] is started
/// by the usual flow; only the auto-switches flow through here.
class ProtocolPlusController {
  final Ref _ref;
  io.Socket? _socket;

  /// All devices wired into the current Protocol Plus session. The `/sessions`
  /// socket is a global broadcast, so each inbound `START_PROTOCOL` is matched
  /// against these bindings to find the right device + server session.
  final List<ProtocolPlusBinding> _bindings = <ProtocolPlusBinding>[];

  /// The LOCAL engine/session id (Uuid) for the current run — used to remove the
  /// active session when the run ends, independent of any screen.
  String? _localSessionId;

  /// Org id, captured to (re)join the org room so the server's room-scoped
  /// `session-event` (SESSION_STOPPED) broadcasts reach this client.
  String? _organizationId;

  /// Removes the engine state listener wired in [connectAll]. Lets the
  /// app-scoped controller detect run completion even with no screen mounted.
  void Function()? _removeEngineListener;

  /// Guards the one-time end-of-run teardown ([_finishRun]).
  bool _terminalHandled = false;

  /// The engine for the current run (set in [connectAll]) — used to replay a
  /// held protocol switch once a device reconnects.
  SessionEngine? _engine;

  /// Protocol switches that arrived while a (BLE) device was disconnected,
  /// keyed by localMac. Only the LATEST is kept; applied on reconnect.
  final Map<String, ({Protocol protocol, int index})> _pendingSwitches = {};

  /// Devices whose OWN server session has already been stopped because the user
  /// stopped that unit on the hardware. [stopServerSession] and [_finishRun]
  /// skip them so the end-of-run teardown doesn't re-post a stop for a session
  /// the server already closed.
  final Set<String> _serverStoppedDevices = <String>{};

  /// Watches per-device BLE connection so a held switch can be applied the
  /// moment the device reconnects.
  StreamSubscription<Map<String, BleConnectionStatus>>? _connStatesSub;
  Map<String, BleConnectionStatus> _lastConnStates = {};

  /// Periodic safety net that drains [_pendingSwitches]. The connection-state
  /// stream ([_applyPendingSwitchesOn]) only fires on the exact disconnected→
  /// connected transition — if that edge is missed, or a switch lands here after
  /// a failed/timed-out write (see the START_PROTOCOL handler), the held switch
  /// would otherwise strand the device on "SWITCHING" forever. This timer keeps
  /// retrying every connected device's pending switch until it succeeds, which
  /// is what makes the run converge instead of freezing on a flaky stack.
  Timer? _pendingSwitchReconciler;

  ProtocolPlusController(this._ref);

  /// Pretty-print any JSON-ish payload for debugging (falls back to toString).
  String _pretty(dynamic data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  /// GET /protocol-plus — list all Protocol Plus templates.
  Future<List<ProtocolPlus>> getProtocolPlusList() async {
    final dio = _ref.read(nodeDioProvider);
    final res = await dio.get(ApiEndpoints.protocolPlus);
    final data = res.data;
    appLogger
        .i('ProtocolPlus: ⇐ GET /protocol-plus payload:\n${_pretty(data)}');
    final List list = data is List
        ? data
        : (data is Map ? (data['data'] as List? ?? const []) : const []);
    return list
        .whereType<Map>()
        .map((e) => ProtocolPlus.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fetch a Protocol Plus by id with its sub-protocols FULLY POPULATED
  /// (each protocol's cycles inline). Prefer `GET /protocols/:id` — for a plus
  /// id the backend returns the protocol-plus with `.populate('protocolIds')`.
  /// Fall back to `GET /protocol-plus/:id` (ids only) if that endpoint 404s on
  /// an older server build.
  Future<ProtocolPlus> getProtocolPlusDetail(String id) async {
    final dio = _ref.read(nodeDioProvider);
    try {
      final res = await dio.get(ApiEndpoints.protocolById(id));
      final raw = res.data;
      appLogger
          .i('ProtocolPlus: ⇐ GET /protocols/$id payload:\n${_pretty(raw)}');
      final data = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
      return ProtocolPlus.fromJson((data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      appLogger.w(
        'ProtocolPlus: /protocols/$id failed (${e.response?.statusCode}); '
        'falling back to /protocol-plus/$id',
      );
      final res = await dio.get('${ApiEndpoints.protocolPlus}/$id');
      final raw = res.data;
      appLogger.i(
          'ProtocolPlus: ⇐ GET /protocol-plus/$id payload:\n${_pretty(raw)}');
      final data = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
      return ProtocolPlus.fromJson((data as Map).cast<String, dynamic>());
    }
  }

  /// POST /protocol-plus/start. Returns the server-generated sessionId.
  Future<ProtocolPlusStartResult> startProtocolPlus({
    required String protocolPlusId,
    required String deviceName,
    required String macAddress,
    required String transport,
    String? clientId,
    bool isGuestMode = true,
    bool isMobile = true,
    String? slotId,
    String? bodyPart,
    Map<String, dynamic>? advancedSettings,
  }) async {
    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    final userId = await storage.getUserId();
    final orgId = await storage.getSelectedOrgId();

    final dio = _ref.read(nodeDioProvider);
    // Build the payload as a value first so we can log EXACTLY what we sent if
    // the server rejects it (the device-identity 400 we're chasing).
    final payload = <String, dynamic>{
      'protocolPlusId': protocolPlusId,
      if (orgId != null) 'organizationId': int.tryParse(orgId),
      'clientId': clientId,
      'isGuestMode': isGuestMode,
      'isMobile': isMobile,
      'deviceName': deviceName,
      // BLE devices are identified by bluetoothId; Wi-Fi devices by macAddress.
      if (transport == 'ble')
        'bluetoothId': macAddress
      else
        'macAddress': macAddress,
      if (slotId != null) 'slotId': slotId,
      if (bodyPart != null) 'bodyPart': bodyPart,
      'advancedSettings': advancedSettings ?? const {},
    };

    try {
      final res = await dio.post(
        ApiEndpoints.protocolPlusStart,
        data: payload,
        options: Options(
          headers: {
            if (userId != null) 'x-user-id': userId,
            if (token != null) 'Authorization': token,
          },
        ),
      );

      appLogger.i(
        'ProtocolPlus: ⇐ POST /protocol-plus/start payload:\n${_pretty(res.data)}',
      );
      final data = (res.data as Map).cast<String, dynamic>();
      return ProtocolPlusStartResult(
        sessionId: data['sessionId']?.toString() ?? '',
        protocolCount: (data['protocolCount'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      // This is the line that was previously invisible: log the server's reason
      // AND the exact request, so the backend rejection (e.g. unregistered/
      // mismatched device id, BLE MAC ±1) is diagnosable from a shared log.
      appLogger.e(
        'ProtocolPlus: ❌ POST /protocol-plus/start FAILED '
        '(status=${e.response?.statusCode})\n'
        'SERVER BODY: ${e.response?.data}\n'
        'SENT PAYLOAD: $payload\n'
        'orgId(raw)=$orgId  transport=$transport  '
        'sentDeviceId=$macAddress  deviceName="$deviceName"',
      );
      rethrow;
    }
  }

  /// Build the auth headers + organizationId used by the session lifecycle
  /// endpoints. Returns null when no org is known so callers can no-op safely.
  Future<({String orgId, Options options})?> _sessionRequestContext() async {
    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    final userId = await storage.getUserId();
    final orgId = await storage.getSelectedOrgId();
    if (orgId == null || orgId.isEmpty) {
      appLogger
          .w('ProtocolPlus: no organizationId — cannot sync session state');
      return null;
    }

    return (
      orgId: orgId,
      options: Options(
        headers: {
          if (userId != null) 'x-user-id': userId,
          if (token != null) 'Authorization': token,
        },
      ),
    );
  }

  /// POST /sessions/:sessionId/pause/:organizationId for every bound device —
  /// pause the server-side Protocol Plus session(s) so they stay in sync.
  Future<void> pauseServerSession() async {
    if (_bindings.isEmpty) return;
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    final dio = _ref.read(nodeDioProvider);
    for (final b in _bindings) {
      try {
        final res = await dio.post(
          ApiEndpoints.sessionPause(b.serverSessionId, ctx.orgId),
          data: {'macAddress': b.localMac},
          options: ctx.options,
        );
        appLogger
            .i('ProtocolPlus: ⇐ POST pause payload:\n${_pretty(res.data)}');
      } on DioException catch (e) {
        appLogger.e(
          'ProtocolPlus: pause failed (status=${e.response?.statusCode}) '
          '${e.response?.data}',
        );
      } catch (e) {
        appLogger.e('ProtocolPlus: pause failed: $e');
      }
    }
  }

  /// POST /sessions/:sessionId/resume/:organizationId for every bound device.
  Future<void> resumeServerSession() async {
    if (_bindings.isEmpty) return;
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    final dio = _ref.read(nodeDioProvider);
    for (final b in _bindings) {
      try {
        final res = await dio.post(
          ApiEndpoints.sessionResume(b.serverSessionId, ctx.orgId),
          data: {'macAddress': b.localMac},
          options: ctx.options,
        );
        appLogger
            .i('ProtocolPlus: ⇐ POST resume payload:\n${_pretty(res.data)}');
      } on DioException catch (e) {
        appLogger.e(
          'ProtocolPlus: resume failed (status=${e.response?.statusCode}) '
          '${e.response?.data}',
        );
      } catch (e) {
        appLogger.e('ProtocolPlus: resume failed: $e');
      }
    }
  }

  /// POST /sessions/:sessionId/stop/:organizationId with `stopAll` for every
  /// bound device — ends the Protocol Plus session(s) and cancels the server's
  /// remaining switch jobs.
  Future<void> stopServerSession() async {
    if (_bindings.isEmpty) return;
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    final dio = _ref.read(nodeDioProvider);
    for (final b in _bindings) {
      // Already closed by a device-initiated stop — don't re-post.
      if (_serverStoppedDevices.contains(b.localMac)) continue;
      try {
        final res = await dio.post(
          ApiEndpoints.sessionStop(b.serverSessionId, ctx.orgId),
          data: const {'stopAll': true},
          options: ctx.options,
        );
        appLogger.i('ProtocolPlus: ⇐ POST stop payload:\n${_pretty(res.data)}');
      } on DioException catch (e) {
        appLogger.e(
          'ProtocolPlus: stop failed (status=${e.response?.statusCode}) '
          '${e.response?.data}',
        );
      } catch (e) {
        appLogger.e('ProtocolPlus: stop failed: $e');
      }
    }
  }

  /// The user stopped [localMac] ON THE DEVICE mid-sequence (the engine's
  /// firmware run-state detector confirmed it). Stop just that device's server
  /// session so the backend stops scheduling its remaining `START_PROTOCOL`
  /// switches and it drops out of the org live feed — which is also what stops
  /// the on-screen countdown, since the session card reads the feed's
  /// `remainingSeconds` in preference to the local engine timer.
  ///
  /// Devices are registered one server session each ([_registerPlusDevices]), so
  /// this affects only the stopped unit; the rest of a multi-device Plus run
  /// carries on. When it was the last live device the engine goes terminal
  /// anyway and the existing engine listener runs [_finishRun].
  Future<void> _handlePlusDeviceStopped(String localMac) async {
    if (!_serverStoppedDevices.add(localMac)) return; // already handled
    ProtocolPlusBinding? binding;
    for (final b in _bindings) {
      if (b.localMac == localMac) {
        binding = b;
        break;
      }
    }
    if (binding == null) return;

    // Drop any held switch for this device — it is never being applied now.
    _pendingSwitches.remove(localMac);
    _engine?.setPlusSwitchPending(localMac, false);

    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    try {
      final res = await _ref.read(nodeDioProvider).post(
            ApiEndpoints.sessionStop(binding.serverSessionId, ctx.orgId),
            data: const {'stopAll': true},
            options: ctx.options,
          );
      appLogger.i(
        'ProtocolPlus: device-initiated stop → server session '
        '${binding.serverSessionId} stopped:\n${_pretty(res.data)}',
      );
    } on DioException catch (e) {
      appLogger.e(
        'ProtocolPlus: device-stop server stop failed for $localMac '
        '(status=${e.response?.statusCode}) ${e.response?.data}',
      );
    } catch (e) {
      appLogger.e(
        'ProtocolPlus: device-stop server stop failed for $localMac: $e',
      );
    }
  }

  /// Backward-compatible single-device entry point. Wraps [connectAll] with a
  /// one-device binding (used by the single-device launch flow).
  Future<void> connect({
    required String sessionId,
    required String macAddress,
    required SessionEngine engine,
    String? serverDeviceId,
    String plusId = '',
    String? localSessionId,
  }) {
    return connectAll(
      bindings: [
        ProtocolPlusBinding(
          localMac: macAddress,
          serverDeviceId: serverDeviceId ?? macAddress,
          serverSessionId: sessionId,
          plusId: plusId,
        ),
      ],
      engine: engine,
      localSessionId: localSessionId,
    );
  }

  /// Register every Plus device with the server (POST /protocol-plus/start) and
  /// publish the resulting socket bindings to [protocolPlusBindingsProvider] so
  /// the already-open session screen can wire its socket when they arrive.
  ///
  /// Runs in the BACKGROUND after navigation — this is what lets the session
  /// screen open the instant the devices start instead of waiting on these
  /// network calls. The POSTs run concurrently; per-device failures are logged
  /// and skipped (the others still register). Returns the bindings it produced.
  Future<List<ProtocolPlusBinding>> registerAndPublishBindings({
    required String sessionId,
    required List<ProtocolPlusRegistration> plans,
    required String transport,
    String? clientId,
  }) async {
    if (plans.isEmpty) return const [];

    // Resolve registered (display) names once for all devices — best-effort.
    final nameByDevice =
        await _resolveRegisteredNames(plans.map((p) => p.deviceId).toList());

    // If any device hits a token/subscription rejection we must abort the whole
    // launch (block the run, web parity). We don't throw mid-flight, though:
    // other devices may already have registered + locked tokens server-side, so
    // we let all POSTs settle, PUBLISH the succeeded bindings (so the launch
    // catch can roll them back / stop them), then throw.
    var tokenErrorSeen = false;

    final results = await Future.wait(plans.map((plan) async {
      // BLE registers by the firmware-reported bluetoothId (captured over BLE
      // after connect), not the phone-local id; Wi-Fi uses the macAddress.
      var serverDeviceId = plan.deviceId;
      String? connectedName;
      if (transport == 'ble') {
        final connector = _ref.read(bleConnectorProvider);
        final fwId = connector.getFirmwareSessionId(plan.deviceId);
        if (fwId != null && fwId.isNotEmpty) {
          serverDeviceId = fwId;
        } else {
          appLogger.w(
            'ProtocolPlus: no firmware bluetoothId for ${plan.deviceId}; '
            'using local id',
          );
        }
        // Live "Connected to <name>" advertised name — used when neither the
        // org registry nor the paired list resolved a name.
        connectedName = connector.getConnectedDeviceName(plan.deviceId);
      }
      // Send the device's NAME (never the raw mac/bluetoothId): registered name
      // → live connected name → mac as last resort.
      final deviceName = nameByDevice[plan.deviceId.trim().toUpperCase()] ??
          connectedName ??
          plan.deviceId;
      try {
        final result = await startProtocolPlus(
          protocolPlusId: plan.plusId,
          deviceName: deviceName,
          macAddress: serverDeviceId,
          transport: transport,
          // Register under the client in Client mode so the backend ties the
          // run to the client (live feed name, history). Guest → null + guest.
          clientId: clientId,
          isGuestMode: clientId == null || clientId.isEmpty,
          advancedSettings: plan.advanced.toJson(),
        );
        if (result.sessionId.isEmpty) {
          appLogger
              .e('ProtocolPlus: empty server sessionId for ${plan.deviceId}');
          return null;
        }
        appLogger.i(
          'ProtocolPlus: registered ${plan.deviceId} '
          '(serverSessionId=${result.sessionId}, count=${result.protocolCount})',
        );
        return ProtocolPlusBinding(
          localMac: plan.deviceId,
          serverDeviceId: serverDeviceId,
          serverSessionId: result.sessionId,
          plusId: plan.plusId,
        );
      } on DioException catch (e) {
        // Flag token/subscription rejections; we throw after publishing (below)
        // so already-registered devices can be rolled back by the launch catch.
        if (isTokenOrSubscriptionError(e)) {
          tokenErrorSeen = true;
        }
        appLogger.e('ProtocolPlus: failed to register ${plan.deviceId}: $e');
        return null;
      } catch (e) {
        appLogger.e('ProtocolPlus: failed to register ${plan.deviceId}: $e');
        return null;
      }
    }));

    final bindings = results.whereType<ProtocolPlusBinding>().toList();
    // Publish — the session screen is (or will be) watching this key. Setting
    // the value is safe whether the screen subscribed before or after us.
    _ref.read(protocolPlusBindingsProvider(sessionId).notifier).state =
        bindings;
    appLogger.i(
      'ProtocolPlus: published ${bindings.length} binding(s) for session '
      '$sessionId',
    );
    // Bindings are now published, so launchSession's catch can stop any that
    // succeeded before this throw aborts the run.
    if (tokenErrorSeen) {
      throw const InsufficientTokensException();
    }
    return bindings;
  }

  /// Best-effort map of (normalized device id) → registered org device name.
  /// BLE units advertise on a MAC ±1 (last byte) from the registered hardware
  /// MAC, so each id and its ±1 variants are matched. Display-only — falls back
  /// to the device id when no match is found, so failures here never block a run.
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

    // Friendly names are the name the device was CONNECTED/registered with, from
    // BOTH sources (one per transport): the org WiFi/cloud registry AND this
    // phone's locally-paired BLE devices. The WiFi org provider deliberately
    // excludes BLE, so without the paired list a BLE device's name would wrongly
    // fall back to its raw mac/bluetoothId.
    final nameByMac = <String, String>{};
    try {
      final registered = await _ref.read(wifiDevicesByOrgProvider.future);
      for (final d in registered) {
        if (d.name.trim().isNotEmpty) nameByMac[norm(d.macAddress)] = d.name;
      }
    } catch (e) {
      appLogger.w('ProtocolPlus: could not load WiFi device names: $e');
    }
    try {
      final paired = await _ref.read(bleRepositoryProvider).getPairedDevices();
      for (final p in paired) {
        if (p.name.trim().isNotEmpty) {
          nameByMac.putIfAbsent(norm(p.macAddress), () => p.name);
        }
      }
    } catch (e) {
      appLogger.w('ProtocolPlus: could not load paired BLE device names: $e');
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

  /// Open ONE `/sessions` socket and route each server `START_PROTOCOL` to the
  /// matching device in [bindings]. Supports multiple devices, each with its
  /// own server session and (possibly different) Protocol Plus template.
  Future<void> connectAll({
    required List<ProtocolPlusBinding> bindings,
    required SessionEngine engine,
    String? localSessionId,
  }) async {
    final incoming =
        bindings.where((b) => b.serverSessionId.isNotEmpty).toList();
    if (incoming.isEmpty) {
      appLogger.w('ProtocolPlus: connectAll called with no valid bindings');
      return;
    }

    // If a live socket is already wired to these exact bindings (e.g. the user
    // navigated away and back into the session screen mid-run), keep it instead
    // of recycling. This removes the brief reconnect gap during which a server
    // START_PROTOCOL switch could be missed. The SessionEngine for a given
    // sessionId is the same cached instance across re-entry, so the existing
    // socket's handler still targets the right engine.
    if (_socket != null &&
        (_socket?.connected ?? false) &&
        _sameBindings(_bindings, incoming)) {
      appLogger.i(
        'ProtocolPlus: reusing existing live socket '
        '(${incoming.length} binding(s)) — skipping reconnect',
      );
      return;
    }

    // Tear down any previous connection before opening a new one.
    dispose();

    _bindings
      ..clear()
      ..addAll(incoming);
    _localSessionId = localSessionId;
    _terminalHandled = false;
    _engine = engine;
    _pendingSwitches.clear();
    _serverStoppedDevices.clear();

    // Apply any protocol switch that was held while a device was disconnected,
    // the moment that device reconnects (BLE). Survives screen changes.
    _connStatesSub?.cancel();
    _lastConnStates = {};
    _connStatesSub = _ref
        .read(bleConnectorProvider)
        .connectionStates
        .listen(_applyPendingSwitchesOn);

    // Safety net for the above: re-attempt held switches on a fixed cadence too,
    // not only on the connection-state edge. Covers missed transitions and
    // switches re-queued after a failed/timed-out write.
    _pendingSwitchReconciler?.cancel();
    _pendingSwitchReconciler = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _reconcilePendingSwitches(),
    );

    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    _organizationId = await storage.getSelectedOrgId();

    // Detect run completion app-scoped (not tied to the screen): when the engine
    // reaches a terminal state, end the run everywhere — even if no SessionScreen
    // is mounted. This is what frees the device after an off-screen Plus finish.
    // fireImmediately:true also covers the race where the run already ended
    // before registration produced these bindings (engine already terminal).
    // A device stopped ON THE DEVICE mid-sequence. Each Plus device owns its own
    // server session, so stop exactly that one — the others keep running and
    // keep receiving their switches.
    engine.onPlusDeviceStoppedByUser =
        (mac) => unawaited(_handlePlusDeviceStopped(mac));

    _removeEngineListener?.call();
    _removeEngineListener = engine.addListener(
      (state) {
        if (state.status == SessionStatus.completed ||
            state.status == SessionStatus.stopped) {
          unawaited(_finishRun(stopServer: true));
        }
      },
      fireImmediately: true,
    );

    // Derive the socket endpoint from the REST base so it tracks config changes.
    // Shared with the org-wide live-session + credits feeds via [SessionsSocket]
    // so all consumers dial the identical host/proxy path.
    appLogger.i(
      'ProtocolPlus: connecting socket → ${SessionsSocket.urlFor('/sessions')} '
      '(path=${SessionsSocket.path})',
    );

    final socket = SessionsSocket.buildSocket(
      token: token,
      namespace: '/sessions',
    );
    _socket = socket;

    socket.onConnect((_) {
      appLogger.i('ProtocolPlus: ✅ socket connected (id=${socket.id})');
      // Join the org room so the server's room-scoped `session-event`
      // (SESSION_STOPPED) broadcasts reach us — mirrors the web app. Re-emitted
      // on every (re)connect so it survives reconnects.
      final orgId = int.tryParse(_organizationId ?? '');
      if (orgId != null) {
        socket.emit('subscribe-organization', {'organizationId': orgId});
        appLogger.i('ProtocolPlus: subscribed to organization-$orgId');
      } else {
        appLogger.w(
          'ProtocolPlus: no organizationId — cannot subscribe to stop events',
        );
      }
    });
    socket.onDisconnect(
        (r) => appLogger.w('ProtocolPlus: socket disconnected ($r)'));
    socket.onConnectError(
      (e) => appLogger.e('ProtocolPlus: ❌ socket connect error: $e'),
    );
    socket.onError((e) => appLogger.e('ProtocolPlus: socket error: $e'));

    // DEBUG: log EVERY inbound event so we can see whether START_PROTOCOL
    // (or anything) is actually arriving from the server.
    socket.onAny(
      (event, data) => appLogger.i('ProtocolPlus: ⇐ event "$event": $data'),
    );

    // `START_PROTOCOL` is a GLOBAL broadcast from the server, so we match it to
    // one of our bindings (session + device) before acting.
    socket.on('START_PROTOCOL', (data) async {
      try {
        if (data is! Map) return;
        final evSession = data['sessionId']?.toString();
        final evMac = data['macAddress']?.toString();
        final evBt = data['bluetoothId']?.toString();

        // Find the binding whose server session matches AND whose device id
        // (local write target OR the id we registered with the server) matches
        // the event. The device may be addressed by macAddress (Wi-Fi) or
        // bluetoothId (BLE, the firmware-reported id).
        bool matchesId(ProtocolPlusBinding b, String? v) =>
            v != null &&
            v.isNotEmpty &&
            (v == b.localMac || v == b.serverDeviceId);
        ProtocolPlusBinding? binding;
        for (final b in _bindings) {
          if (b.serverSessionId != evSession) continue;
          if (matchesId(b, evMac) || matchesId(b, evBt)) {
            binding = b;
            break;
          }
        }
        if (binding == null) return;

        final index = (data['protocolIndex'] as num?)?.toInt() ?? 0;

        // The event's `protocol` may arrive as a full populated object, a
        // partial object (no cycles), or just an id from the protocolIds array.
        // Resolve to a full Protocol (with cycles) before sending to the device.
        final protocol = await _resolveEventProtocol(data, index);
        if (protocol == null || protocol.cycles.isEmpty) {
          appLogger.e(
            'ProtocolPlus: no usable protocol for index $index — switch skipped',
          );
          return;
        }

        appLogger.i(
          'ProtocolPlus: START_PROTOCOL (session=$evSession, index=$index, '
          'device=${binding.localMac}, protocol=${protocol.templateName}, '
          'cycles=${protocol.cycles.length})',
        );

        // If this is a BLE run and the device's link is currently down, the
        // config+PLAY write can't reach it — HOLD the latest switch and apply it
        // the moment the device reconnects (see _applyPendingSwitchesOn).
        final isBle = engine.transport == SessionTransport.ble;
        if (isBle &&
            !_ref.read(bleConnectorProvider).isConnected(binding.localMac)) {
          _pendingSwitches[binding.localMac] =
              (protocol: protocol, index: index);
          // Tell the engine a switch is outstanding: while it is, the device's
          // `rs:stop` is the expected idle waiting for this protocol, not the
          // user pressing STOP on the unit.
          engine.setPlusSwitchPending(binding.localMac, true);
          appLogger.w(
            'ProtocolPlus: ${binding.localMac} not connected — holding switch '
            'index=$index until reconnect',
          );
          return;
        }

        // Write to the device using our LOCAL id (BLE remoteId / Wi-Fi mac).
        // The event's `bluetoothId` is the firmware id, which is NOT what the
        // BLE connector uses to address the device — so we must not write to it.
        final ok = await engine.applyProtocolPlusSwitch(
          binding.localMac,
          protocol,
          index,
        );
        // If the write failed/timed out (e.g. the device dropped between the
        // connection check and the write), DON'T lose the switch — queue it so
        // the reconciler retries once the link is healthy again. Otherwise the
        // device would strand on "SWITCHING".
        if (!ok) {
          _pendingSwitches[binding.localMac] =
              (protocol: protocol, index: index);
          engine.setPlusSwitchPending(binding.localMac, true);
          appLogger.w(
            'ProtocolPlus: switch apply failed for ${binding.localMac} '
            '(index=$index) — queued for retry',
          );
        } else {
          engine.setPlusSwitchPending(binding.localMac, false);
        }
      } catch (e) {
        appLogger.e('ProtocolPlus: failed to handle START_PROTOCOL: $e');
      }
    });

    // Server lifecycle events (room-scoped). When the server reports this run
    // STOPPED — whether from our own completion stop, a manual stop, or another
    // client/device — free the device locally so it leaves the live/busy list,
    // even if no SessionScreen is mounted.
    socket.on('session-event', (data) {
      try {
        if (data is! Map) return;
        final type = data['type']?.toString();

        // SESSION_UPDATED carries per-device telemetry (pad state, warnings,
        // faults, sensors) — the device→app channel the web card renders. Feed
        // it to the engine, which matches each device by MAC against this
        // session and ignores devices that aren't ours, so no binding gate is
        // needed here.
        if (type == 'SESSION_UPDATED') {
          final devices = data['devices'];
          final engine = _engine;
          if (devices is List && engine != null) {
            for (final dev in devices) {
              if (dev is! Map) continue;
              final m = dev.cast<String, dynamic>();
              final id = (m['macAddress'] ?? m['slotId'] ?? m['deviceName'])
                  ?.toString();
              if (id == null || id.isEmpty) continue;
              engine.updateDeviceTelemetry(id, m);
            }
          }
          return;
        }

        // SESSION_PAUSED / SESSION_RESUMED — another client or the backend
        // changed this run's lifecycle. Reconcile the local UI without
        // re-issuing device commands (mirrors the web's socket handlers).
        if (type == 'SESSION_PAUSED' || type == 'SESSION_RESUMED') {
          final evSession = data['sessionId']?.toString();
          if (evSession == null || evSession.isEmpty) return;
          if (!_bindings.any((b) => b.serverSessionId == evSession)) return;
          _engine?.applyRemoteLifecycle(
            type == 'SESSION_PAUSED'
                ? SessionStatus.paused
                : SessionStatus.running,
          );
          return;
        }

        if (type != 'SESSION_STOPPED') return;
        final evSession = data['sessionId']?.toString();
        if (evSession == null || evSession.isEmpty) return;
        final matches = _bindings.any((b) => b.serverSessionId == evSession);
        if (!matches) return;
        appLogger
            .i('ProtocolPlus: ⇐ SESSION_STOPPED for $evSession — ending run');
        // Server already ended it; just free locally (don't re-call stop).
        unawaited(_finishRun(stopServer: false));
      } catch (e) {
        appLogger.e('ProtocolPlus: failed to handle session-event: $e');
      }
    });

    socket.connect();
  }

  /// Resolve the `START_PROTOCOL` payload into a full [Protocol] with cycles.
  /// Handles every shape the server may send:
  ///  - a full populated protocol object (has `cycles`)
  ///  - a partial object (only `_id`/`template_name`)
  ///  - just an id string (an element of the `protocolIds` array)
  /// When cycles are missing, the full protocol is fetched by id.
  Future<Protocol?> _resolveEventProtocol(Map data, int index) async {
    final protoJson = data['protocol'];
    String? protoId;
    Protocol? protocol;

    if (protoJson is Map) {
      final map = protoJson.cast<String, dynamic>();
      protoId = map['_id']?.toString() ?? map['id']?.toString();
      final cycles = map['cycles'];
      if (cycles is List && cycles.isNotEmpty) {
        protocol = Protocol.fromJson(map);
      }
    } else if (protoJson is String) {
      protoId = protoJson;
    }

    // Fallbacks for an id sent alongside the (possibly absent) protocol object.
    protoId ??=
        data['protocolId']?.toString() ?? data['protocol_id']?.toString();

    if ((protocol == null || protocol.cycles.isEmpty) &&
        protoId != null &&
        protoId.isNotEmpty) {
      try {
        protocol = await _ref.read(protocolDetailProvider(protoId).future);
      } catch (e) {
        appLogger.e(
          'ProtocolPlus: failed to fetch protocol id=$protoId (index=$index): $e',
        );
      }
    }

    return protocol;
  }

  /// True when two binding lists describe the same run — same set of
  /// (localMac, serverSessionId) pairs — so a live socket can be reused instead
  /// of being torn down and reconnected.
  bool _sameBindings(
    List<ProtocolPlusBinding> a,
    List<ProtocolPlusBinding> b,
  ) {
    if (a.length != b.length) return false;
    String key(ProtocolPlusBinding x) => '${x.localMac}|${x.serverSessionId}';
    final sa = a.map(key).toSet();
    final sb = b.map(key).toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }

  /// End-of-run teardown, app-scoped so it works even with no screen mounted:
  ///   1. (optionally) tell the server to stop — it deletes the session, cancels
  ///      the remaining Plus jobs, and broadcasts SESSION_STOPPED to other clients.
  ///   2. remove the LOCAL active session so the device leaves the busy list.
  ///   3. stop the background service and tear down the socket.
  /// Idempotent — runs once per run via [_terminalHandled].
  Future<void> _finishRun({required bool stopServer}) async {
    if (_terminalHandled) return;
    _terminalHandled = true;
    final localId = _localSessionId;
    final engine = _engine;

    // Snapshot the completed run for post-session review BEFORE tearing down
    // (removeSession/stopService), so the "needs review" card survives the live
    // card being dropped. Idempotent — the engine tick may have queued it too.
    engine?.enqueuePendingOutcome();

    // Belt-and-suspenders terminal STOP. Nothing else guarantees the physical
    // device halts at end-of-run: the server's stop can't reach a BLE unit at
    // all, and the firmware self-stop (per-protocol totalDuration) is the only
    // thing ending a Plus run — if it misfires (a late/half-applied switch, a
    // wrong duration) the device keeps running long after the app shows
    // "completed". Explicitly STOP every bound device here. stopDevice() is
    // idempotent and already handles WiFi (playCmd=2) vs BLE and the
    // disconnected/idle-between-protocols Plus case, so a redundant stop on an
    // already-stopped device is harmless.
    if (engine != null) {
      for (final b in _bindings) {
        try {
          await engine.stopDevice(b.localMac);
        } catch (e) {
          appLogger.w(
            'ProtocolPlus: terminal stopDevice(${b.localMac}) failed: $e',
          );
        }
      }
    }

    if (stopServer) {
      try {
        await stopServerSession();
      } catch (e) {
        appLogger.e('ProtocolPlus: stopServerSession during finish failed: $e');
      }
    }

    if (localId != null && localId.isNotEmpty) {
      try {
        await _ref.read(activeSessionsProvider.notifier).removeSession(localId);
      } catch (e) {
        appLogger.e('ProtocolPlus: removeSession($localId) failed: $e');
      }
      try {
        await _ref
            .read(backgroundSessionRuntimeProvider.notifier)
            .stopService(sessionId: localId);
      } catch (e) {
        appLogger.e('ProtocolPlus: stopService($localId) failed: $e');
      }
    }

    dispose();
  }

  /// On each BLE connection-state change, replay a held protocol switch for any
  /// bound device that JUST transitioned to `connected`.
  void _applyPendingSwitchesOn(Map<String, BleConnectionStatus> states) {
    final engine = _engine;
    if (engine == null) {
      _lastConnStates = Map.of(states);
      return;
    }
    for (final b in _bindings) {
      final prev = _lastConnStates[b.localMac];
      final now = states[b.localMac];
      final justConnected = now == BleConnectionStatus.connected &&
          prev != BleConnectionStatus.connected;
      if (!justConnected) continue;
      _applyPendingSwitch(engine, b.localMac, reason: 'reconnected');
    }
    _lastConnStates = Map.of(states);
  }

  /// Fixed-cadence safety net: re-apply any held switch for a device that is
  /// CURRENTLY connected, regardless of whether we observed the reconnect edge.
  /// This is what converges a run that would otherwise sit on "SWITCHING"
  /// because a connection-state transition was missed or a write timed out.
  void _reconcilePendingSwitches() {
    final engine = _engine;
    if (engine == null || _pendingSwitches.isEmpty) return;
    final connector = _ref.read(bleConnectorProvider);
    for (final b in _bindings) {
      if (!_pendingSwitches.containsKey(b.localMac)) continue;
      if (!connector.isConnected(b.localMac)) continue;
      _applyPendingSwitch(engine, b.localMac, reason: 'reconciler');
    }
  }

  /// Remove and apply the held switch for [mac] (no-op if none). The synchronous
  /// `remove` before any await makes this safe against the connection-state
  /// listener and the reconciler racing for the same entry — whoever removes it
  /// first applies it; the other sees null and skips.
  void _applyPendingSwitch(SessionEngine engine, String mac,
      {required String reason}) {
    final pending = _pendingSwitches.remove(mac);
    if (pending == null) return;
    appLogger.i(
      'ProtocolPlus: applying held switch for $mac (index=${pending.index}, '
      'via=$reason)',
    );
    // No longer HELD, but the write below still keeps the device idle for a few
    // seconds — applyProtocolPlusSwitch marks itself in-flight for that, so the
    // stop detector stays suppressed across the handover.
    engine.setPlusSwitchPending(mac, false);
    unawaited(
      engine
          .applyProtocolPlusSwitch(mac, pending.protocol, pending.index)
          .then((ok) {
        // Re-queue on failure so the next reconciler tick retries — keep trying
        // until the device actually accepts the switch.
        if (!ok && _engine != null) {
          _pendingSwitches[mac] = pending;
          engine.setPlusSwitchPending(mac, true);
          appLogger.w(
            'ProtocolPlus: held switch for $mac (index=${pending.index}) '
            'still failing — will retry',
          );
        }
      }),
    );
  }

  void dispose() {
    _removeEngineListener?.call();
    _removeEngineListener = null;
    _connStatesSub?.cancel();
    _connStatesSub = null;
    _pendingSwitchReconciler?.cancel();
    _pendingSwitchReconciler = null;
    _pendingSwitches.clear();
    _serverStoppedDevices.clear();
    _lastConnStates = {};
    // Detach before dropping the reference, or a late confirmation from an
    // engine that outlives this run would call back into a torn-down controller.
    _engine?.onPlusDeviceStoppedByUser = null;
    _engine = null;
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _bindings.clear();
    _localSessionId = null;
    _organizationId = null;
  }
}

/// Ordered display names for the Protocol Plus sequence chips. Prefers the
/// populated sub-protocol template names; falls back to the raw ids when the
/// server only returned ids.
List<String> _protocolPlusSequenceNames(
  List<Protocol> populated,
  List<String> orderedIds,
) {
  if (populated.isNotEmpty) {
    return populated.map((p) => p.templateName).toList();
  }
  return List<String>.from(orderedIds);
}

/// Advanced settings derived from a protocol's own fields. Keeps the
/// edge-cycle flags (cycle1/cycle5) and vibration range in sync with the
/// protocol so the firmware doesn't run an unexpected hot initiation cycle.
AdvancedSettings _advancedFromProtocol(Protocol p) => AdvancedSettings(
      cycle1Initiation: p.cycle1,
      cycle5Completion: p.cycle5,
      vibrationSweepMin: p.vibmin,
      vibrationSweepMax: p.vibmax,
      vibMin: p.vibmin,
      vibMax: p.vibmax,
      hotDrop: p.hotdrop,
      coldDrop: p.colddrop,
    );

/// One device's selection for a session launch. [protocol] is the user's pick;
/// when it's a Protocol Plus template, the run is server-driven (protocol[0]
/// starts locally, the rest arrive via the `/sessions` socket).
class SessionDeviceSelection {
  final String deviceId;
  final Protocol protocol;
  final AdvancedSettings advanced;

  const SessionDeviceSelection({
    required this.deviceId,
    required this.protocol,
    required this.advanced,
  });
}

/// Single-device Protocol Plus entry point (auto-detect from the protocol list).
/// Kept for callers that only know a plusId + deviceId; delegates to
/// [launchSession].
Future<void> launchProtocolPlusSession(
  WidgetRef ref,
  BuildContext context, {
  required Protocol plusProtocol,
  required String deviceId,
  required String transport,
}) {
  return launchSession(
    ref,
    context,
    selections: [
      SessionDeviceSelection(
        deviceId: deviceId,
        protocol: plusProtocol,
        advanced: _advancedFromProtocol(plusProtocol),
      ),
    ],
    transport: transport,
  );
}

/// Unified session launcher. Handles any mix of normal protocols and Protocol
/// Plus templates across multiple devices in ONE session/engine:
///   - normal device  → its protocol runs and auto-completes as usual.
///   - Plus device     → protocol[0] starts locally, the server schedules the
///                        switches, and one socket routes each `START_PROTOCOL`
///                        to the right device.
/// Every selected device is started; Plus devices are each registered with the
/// server and wired into the live session screen via per-device bindings.
Future<void> launchSession(
  WidgetRef ref,
  BuildContext context, {
  required List<SessionDeviceSelection> selections,
  required String transport,
  String? delayedDeviceId,
  String? clientId,
  GuidedAssessmentData? intake,
}) async {
  if (selections.isEmpty) return;
  final controller = ref.read(protocolPlusControllerProvider);
  final transportEnum =
      transport == 'wifi' ? SessionTransport.wifi : SessionTransport.ble;
  final deviceIds = selections.map((s) => s.deviceId).toList();
  String? sessionId;
  try {
    final protocolByDevice = <String, Protocol>{};
    final advancedByDevice = <String, AdvancedSettings>{};
    final plusDeviceIds = <String>{};
    final durationsByDevice = <String, int>{};
    final plusPlans = <ProtocolPlusRegistration>[];
    // Per-device tracker data so each Plus device gets its own progress card.
    final plusNameByDevice = <String, String>{};
    final plusSequenceByDevice = <String, List<String>>{};
    final plusDurationsByDevice = <String, List<int>>{};
    final plusDelayByDevice = <String, int>{};

    // Admin-defined post-session questions per protocol (incl. each Plus
    // sub-protocol), for the post-session outcomes sheet.
    final questionsByProtocolName = <String, List<ProtocolQuestion>>{};
    void recordQuestions(Protocol p) {
      if (p.questions.isNotEmpty) {
        questionsByProtocolName[p.templateName] = p.questions;
      }
    }

    for (final sel in selections) {
      if (sel.protocol.isProtocolPlus) {
        final detail = await controller.getProtocolPlusDetail(sel.protocol.id);
        final orderedIds = detail.protocolIds;
        final populated = detail.protocols;
        if (orderedIds.isEmpty && populated.isEmpty) {
          throw StateError(
              'Protocol Plus "${sel.protocol.templateName}" has no protocols');
        }
        // protocol[0] full object (cycles). Prefer populated; never fetch plus id.
        Protocol first;
        if (populated.isNotEmpty && populated.first.cycles.isNotEmpty) {
          first = populated.first;
        } else {
          final fid = orderedIds.first;
          if (fid == sel.protocol.id) {
            throw StateError('protocolIds[0] equals the plus id ($fid)');
          }
          first = await ref.read(protocolDetailProvider(fid).future);
        }
        if (first.cycles.isEmpty) {
          throw StateError('protocol[0] (${first.templateName}) has no cycles');
        }
        final advanced = _advancedFromProtocol(first);
        protocolByDevice[sel.deviceId] = first;
        advancedByDevice[sel.deviceId] = advanced;
        plusDeviceIds.add(sel.deviceId);
        if (detail.totalDuration > 0) {
          durationsByDevice[sel.deviceId] = detail.totalDuration;
        }
        plusPlans.add(ProtocolPlusRegistration(
          deviceId: sel.deviceId,
          plusId: sel.protocol.id,
          advanced: advanced,
        ));
        plusNameByDevice[sel.deviceId] = detail.templateName;
        plusSequenceByDevice[sel.deviceId] =
            _protocolPlusSequenceNames(populated, orderedIds);
        // Questions for each sub-protocol (populated docs carry them; `first`
        // covers the ids-only case where only protocol[0] was fetched).
        recordQuestions(first);
        for (final p in populated) {
          recordQuestions(p);
        }
        // Per-sub-protocol durations in the SAME order as the sequence names,
        // so the live tracker can show each protocol's time under its name.
        plusDurationsByDevice[sel.deviceId] =
            populated.map((p) => p.totalDurationSeconds).toList();
        plusDelayByDevice[sel.deviceId] = detail.delay;
      } else {
        protocolByDevice[sel.deviceId] = sel.protocol;
        advancedByDevice[sel.deviceId] = sel.advanced;
        recordQuestions(sel.protocol);
      }
    }

    sessionId = const Uuid().v4();
    final engine = ref.read(sessionEngineFamilyProvider(sessionId).notifier);
    // Thread the Client/Guest + Guided Assessment context so the intake POSTed
    // on session capture carries clientType/clientId and the guided fields.
    engine.setClientContext(clientId: clientId, intake: intake);
    final commonProtocol = protocolByDevice[deviceIds.first]!;
    final commonAdvanced = advancedByDevice[deviceIds.first]!;
    final effectiveDelayedDeviceId =
        delayedDeviceId != null && deviceIds.contains(delayedDeviceId)
            ? delayedDeviceId
            : null;

    engine.prepareSession(deviceIds: deviceIds, transport: transportEnum);
    engine.loadSession(
      commonProtocol,
      deviceIds,
      transport: transportEnum,
      advancedSettings: commonAdvanced,
      advancedSettingsByDevice: advancedByDevice,
      delayedDeviceId: effectiveDelayedDeviceId,
      protocolByDevice: protocolByDevice,
      wifiConfigAlreadyPublished: false,
    );
    // AFTER loadSession (which rebuilds the engine state) so the questions
    // aren't wiped — this was why the outcomes sheet showed none.
    engine.setSessionQuestions(questionsByProtocolName);
    if (plusDeviceIds.isNotEmpty) {
      engine.setProtocolPlusDevices(plusDeviceIds);
      if (durationsByDevice.isNotEmpty) {
        engine.setDeviceTotalDurations(durationsByDevice);
      }
      if (plusSequenceByDevice.isNotEmpty) {
        engine.setProtocolPlusSequencesByDevice(
          plusNameByDevice,
          plusSequenceByDevice,
          delayByDevice: plusDelayByDevice,
          durationsByDevice: plusDurationsByDevice,
        );
      }
    }
    engine.applySessionClockOffsetFromWallAnchor(DateTime.now());

    final sid = sessionId;

    // Register the run with the BACKEND *before* starting the device — and AWAIT
    // it. The backend locks/deducts tokens on /sessions/start (and
    // /protocol-plus/start), so an insufficient-tokens / no-subscription
    // rejection must BLOCK the run (web parity). A token rejection throws
    // [InsufficientTokensException], caught below: the engine never starts and
    // any already-registered side is rolled back. (Transient network failures
    // stay tolerant — they return null/fewer bindings, so an affordable run
    // still proceeds offline.)
    final normalSelections =
        selections.where((s) => !s.protocol.isProtocolPlus).toList();

    if (plusPlans.isNotEmpty) {
      final bindings = await controller.registerAndPublishBindings(
        sessionId: sid,
        plans: plusPlans,
        transport: transport,
        clientId: clientId,
      );
      // Flag these backend sessions as owned by this phone so the live feed
      // treats them as controllable own-runs (not foreign), and map each back
      // to the local engine for safe re-open from the History live tab.
      final live = ref.read(liveSessionsProvider.notifier);
      final mapNotifier = ref.read(ownBackendToLocalSessionProvider.notifier);
      for (final b in bindings) {
        live.markOwned(b.serverSessionId);
        mapNotifier.update((m) => {...m, b.serverSessionId: sid});
      }
    }

    // Create a BACKEND session for the NORMAL (non-Plus) device subset so the
    // run shows up in the org-wide live-session feed (parity with the web app)
    // and so the backend locks tokens. The backend sessionId is published to
    // [normalServerSessionIdProvider] so the live session screen can drive
    // pause/resume/stop (and so the terminal stop reliably deducts tokens).
    if (normalSelections.isNotEmpty) {
      final specs = normalSelections
          .map((s) => NormalDeviceSpec(
                localMac: s.deviceId,
                protocolId: s.protocol.id,
                protocolName: s.protocol.templateName,
                advancedSettings: s.advanced.toJson(),
                totalDurationSeconds: s.protocol.totalDurationSeconds,
              ))
          .toList();
      final backendId = await ref
          .read(sessionSyncServiceProvider)
          .startServerSession(
            devices: specs,
            transport: transport,
            clientId: clientId,
          );
      if (backendId != null) {
        ref.read(normalServerSessionIdProvider(sid).notifier).state = backendId;
        ref.read(liveSessionsProvider.notifier).markOwned(backendId);
        ref.read(ownBackendToLocalSessionProvider.notifier).update(
              (m) => {...m, backendId: sid},
            );
      }
    }

    // Backend accepted the run (tokens are locked) — NOW start the device.
    await engine.start();

    // Open the session screen. The devices are running and the backend bindings
    // are already published, so the screen wires its socket immediately.
    if (!context.mounted) return;
    context.push(
      RoutePaths.session,
      extra: {
        'sessionId': sid,
        'protocolId': commonProtocol.id,
        'protocol': commonProtocol,
        'deviceIds': deviceIds,
        'transport': transport,
        'advancedSettings': commonAdvanced,
        'advancedSettingsByDevice': advancedByDevice,
        'protocolByDeviceId': {
          for (final id in deviceIds) id: protocolByDevice[id]!.id,
        },
        'delayedDeviceId': effectiveDelayedDeviceId,
        'skipEngineBootstrap': true,
        // Bindings are resolved up front now — hand them straight to the screen
        // (it prefers this over the provider) so the socket wires on first frame.
        if (plusPlans.isNotEmpty)
          'protocolPlusBindings': ref.read(protocolPlusBindingsProvider(sid)),
      },
    );
  } catch (e) {
    if (sessionId != null) {
      ref.read(sessionEngineFamilyProvider(sessionId).notifier).reset();
      // Stop any backend session that DID register before the failure, so no
      // phantom RUNNING session / stuck token lock lingers (mixed normal+Plus
      // and multi-device Plus runs can register one side before another 400s).
      await _rollbackPartialRegistration(ref, sessionId);
    }
    if (e is InsufficientTokensException) {
      appLogger.e('Session launch blocked — ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }
    if (e is DioException) {
      appLogger.e(
        'Session launch failed → ${e.requestOptions.method} '
        '${e.requestOptions.uri} (status=${e.response?.statusCode})\n'
        'REQUEST BODY: ${e.requestOptions.data}\n'
        'RESPONSE BODY: ${e.response?.data}',
      );
    } else {
      appLogger.e('Session launch failed: $e');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e')),
      );
    }
  }
}

/// Stop any backend session that registered for [localSessionId] before a launch
/// failure, so a phantom RUNNING session / stuck token lock doesn't linger.
///
/// Reads the published Plus bindings and the normal backend sessionId for this
/// local session and best-effort stops each via `/sessions/:id/stop/:org`
/// (`stopAll`), which also releases the backend's token lock. Never throws.
Future<void> _rollbackPartialRegistration(
  WidgetRef ref,
  String localSessionId,
) async {
  final sync = ref.read(sessionSyncServiceProvider);
  final plusBindings = ref.read(protocolPlusBindingsProvider(localSessionId));
  for (final b in plusBindings) {
    if (b.serverSessionId.isNotEmpty) {
      await sync.stopServerSession(b.serverSessionId);
    }
  }
  final normalId = ref.read(normalServerSessionIdProvider(localSessionId));
  if (normalId != null && normalId.isNotEmpty) {
    await sync.stopServerSession(normalId);
  }
}
