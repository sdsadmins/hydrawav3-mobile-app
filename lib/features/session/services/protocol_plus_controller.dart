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
import '../../ble/services/ble_connector.dart';
import '../../protocols/domain/protocol_model.dart';
import '../../protocols/domain/protocol_plus_model.dart';
import '../../protocols/presentation/providers/protocol_provider.dart';
import '../domain/session_model.dart';
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
      appLogger.w('ProtocolPlus: no organizationId — cannot sync session state');
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
        appLogger.i('ProtocolPlus: ⇐ POST pause payload:\n${_pretty(res.data)}');
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
    );
  }

  /// Open ONE `/sessions` socket and route each server `START_PROTOCOL` to the
  /// matching device in [bindings]. Supports multiple devices, each with its
  /// own server session and (possibly different) Protocol Plus template.
  Future<void> connectAll({
    required List<ProtocolPlusBinding> bindings,
    required SessionEngine engine,
  }) async {
    // Tear down any previous connection before opening a new one.
    dispose();

    _bindings
      ..clear()
      ..addAll(bindings.where((b) => b.serverSessionId.isNotEmpty));
    if (_bindings.isEmpty) {
      appLogger.w('ProtocolPlus: connectAll called with no valid bindings');
      return;
    }

    final token = await _ref.read(secureStorageProvider).getAccessToken();

    // nodeBaseUrl is e.g. `https://host/hydrawav/v1/` → socket lives at host root.
    final wsBase = ApiEndpoints.nodeBaseUrl
        .replaceAll('/hydrawav/v1/', '')
        .replaceAll(RegExp(r'/$'), '');

    appLogger.i('ProtocolPlus: connecting socket → $wsBase/sessions');

    final socket = io.io(
      '$wsBase/sessions',
      io.OptionBuilder()
          .setPath('/socket.io')
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

    socket.onConnect(
      (_) => appLogger.i('ProtocolPlus: ✅ socket connected (id=${socket.id})'),
    );
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

  void dispose() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _bindings.clear();
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
    final plusPlans =
        <({String deviceId, String plusId, AdvancedSettings advanced})>[];
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
          throw StateError(
              'protocol[0] (${first.templateName}) has no cycles');
        }
        final advanced = _advancedFromProtocol(first);
        protocolByDevice[sel.deviceId] = first;
        advancedByDevice[sel.deviceId] = advanced;
        plusDeviceIds.add(sel.deviceId);
        if (detail.totalDuration > 0) {
          durationsByDevice[sel.deviceId] = detail.totalDuration;
        }
        plusPlans.add((
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

    // Register each Protocol Plus device with the server + build socket bindings.
    // BLE devices register by their firmware-reported bluetoothId (captured over
    // BLE after connect), not the phone-local id; Wi-Fi uses the macAddress.
    final bindings = <ProtocolPlusBinding>[];
    for (final plan in plusPlans) {
      var serverDeviceId = plan.deviceId;
      if (transport == 'ble') {
        final fwId =
            ref.read(bleConnectorProvider).getFirmwareSessionId(plan.deviceId);
        if (fwId != null && fwId.isNotEmpty) {
          serverDeviceId = fwId;
        } else {
          appLogger.w(
            'ProtocolPlus: no firmware bluetoothId for ${plan.deviceId}; '
            'using local id',
          );
        }
      }
      try {
        final result = await controller.startProtocolPlus(
          protocolPlusId: plan.plusId,
          deviceName: plan.deviceId,
          macAddress: serverDeviceId,
          transport: transport,
          advancedSettings: plan.advanced.toJson(),
        );
        if (result.sessionId.isNotEmpty) {
          bindings.add(ProtocolPlusBinding(
            localMac: plan.deviceId,
            serverDeviceId: serverDeviceId,
            serverSessionId: result.sessionId,
            plusId: plan.plusId,
          ));
          appLogger.i(
            'ProtocolPlus: registered ${plan.deviceId} '
            '(serverSessionId=${result.sessionId}, count=${result.protocolCount})',
          );
        } else {
          appLogger.e(
            'ProtocolPlus: empty server sessionId for ${plan.deviceId}',
          );
        }
      } catch (e) {
        appLogger.e('ProtocolPlus: failed to register ${plan.deviceId}: $e');
      }
    }

    if (!context.mounted) return;
    context.push(
      RoutePaths.session,
      extra: {
        'sessionId': sessionId,
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
        if (bindings.isNotEmpty) 'protocolPlusId': bindings.first.plusId,
        if (bindings.isNotEmpty)
          'protocolPlusBindings': bindings.map((b) => b.toMap()).toList(),
      },
    );
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
