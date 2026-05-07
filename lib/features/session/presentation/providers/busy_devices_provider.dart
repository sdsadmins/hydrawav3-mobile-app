import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/domain/active_session_model.dart';

/// Provider that tracks all devices currently in use by active sessions
/// Note: For now, we'll keep the original simple approach to avoid import conflicts
/// TODO: Add actual connection checking once import issues are resolved
final busyDevicesProvider = Provider<Set<String>>((ref) {
  final activeSessions = ref.watch(activeSessionsProvider);

  final busyDevices = <String>{};

  for (final session in activeSessions) {
    // Only consider devices from running or paused sessions
    if (session.status == SessionStatus.running ||
        session.status == SessionStatus.paused) {
      busyDevices.addAll(session.deviceIds);
    }
  }

  return busyDevices;
});

/// Provider to check if a specific device is busy
final isDeviceBusyProvider = Provider.family<bool, String>((ref, deviceId) {
  final busyDevices = ref.watch(busyDevicesProvider);
  return busyDevices.contains(deviceId);
});

/// Provider to get devices that are in active sessions but potentially disconnected
/// This is a placeholder for future enhancement
final ghostBusyDevicesProvider = Provider<Set<String>>((ref) {
  // For now, return empty set
  // TODO: Implement actual connection checking
  return <String>{};
});
