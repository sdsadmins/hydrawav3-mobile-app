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
  String? _sessionId;

  /// The LOCAL device id used to address the device for sends
  /// (BLE remoteId / Wi-Fi macAddress) — this is what [SessionEngine] /
  /// the BLE connector expect for `writeToDevice`.
  String? _macAddress;

  /// The id we REGISTERED with the server (firmware-reported bluetoothId for
  /// BLE, e.g. "24Qt…==", or macAddress for Wi-Fi). The server echoes this in
  /// `START_PROTOCOL`, so we match on it. It is NOT a valid BLE write target.
  String? _serverDeviceId;

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
    // Remember the id we register with the server (firmware bluetoothId for
    // BLE, macAddress for Wi-Fi) so we can match it back on START_PROTOCOL.
    _serverDeviceId = macAddress;
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
  /// endpoints. Returns null when the server session isn't known yet (i.e.
  /// [connect] hasn't run) so callers can no-op safely.
  Future<({String sessionId, String orgId, Options options})?>
      _sessionRequestContext() async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) return null;

    final storage = _ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();
    final userId = await storage.getUserId();
    final orgId = await storage.getSelectedOrgId();
    if (orgId == null || orgId.isEmpty) {
      appLogger.w('ProtocolPlus: no organizationId — cannot sync session state');
      return null;
    }

    return (
      sessionId: sessionId,
      orgId: orgId,
      options: Options(
        headers: {
          if (userId != null) 'x-user-id': userId,
          if (token != null) 'Authorization': token,
        },
      ),
    );
  }

  /// POST /sessions/:sessionId/pause/:organizationId — pause the server-side
  /// Protocol Plus session so it stays in sync with the device/app.
  Future<void> pauseServerSession() async {
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    try {
      final dio = _ref.read(nodeDioProvider);
      final res = await dio.post(
        ApiEndpoints.sessionPause(ctx.sessionId, ctx.orgId),
        data: {if (_macAddress != null) 'macAddress': _macAddress},
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

  /// POST /sessions/:sessionId/resume/:organizationId.
  Future<void> resumeServerSession() async {
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    try {
      final dio = _ref.read(nodeDioProvider);
      final res = await dio.post(
        ApiEndpoints.sessionResume(ctx.sessionId, ctx.orgId),
        data: {if (_macAddress != null) 'macAddress': _macAddress},
        options: ctx.options,
      );
      appLogger.i('ProtocolPlus: ⇐ POST resume payload:\n${_pretty(res.data)}');
    } on DioException catch (e) {
      appLogger.e(
        'ProtocolPlus: resume failed (status=${e.response?.statusCode}) '
        '${e.response?.data}',
      );
    } catch (e) {
      appLogger.e('ProtocolPlus: resume failed: $e');
    }
  }

  /// POST /sessions/:sessionId/stop/:organizationId with `stopAll` — ends the
  /// Protocol Plus session and cancels the server's remaining switch jobs.
  Future<void> stopServerSession() async {
    final ctx = await _sessionRequestContext();
    if (ctx == null) return;
    try {
      final dio = _ref.read(nodeDioProvider);
      final res = await dio.post(
        ApiEndpoints.sessionStop(ctx.sessionId, ctx.orgId),
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

  /// Open the `/sessions` socket and route each protocol switch to [engine].
  Future<void> connect({
    required String sessionId,
    required String macAddress,
    required SessionEngine engine,
  }) async {
    // Tear down any previous connection before opening a new one.
    dispose();

    _sessionId = sessionId;
    _macAddress = macAddress;

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

    // `START_PROTOCOL` is a GLOBAL broadcast from the server, so we filter to
    // our own session + device before acting.
    socket.on('START_PROTOCOL', (data) async {
      try {
        if (data is! Map) return;
        final evSession = data['sessionId']?.toString();
        final evMac = data['macAddress']?.toString();
        final evBt = data['bluetoothId']?.toString();

        if (evSession != _sessionId) return;
        // The device may be identified by macAddress (Wi-Fi) or bluetoothId
        // (BLE, the firmware-reported id we registered with the server).
        // Accept the switch when the event id matches EITHER the id we
        // registered with the server OR our local id.
        final localId = _macAddress;
        final serverId = _serverDeviceId;
        bool isOurs(String? v) =>
            v != null && v.isNotEmpty && (v == localId || v == serverId);
        final knowDevice = (localId != null && localId.isNotEmpty) ||
            (serverId != null && serverId.isNotEmpty);
        if (knowDevice && !isOurs(evMac) && !isOurs(evBt)) {
          return;
        }

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
          'protocol=${protocol.templateName}, cycles=${protocol.cycles.length})',
        );

        // Write to the device using our LOCAL id (BLE remoteId / Wi-Fi mac).
        // The event's `bluetoothId` is the firmware id, which is NOT what the
        // BLE connector uses to address the device — so we must not write to it.
        final targetId = _macAddress ??
            ((evMac != null && evMac.isNotEmpty) ? evMac : (evBt ?? ''));

        if (targetId.isEmpty) {
          appLogger.e(
            'ProtocolPlus: no local target device id for switch — skipped',
          );
          return;
        }

        await engine.applyProtocolPlusSwitch(
          targetId,
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
    _sessionId = null;
    _macAddress = null;
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

/// Shared entry point to start a Protocol Plus run for [plusId] on [deviceId].
/// Used by selecting a protocol-plus from the normal protocol list (auto-detect)
/// — no separate screen/button required. Runs protocol[0] locally, spans the
/// whole sequence duration, registers the server schedule, and navigates to the
/// live session (which opens the socket for the auto-switches).
Future<void> launchProtocolPlusSession(
  WidgetRef ref,
  BuildContext context, {
  required String plusId,
  required String deviceId,
  required String transport,
}) async {
  final controller = ref.read(protocolPlusControllerProvider);
  final transportEnum =
      transport == 'wifi' ? SessionTransport.wifi : SessionTransport.ble;
  String? sessionId;
  try {
    // Fetch the protocol-plus with its sub-protocols populated (full cycles).
    final detail = await controller.getProtocolPlusDetail(plusId);
    final orderedIds = detail.protocolIds;
    final populated = detail.protocols;
    final totalDurationSeconds = detail.totalDuration;
    appLogger.i(
      'ProtocolPlus: launch plusId=$plusId, protocolIds=$orderedIds, '
      'populated=${populated.length}, totalDuration=${totalDurationSeconds}s',
    );
    if (orderedIds.isEmpty && populated.isEmpty) {
      throw StateError('Protocol Plus has no protocols');
    }

    // protocol[0] full object (cycles). Prefer populated; never fetch plus id.
    Protocol firstProtocol;
    if (populated.isNotEmpty && populated.first.cycles.isNotEmpty) {
      firstProtocol = populated.first;
    } else {
      final fid = orderedIds.first;
      if (fid == plusId) {
        throw StateError('protocolIds[0] equals the plus id ($fid)');
      }
      firstProtocol = await ref.read(protocolDetailProvider(fid).future);
    }
    if (firstProtocol.cycles.isEmpty) {
      throw StateError(
          'protocol[0] (${firstProtocol.templateName}) has no cycles');
    }

    // Derive advanced settings from protocol[0]'s own fields instead of the
    // bare defaults. The default constructor forces cycle1Initiation /
    // cycle5Completion ON, which makes the firmware run a ~9s hot initiation
    // edge cycle before the real protocol. Web parity: cycle1/cycle5 (and the
    // vibration sweep range) come from the protocol, not a hard-coded default.
    final advanced = AdvancedSettings(
      cycle1Initiation: firstProtocol.cycle1,
      cycle5Completion: firstProtocol.cycle5,
      vibrationSweepMin: firstProtocol.vibmin,
      vibrationSweepMax: firstProtocol.vibmax,
      vibMin: firstProtocol.vibmin,
      vibMax: firstProtocol.vibmax,
      hotDrop: firstProtocol.hotdrop,
      coldDrop: firstProtocol.colddrop,
    );
    sessionId = const Uuid().v4();
    final engine = ref.read(sessionEngineFamilyProvider(sessionId).notifier);

    engine.prepareSession(deviceIds: [deviceId], transport: transportEnum);
    engine.loadSession(
      firstProtocol,
      [deviceId],
      transport: transportEnum,
      advancedSettings: advanced,
      advancedSettingsByDevice: {deviceId: advanced},
      protocolByDevice: {deviceId: firstProtocol},
      wifiConfigAlreadyPublished: false,
    );
    if (totalDurationSeconds > 0) {
      engine.setSessionTotalDuration(totalDurationSeconds);
    }
    // Sequence tracker: plus title + ordered sub-protocol names.
    engine.setProtocolPlusSequence(
      detail.templateName,
      _protocolPlusSequenceNames(populated, orderedIds),
    );
    engine.applySessionClockOffsetFromWallAnchor(DateTime.now());
    await engine.start();

    // BLE devices are identified to the server by their firmware-reported
    // bluetoothId (e.g. "24Qt…=="), captured over BLE after connect — not the
    // phone-local remoteId/MAC. Wi-Fi uses the macAddress directly.
    String serverDeviceId = deviceId;
    if (transport == 'ble') {
      final fwId =
          ref.read(bleConnectorProvider).getFirmwareSessionId(deviceId);
      if (fwId == null || fwId.isEmpty) {
        appLogger.w(
          'ProtocolPlus: no firmware bluetoothId captured for $deviceId yet; '
          'falling back to local id',
        );
      } else {
        serverDeviceId = fwId;
      }
    }

    final result = await controller.startProtocolPlus(
      protocolPlusId: plusId,
      deviceName: deviceId,
      macAddress: serverDeviceId,
      transport: transport,
      advancedSettings: advanced.toJson(),
    );
    appLogger.i(
      'ProtocolPlus: launched "${detail.templateName}" '
      '(serverSessionId=${result.sessionId}, count=${result.protocolCount})',
    );

    if (!context.mounted) return;
    context.push(
      RoutePaths.session,
      extra: {
        'sessionId': sessionId,
        'protocolId': firstProtocol.id,
        'protocol': firstProtocol,
        'deviceIds': [deviceId],
        'transport': transport,
        'advancedSettings': advanced,
        'advancedSettingsByDevice': {deviceId: advanced},
        'protocolByDeviceId': {deviceId: firstProtocol.id},
        'skipEngineBootstrap': true,
        'protocolPlusId': plusId,
        'protocolPlusServerSessionId': result.sessionId,
        'protocolPlusMac': deviceId,
      },
    );
  } catch (e) {
    if (sessionId != null) {
      ref.read(sessionEngineFamilyProvider(sessionId).notifier).reset();
    }
    if (e is DioException) {
      appLogger.e(
        'ProtocolPlus: launch failed → ${e.requestOptions.method} '
        '${e.requestOptions.uri} (status=${e.response?.statusCode})\n'
        'REQUEST BODY: ${e.requestOptions.data}\n'
        'RESPONSE BODY: ${e.response?.data}',
      );
    } else {
      appLogger.e('ProtocolPlus: launch failed: $e');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start Protocol Plus: $e')),
      );
    }
  }
}
