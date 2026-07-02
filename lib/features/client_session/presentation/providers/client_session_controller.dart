import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/providers/client_auth_provider.dart';
import '../../../ble/data/ble_command_service.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/services/ble_connector.dart';
import '../../../protocols/data/protocol_remote_source.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../session/services/session_engine.dart';

/// A bare Dio for client-scoped Node calls. It attaches the client's own token
/// (held in [clientAuthProvider], NOT the shared secure storage) and has NO
/// auth interceptor — so a 401 here can never trigger the practitioner refresh/
/// clear-token flow that would log the client out.
Dio _clientDio(Ref ref) {
  final token = ref.read(clientAuthProvider).session?.accessToken ?? '';
  return Dio(BaseOptions(
    baseUrl: ApiEndpoints.nodeBaseUrl,
    connectTimeout: AppConstants.connectTimeout,
    receiveTimeout: AppConstants.receiveTimeout,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
  ));
}

/// Which stage of the at-home flow the client is in (web parity: `Phase`).
enum ClientPhase { select, running, paused }

/// Runnable protocols for the at-home client (web parity: `getProtocolsOnly`
/// filtered to non-Plus templates that carry cycles). Uses the client's own
/// token via [protocolRemoteSourceProvider] — org comes from the JWT, so this
/// works without a practitioner org selection.
final clientSessionProtocolsProvider =
    FutureProvider.autoDispose<List<Protocol>>((ref) async {
  final list = await ProtocolRemoteSource(_clientDio(ref)).getProtocols(
        page: 1,
        perPage: 100,
      );
  return list
      .where((p) => !p.isProtocolPlus && p.cycles.isNotEmpty && p.active)
      .toList();
});

