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
import '../../ble/domain/ble_device_model.dart';
import '../../ble/services/ble_connector.dart';
import '../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../protocols/domain/protocol_model.dart';
import '../../protocols/domain/protocol_plus_model.dart';
import '../../protocols/presentation/providers/protocol_provider.dart';
import '../domain/session_model.dart';
import '../presentation/providers/active_sessions_provider.dart';
import 'background_session_runtime.dart';
import 'session_engine.dart';

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

  /// Watches per-device BLE connection so a held switch can be applied the
  /// moment the device reconnects.
  StreamSubscription<Map<String, BleConnectionStatus>>? _connStatesSub;
  Map<String, BleConnectionStatus> _lastConnStates = {};

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
    final res = await dio.post(
      ApiEndpoints.protocolPlusStart,
      data: {
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
      },
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
  }) async {
    if (plans.isEmpty) return const [];

    // Resolve registered (display) names once for all devices — best-effort.
    final nameByDevice =
        await _resolveRegisteredNames(plans.map((p) => p.deviceId).toList());

    final results = await Future.wait(plans.map((plan) async {
      // BLE registers by the firmware-reported bluetoothId (captured over BLE
      // after connect), not the phone-local id; Wi-Fi uses the macAddress.
      var serverDeviceId = plan.deviceId;
      if (transport == 'ble') {
        final fwId =
            _ref.read(bleConnectorProvider).getFirmwareSessionId(plan.deviceId);
        if (fwId != null && fwId.isNotEmpty) {
          serverDeviceId = fwId;
        } else {
          appLogger.w(
            'ProtocolPlus: no firmware bluetoothId for ${plan.deviceId}; '
            'using local id',
          );
        }
      }
      final deviceName =
          nameByDevice[plan.deviceId.trim().toUpperCase()] ?? plan.deviceId;
      try {
        final result = await startProtocolPlus(
          protocolPlusId: plan.plusId,
          deviceName: deviceName,
          macAddress: serverDeviceId,
          transport: transport,
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
      } catch (e) {
        appLogger.e('ProtocolPlus: failed to register ${plan.deviceId}: $e');
        return null;
      }
    }));

    final bindings = results.whereType<ProtocolPlusBinding>().toList();
    // Publish — the session screen is (or will be) watching this key. Setting
    // the value is safe whether the screen subscribed before or after us.
    _ref.read(protocolPlusBindingsProvider(sessionId).notifier).state = bindings;
    appLogger.i(
      'ProtocolPlus: published ${bindings.length} binding(s) for session '
      '$sessionId',
    );
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
      appLogger.w('ProtocolPlus: could not resolve device names: $e');
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

    // Apply any protocol switch that was held while a device was disconnected,
    // the moment that device reconnects (BLE). Survives screen changes.
    _connStatesSub?.cancel();
    _lastConnStates = {};
    _connStatesSub = _ref
        .read(bleConnectorProvider)
        .connectionStates
        .listen(_applyPendingSwitchesOn);

    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    _organizationId = await storage.getSelectedOrgId();

    // Detect run completion app-scoped (not tied to the screen): when the engine
    // reaches a terminal state, end the run everywhere — even if no SessionScreen
    // is mounted. This is what frees the device after an off-screen Plus finish.
    // fireImmediately:true also covers the race where the run already ended
    // before registration produced these bindings (engine already terminal).
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
    // nodeBaseUrl is like `https://host[/<proxyPrefix>]/hydrawav/v1/`.
    //   • The Nest server uses global prefix `hydrawav/v1` and serves socket.io
    //     at the default path `/socket.io`, gateway namespace `/sessions`.
    //   • Any path segment BEFORE `hydrawav/v1` (e.g. `/api`) is a reverse-proxy
    //     prefix that also fronts socket.io, so the external socket path is
    //     `<proxyPrefix>/socket.io`. Unlike the browser web app (which can use a
    //     relative URL resolved against window.origin), Flutter must dial an
    //     absolute origin — a bare `/sessions` has no host and just times out.
    final restUri = Uri.parse(ApiEndpoints.nodeBaseUrl);
    final origin = '${restUri.scheme}://${restUri.host}'
        '${restUri.hasPort ? ':${restUri.port}' : ''}';
    final proxyPrefix = restUri.path
        .split('hydrawav/v1')
        .first
        .replaceAll(RegExp(r'/+$'), ''); // e.g. `/api` or ``
    final socketUrl = '$origin/sessions';
    final socketPath = '$proxyPrefix/socket.io';

    appLogger.i(
      'ProtocolPlus: connecting socket → $socketUrl (path=$socketPath)',
    );

    final socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setPath(socketPath)
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          // ngrok free tier injects a browser-warning page that breaks the
          // socket.io handshake unless this header is present.
          .setExtraHeaders({'ngrok-skip-browser-warning': 'true'})
          .disableAutoConnect()
          .enableForceNew()
          .build(),
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
          appLogger.w(
            'ProtocolPlus: ${binding.localMac} not connected — holding switch '
            'index=$index until reconnect',
          );
          return;
        }

        // Write to the device using our LOCAL id (BLE remoteId / Wi-Fi mac).
        // The event's `bluetoothId` is the firmware id, which is NOT what the
        // BLE connector uses to address the device — so we must not write to it.
        await engine.applyProtocolPlusSwitch(
          binding.localMac,
          protocol,
          index,
        );
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
        if (type != 'SESSION_STOPPED') return;
        final evSession = data['sessionId']?.toString();
        if (evSession == null || evSession.isEmpty) return;
        final matches = _bindings.any((b) => b.serverSessionId == evSession);
        if (!matches) return;
        appLogger.i('ProtocolPlus: ⇐ SESSION_STOPPED for $evSession — ending run');
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

    if (stopServer) {
      try {
        await stopServerSession();
      } catch (e) {
        appLogger.e('ProtocolPlus: stopServerSession during finish failed: $e');
      }
    }

    if (localId != null && localId.isNotEmpty) {
      try {
        await _ref
            .read(activeSessionsProvider.notifier)
            .removeSession(localId);
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
      final pending = _pendingSwitches.remove(b.localMac);
      if (pending == null) continue;
      appLogger.i(
        'ProtocolPlus: ${b.localMac} reconnected — applying held switch '
        'index=${pending.index}',
      );
      unawaited(
        engine.applyProtocolPlusSwitch(
          b.localMac,
          pending.protocol,
          pending.index,
        ),
      );
    }
    _lastConnStates = Map.of(states);
  }

  void dispose() {
    _removeEngineListener?.call();
    _removeEngineListener = null;
    _connStatesSub?.cancel();
    _connStatesSub = null;
    _pendingSwitches.clear();
    _lastConnStates = {};
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
      } else {
        protocolByDevice[sel.deviceId] = sel.protocol;
        advancedByDevice[sel.deviceId] = sel.advanced;
      }
    }

    sessionId = const Uuid().v4();
    final engine = ref.read(sessionEngineFamilyProvider(sessionId).notifier);
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
    if (plusDeviceIds.isNotEmpty) {
      engine.setProtocolPlusDevices(plusDeviceIds);
      if (durationsByDevice.isNotEmpty) {
        engine.setDeviceTotalDurations(durationsByDevice);
      }
      if (plusSequenceByDevice.isNotEmpty) {
        engine.setProtocolPlusSequencesByDevice(
          plusNameByDevice,
          plusSequenceByDevice,
        );
      }
    }
    engine.applySessionClockOffsetFromWallAnchor(DateTime.now());
    await engine.start();

    // Open the session screen IMMEDIATELY — before any server registration.
    // The devices are already running after engine.start(); waiting on the
    // (network) Protocol Plus registration here used to leave them running with
    // no UI, so impatient users navigated away and the run was recorded
    // nowhere. Registration now runs in the BACKGROUND below and delivers the
    // socket bindings to the screen via [protocolPlusBindingsProvider].
    final sid = sessionId;
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
        // Tell the screen a Plus run is registering — it watches the bindings
        // provider and wires its socket the moment they arrive.
        if (plusPlans.isNotEmpty) ...{
          'protocolPlusPending': true,
          'protocolPlusId': plusPlans.first.plusId,
        },
      },
    );

    // Register the Plus device(s) with the server in the background; the
    // session screen connects its socket when the bindings are published.
    if (plusPlans.isNotEmpty) {
      unawaited(controller.registerAndPublishBindings(
        sessionId: sid,
        plans: plusPlans,
        transport: transport,
      ));
    }
  } catch (e) {
    if (sessionId != null) {
      ref.read(sessionEngineFamilyProvider(sessionId).notifier).reset();
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
