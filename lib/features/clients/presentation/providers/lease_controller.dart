import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/data/ble_command_service.dart';
import '../../../ble/data/ble_repository.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';

/// Progress + error state for the device-lease flow (parity with the web
/// `leaseActivateStep` / `leaseDeactivateStep` / `leaseError` state in
/// `clientDetails.tsx`). One shared instance drives the lease card UI.
class LeaseFlowState {
  final bool busy;

  /// Human-readable progress line shown while [busy] (e.g. "Connecting to
  /// device…", "Loading lease to device…"). Null when idle.
  final String? step;

  /// Last error message, shown until the next action starts. Null when clear.
  final String? error;

  const LeaseFlowState({this.busy = false, this.step, this.error});

  LeaseFlowState copyWith({bool? busy, String? step, String? error}) {
    return LeaseFlowState(
      busy: busy ?? this.busy,
      step: step,
      error: error,
    );
  }
}

final leaseControllerProvider =
    StateNotifierProvider<LeaseController, LeaseFlowState>((ref) {
  return LeaseController(
    clients: ref.read(clientRepositoryProvider),
    ble: ref.read(bleRepositoryProvider),
    commands: ref.read(bleCommandServiceProvider),
  );
});

/// Orchestrates the full device-lease lifecycle by combining the Node client
/// API (`PATCH /clients/:id`) with the BLE lease commands. The three-way
/// handshake (server registers → device confirms → server activates) mirrors
/// the web app so the server flips `leaseActive` only after the firmware acks.
class LeaseController extends StateNotifier<LeaseFlowState> {
  final ClientRepository _clients;
  final BleRepository _ble;
  final BleCommandService _commands;

  LeaseController({
    required ClientRepository clients,
    required BleRepository ble,
    required BleCommandService commands,
  })  : _clients = clients,
        _ble = ble,
        _commands = commands,
        super(const LeaseFlowState());

  /// Step 1 — register the lease on the server (still inactive). The backend
  /// generates the `leaseId`; the device has not been touched yet, so the
  /// client lands in the "Pending" state until [loadLeaseToDevice] runs.
  Future<Client?> registerLease({
    required String clientId,
    required String macAddress,
    required String password,
  }) async {
    return _run('Registering lease…', () {
      return _clients.updateClient(clientId, {
        'leaseActive': false,
        'macAddress': macAddress.toUpperCase(),
        'password': password,
        'isActive': true,
      });
    });
  }

  /// Step 2 — connect to the device, write the lease ID over BLE, and (only
  /// after the firmware confirms) activate the lease on the server.
  Future<Client?> loadLeaseToDevice({
    required Client client,
    required BluetoothDevice device,
  }) async {
    final leaseId = client.leaseId;
    if (leaseId == null || leaseId.isEmpty) {
      state = state.copyWith(busy: false, error: 'No lease to load.');
      return null;
    }

    state = state.copyWith(busy: true, error: null, step: 'Connecting to device…');
    try {
      final connected = await _ble.connectDevice(device, cachePairedDevice: false);
      if (!connected) {
        state = state.copyWith(busy: false, error: 'Could not connect to the device.');
        return null;
      }

      state = state.copyWith(busy: true, step: 'Loading lease to device…');
      final acked = await _commands.setLeaseId(
        device.remoteId.str,
        leaseId,
        expectedMac: client.macAddress,
      );
      if (!acked) {
        state = state.copyWith(
          busy: false,
          error: 'Device did not confirm it accepted the lease ID.',
        );
        return null;
      }

      state = state.copyWith(busy: true, step: 'Activating lease…');
      final updated = await _clients.updateClient(client.id, {'leaseActive': true});
      state = const LeaseFlowState();
      return updated;
    } on LeaseCommandException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(busy: false, error: _describe(e));
      return null;
    }
  }

  /// Deactivate + return: clear the lease on the device, then hard-clear all
  /// lease fields on the server (which also closes the LeaseHistory row).
  Future<Client?> deactivateLease({
    required Client client,
    required BluetoothDevice device,
  }) async {
    final leaseId = client.leaseId ?? '';

    state = state.copyWith(busy: true, error: null, step: 'Connecting to device…');
    try {
      final connected = await _ble.connectDevice(device, cachePairedDevice: false);
      if (!connected) {
        state = state.copyWith(busy: false, error: 'Could not connect to the device.');
        return null;
      }

      state = state.copyWith(busy: true, step: 'Clearing lease on device…');
      final acked = await _commands.clearLeaseId(
        device.remoteId.str,
        leaseId,
        expectedMac: client.macAddress,
      );
      if (!acked) {
        state = state.copyWith(
          busy: false,
          error: 'Device did not confirm the lease was cleared.',
        );
        return null;
      }

      state = state.copyWith(busy: true, step: 'Deactivating lease…');
      final updated = await _clients.updateClient(client.id, {
        'leaseActive': false,
        'isActive': false,
      });
      state = const LeaseFlowState();
      return updated;
    } on LeaseCommandException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(busy: false, error: _describe(e));
      return null;
    }
  }

  /// Rotate the lease password (no device interaction; server hashes it).
  Future<Client?> resetPassword({
    required String clientId,
    required String password,
  }) async {
    return _run('Updating password…', () {
      return _clients.updateClient(clientId, {'password': password});
    });
  }

  /// Connect to [device] and read its firmware-reported MAC — the value to
  /// register against the client. This is the iOS-safe path: on iOS the BLE
  /// `remoteId` is an opaque UUID, so the MAC must come from the firmware notify
  /// frames (via `resolveHardwareMac`), which is the same value the web reads.
  /// Returns null (and sets an error) if it can't be resolved.
  Future<String?> readDeviceMac(BluetoothDevice device) async {
    state = state.copyWith(busy: true, error: null, step: 'Reading device…');
    try {
      final connected = await _ble.connectDevice(device, cachePairedDevice: false);
      if (!connected) {
        state = state.copyWith(busy: false, error: 'Could not connect to the device.');
        return null;
      }
      final mac = await _commands.resolveHardwareMac(device.remoteId.str);
      if (mac == null) {
        state = state.copyWith(
          busy: false,
          error: 'Could not read the device MAC. Reconnect and try again.',
        );
        return null;
      }
      state = const LeaseFlowState();
      return mac.toUpperCase();
    } catch (e) {
      state = state.copyWith(busy: false, error: _describe(e));
      return null;
    }
  }

  /// Reset any lingering error so the card returns to a clean state.
  void clearError() => state = const LeaseFlowState();

  Future<Client?> _run(String step, Future<Client> Function() action) async {
    state = state.copyWith(busy: true, error: null, step: step);
    try {
      final result = await action();
      state = const LeaseFlowState();
      return result;
    } catch (e) {
      state = state.copyWith(busy: false, error: _describe(e));
      return null;
    }
  }

  String _describe(Object e) {
    final msg = e.toString();
    return msg.startsWith('Exception: ') ? msg.substring(11) : msg;
  }
}