/// Body parts to treat (web parity: `getBodyParts` → `partName`). Fetched with
/// the client token; returns the active part names only.
final clientSessionBodyPartsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final res = await _clientDio(ref).get(ApiEndpoints.bodyParts);
  final data = res.data;
  final list = data is List
      ? data
      : (data is Map && data['data'] is List)
          ? data['data'] as List
          : const [];
  return list
      .whereType<Map>()
      .where((m) => m['isActive'] != false)
      .map((m) => (m['partName'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toList();
});

class ClientSessionState {
  final ClientPhase phase;
  final bool connecting;
  final bool deviceReady;
  final bool starting;
  final String connectedMac; // firmware MAC (display + payload target)
  final String? deviceId; // BLE remoteId used for writes
  final int totalDurationSeconds;
  final String? error;

  const ClientSessionState({
    this.phase = ClientPhase.select,
    this.connecting = false,
    this.deviceReady = false,
    this.starting = false,
    this.connectedMac = '',
    this.deviceId,
    this.totalDurationSeconds = 0,
    this.error,
  });

  bool get isLive =>
      phase == ClientPhase.running || phase == ClientPhase.paused;

  ClientSessionState copyWith({
    ClientPhase? phase,
    bool? connecting,
    bool? deviceReady,
    bool? starting,
    String? connectedMac,
    String? deviceId,
    int? totalDurationSeconds,
    String? error,
  }) {
    return ClientSessionState(
      phase: phase ?? this.phase,
      connecting: connecting ?? this.connecting,
      deviceReady: deviceReady ?? this.deviceReady,
      starting: starting ?? this.starting,
      connectedMac: connectedMac ?? this.connectedMac,
      deviceId: deviceId ?? this.deviceId,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      error: error,
    );
  }
}

final clientSessionControllerProvider =
    StateNotifierProvider<ClientSessionController, ClientSessionState>((ref) {
  return ClientSessionController(ref);
});

/// Drives the at-home client session: connect to the client's own device,
/// run one protocol directly over BLE, and pause/resume/stop it. Mirrors the
/// web `useBleSession` flow (write payload → play 0x01 → pause 0x02 / resume
/// 0x04 / stop 0x03). No backend session is created (web parity).
class ClientSessionController extends StateNotifier<ClientSessionState> {
  final Ref _ref;

  ClientSessionController(this._ref) : super(const ClientSessionState());

  static const int _playByte = 0x01;
  static const int _pauseByte = 0x02;
  static const int _resumeByte = 0x04;
  static const int _stopByte = 0x03;

  BleRepository get _ble => _ref.read(bleRepositoryProvider);
  BleCommandService get _commands => _ref.read(bleCommandServiceProvider);
  BleConnector get _connector => _ref.read(bleConnectorProvider);

  /// Connect to [device], resolve its firmware MAC, and (if [expectedMac] is
  /// set) enforce it's the client's own registered device — tolerating the
  /// Hydra BLE MAC ±1 quirk. On success the device is ready to run.
  Future<bool> connect(BluetoothDevice device, {String? expectedMac}) async {
    state = state.copyWith(connecting: true, deviceReady: false, error: null);
    try {
      final ok = await _ble.connectDevice(device, cachePairedDevice: false);
      if (!ok) {
        state = state.copyWith(
            connecting: false, error: 'Could not connect to the device.');
        return false;
      }

      final mac = await _commands.resolveHardwareMac(device.remoteId.str);
      if (mac == null) {
        state = state.copyWith(
          connecting: false,
          error: "Connected, but couldn't read the device. Please reconnect.",
        );
        return false;
      }

      if (expectedMac != null &&
          expectedMac.trim().isNotEmpty &&
          !_macsEquivalent(mac, expectedMac.trim())) {
        state = state.copyWith(
          connecting: false,
          error: 'This is not your registered device (${mac.toUpperCase()}). '
              'Please connect to your own device '
              '(${expectedMac.toUpperCase()}).',
        );
        return false;
      }

      state = state.copyWith(
        connecting: false,
        deviceReady: true,
        connectedMac: mac.toUpperCase(),
        deviceId: device.remoteId.str,
      );
      return true;
    } catch (e) {
      state = state.copyWith(connecting: false, error: _describe(e));
      return false;
    }
  }

  /// Start [protocol] on the connected device: write the firmware payload, wait
  /// for the device to settle, then send PLAY. No backend session.
  Future<void> start(Protocol protocol) async {
    final id = state.deviceId;
    if (id == null || !state.deviceReady) {
      state = state.copyWith(error: 'Connect your device first.');
      return;
    }
    state = state.copyWith(starting: true, error: null);
    try {
      final engine =
          _ref.read(sessionEngineFamilyProvider('client-home').notifier);
      final payload = engine.buildFirmwarePayload(
        protocol,
        mac: state.connectedMac,
      );

      final wrote = await _connector.writeJsonToDevice(
        id,
        utf8.encode(jsonEncode(payload)),
      );
      if (!wrote) {
        state = state.copyWith(
            starting: false,
            error: 'Failed to send the protocol to the device.');
        return;
      }

      // Let the firmware apply the config before the play command (matches the
      // engine's 2.5s settle window).
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await _connector.writeToDevice(id, const [_playByte]);

      state = state.copyWith(
        phase: ClientPhase.running,
        starting: false,
        totalDurationSeconds: protocol.totalDurationSeconds,
      );
    } catch (e) {
      state = state.copyWith(starting: false, error: _describe(e));
    }
  }

  Future<void> pause() async {
    final id = state.deviceId;
    if (id == null) return;
    try {
      await _connector.writeToDevice(id, const [_pauseByte]);
      state = state.copyWith(phase: ClientPhase.paused);
    } catch (e) {
      state = state.copyWith(error: _describe(e));
    }
  }

  Future<void> resume() async {
    final id = state.deviceId;
    if (id == null) return;
    try {
      await _connector.writeToDevice(id, const [_resumeByte]);
      state = state.copyWith(phase: ClientPhase.running);
    } catch (e) {
      state = state.copyWith(error: _describe(e));
    }
  }

  /// Stop the run and return to the selection stage (web parity:
  /// `resetForAnother`). Even if the stop write fails, we return to select.
  Future<void> stop() async {
    final id = state.deviceId;
    if (id != null) {
      try {
        await _connector.writeToDevice(id, const [_stopByte]);
      } catch (_) {
        // Return to select regardless.
      }
    }
    state = state.copyWith(
      phase: ClientPhase.select,
      totalDurationSeconds: 0,
      error: null,
    );
  }

  void clearError() => state = state.copyWith(error: null);

  /// Same-unit check tolerant of the Hydra BLE-vs-firmware MAC ±1 offset.
  bool _macsEquivalent(String a, String b) {
    final na = a.toUpperCase().replaceAll('-', ':');
    final nb = b.toUpperCase().replaceAll('-', ':');
    if (na == nb) return true;
    final pa = na.split(':');
    final pb = nb.split(':');
    if (pa.length != 6 || pb.length != 6) return false;
    for (var i = 0; i < 5; i++) {
      if (pa[i] != pb[i]) return false;
    }
    final la = int.tryParse(pa[5], radix: 16);
    final lb = int.tryParse(pb[5], radix: 16);
    if (la == null || lb == null) return false;
    return (la - lb).abs() <= 1;
  }

  String _describe(Object e) {
    final msg = e.toString();
    return msg.startsWith('Exception: ') ? msg.substring(11) : msg;
  }
}
