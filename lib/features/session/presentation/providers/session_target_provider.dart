import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session_model.dart';

class SessionTargetState {
  final SessionTransport transport;
  final List<String> deviceIds; // mac addresses for wifi / ble remoteId for ble

  const SessionTargetState({
    this.transport = SessionTransport.wifi,
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
}

class SessionTargetNotifier extends StateNotifier<SessionTargetState> {
  SessionTargetNotifier() : super(const SessionTargetState());

  void setTransport(SessionTransport t) {
    // Clear previously selected devices when transport changes
    // since WiFi device IDs are incompatible with BLE and vice versa
    state = SessionTargetState(
      transport: t,
      deviceIds: const <String>[],
    );
  }

  void setSelected(List<String> deviceIds) {
    state = state.copyWith(deviceIds: deviceIds);
  }

  void toggleDevice(String deviceId) {
    final set = state.deviceIds.toSet();
    if (set.contains(deviceId)) {
      set.remove(deviceId);
    } else {
      set.add(deviceId);
    }
    state = state.copyWith(deviceIds: set.toList());
  }

  void clear() => state = state.copyWith(deviceIds: const <String>[]);
}

final sessionTargetProvider =
    StateNotifierProvider<SessionTargetNotifier, SessionTargetState>((ref) {
  return SessionTargetNotifier();
});
