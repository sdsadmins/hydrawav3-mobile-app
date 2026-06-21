import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/domain/active_session_model.dart';
import 'live_sessions_provider.dart';

/// Normalized MAC plus its ±1 last-byte variants. BLE units advertise on a MAC
/// ±1 from the registered hardware MAC, and the backend stores the firmware id
/// while local device selection uses the advertised id — so a device is "busy"
/// if any of these variants is in use.
Iterable<String> _macVariants(String mac) {
  final norm = mac.trim().toUpperCase();
  final variants = <String>{norm};
  final parts = norm.split(':');
  if (parts.length == 6) {
    final last = int.tryParse(parts.last, radix: 16);
    if (last != null) {
      for (final delta in const [1, -1]) {
        final copy = [...parts];
        copy[5] = ((last + delta) & 0xFF)
            .toRadixString(16)
            .padLeft(2, '0')
            .toUpperCase();
        variants.add(copy.join(':'));
      }
    }
  }
  return variants;
}

/// Devices currently in use by any RUNNING/PAUSED session in the org-wide live
/// feed (the backend is the source of truth — mirrors the web's busy logic).
final busyDevicesProvider = Provider<Set<String>>((ref) {
  final liveSessions = ref.watch(liveSessionsProvider);

  final busyDevices = <String>{};
  for (final session in liveSessions) {
    if (session.status == SessionStatus.running ||
        session.status == SessionStatus.paused) {
      for (final id in session.deviceIds) {
        busyDevices.addAll(_macVariants(id));
      }
    }
  }
  return busyDevices;
});

/// Whether a specific device (by local id) is busy in any live session.
final isDeviceBusyProvider = Provider.family<bool, String>((ref, deviceId) {
  final busyDevices = ref.watch(busyDevicesProvider);
  return _macVariants(deviceId).any(busyDevices.contains);
});

/// Placeholder for devices in active sessions that may be disconnected.
final ghostBusyDevicesProvider = Provider<Set<String>>((ref) {
  return <String>{};
});
