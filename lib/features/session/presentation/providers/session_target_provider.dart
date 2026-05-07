import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session_model.dart';
import '../../../ble/presentation/providers/ble_scan_provider.dart'; // Fixed import path
import '../../../ble/data/ble_repository.dart'; // Added missing import

class SessionTargetState {
  final SessionTransport transport;
  final List<String> deviceIds; // mac addresses for wifi / ble remoteId for ble

  const SessionTargetState({
    this.transport = SessionTransport.ble,
    this.deviceIds = const <String>[],
  });

  SessionTargetState copyWith({
    SessionTransport? transport,
    List<String>? deviceIds,
  }) {
    return SessionTargetState(
      transport: transport ?? this.transport,
      deviceIds: deviceIds ?? this.deviceIds,
    );
  }

  /// Filter device IDs based on current transport type
  List<String> get filteredDeviceIds {
    // For now, return all device IDs to allow cross-transport selection
    // This preserves user selection when switching between BLE and WiFi
    return deviceIds;
  }
}

class SessionTargetNotifier extends StateNotifier<SessionTargetState> {
  SessionTargetNotifier() : super(const SessionTargetState());

  void setTransport(SessionTransport t, WidgetRef ref) {
    // Keep the same device IDs when transport changes
    // This allows users to toggle between BLE and WiFi without losing selection
    // Also stop any ongoing auto-scanning when switching transport
    final scanner = ref.read(bleScanResultsProvider);
    final bleRepo = ref.read(bleRepositoryProvider);
    if (scanner != null && bleRepo.isScanning) {
      // Use the correct stopScan method from bleRepository
      bleRepo.stopScan();
    }

    state = state.copyWith(transport: t);
  }

  void setSelected(List<String> deviceIds) {
    state = state.copyWith(deviceIds: List<String>.from(deviceIds));
  }

  void toggleDevice(String deviceId) {
    final current = List<String>.from(state.deviceIds);
    final isAlreadySelected = current.contains(deviceId);
    state = state.copyWith(
      deviceIds: isAlreadySelected
          ? (current..remove(deviceId))
          : (current..add(deviceId)),
    );
  }

  void ensureSelected(String deviceId) {
    if (state.deviceIds.contains(deviceId)) return;
    state = state.copyWith(deviceIds: [...state.deviceIds, deviceId]);
  }

  void ensureDeselected(String deviceId) {
    if (!state.deviceIds.contains(deviceId)) return;
    final updated = List<String>.from(state.deviceIds)..remove(deviceId);
    state = state.copyWith(deviceIds: updated);
  }

  void clear() => state = state.copyWith(deviceIds: const <String>[]);
}

final sessionTargetProvider =
    StateNotifierProvider<SessionTargetNotifier, SessionTargetState>((ref) {
  return SessionTargetNotifier();
});
