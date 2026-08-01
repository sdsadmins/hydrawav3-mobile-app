import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/domain/active_session_model.dart';
import 'active_sessions_provider.dart';
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
///
/// Runs THIS phone has already finished are excluded: the engine POSTs the stop
/// the instant a run goes terminal, but the feed is a 1s poll, so without this a
/// device stayed greyed out as "In use" for a beat after its own session ended.
final busyDevicesProvider = Provider<Set<String>>((ref) {
  final liveSessions = ref.watch(liveSessionsProvider);
  final finished = ref.watch(finishedOwnSessionIdsProvider);

  final busyDevices = <String>{};
  for (final session in liveSessions) {
    if (finished.contains(session.id)) continue;
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

/// How many physical devices are running org-wide right now — the number the
/// plan's concurrent-device limit is measured against.
///
/// [busyDevicesProvider] must NOT be used for this. It deliberately expands
/// every MAC into its ±1 variants so a membership test matches whichever form
/// the caller holds, which means one running device contributes up to three
/// entries; counting it puts a 1-device run over a 2-device plan. It also keys
/// off the SESSION status, so a device stopped inside a still-running
/// multi-device session went on occupying a slot forever.
///
/// This counts one entry per physical device (±1 variants collapse onto the
/// device already counted, so the local advertised id and the backend's
/// firmware id never double-count), and honours the PER-DEVICE status so
/// stopping one device of a run frees its slot immediately.
final liveDeviceCountProvider = Provider<int>((ref) {
  final counted = <String>[];

  bool alreadyCounted(String norm) =>
      counted.any((seen) => _macVariants(seen).contains(norm));

  void add(String id) {
    final norm = id.trim().toUpperCase();
    if (norm.isEmpty || alreadyCounted(norm)) return;
    counted.add(norm);
  }

  bool isLive(SessionStatus s) =>
      s == SessionStatus.running || s == SessionStatus.paused;

  // The org-wide backend feed is the source of truth and already covers this
  // phone's own registered runs. Runs we've already finished don't occupy a
  // plan slot while the feed catches up.
  final finished = ref.watch(finishedOwnSessionIdsProvider);
  for (final session in ref.watch(liveSessionsProvider)) {
    if (finished.contains(session.id)) continue;
    if (!isLive(session.status)) continue;
    for (final id in session.deviceIds) {
      final status = session.deviceStatuses[id];
      // Unknown per-device status on a live session → treat as running; the
      // feed always reports one, so this only covers malformed frames.
      if (status == null || isLive(status)) add(id);
    }
  }

  // Local runs whose backend registration hasn't landed in the feed yet. The
  // ±1 collapse above keeps these from double-counting a device the feed
  // already reported under its firmware id.
  for (final session in ref.watch(activeSessionsProvider)) {
    if (!isLive(session.status)) continue;
    for (final entry in session.deviceStatuses.entries) {
      if (isLive(entry.value)) add(entry.key);
    }
  }

  return counted.length;
});

/// Placeholder for devices in active sessions that may be disconnected.
final ghostBusyDevicesProvider = Provider<Set<String>>((ref) {
  return <String>{};
});
