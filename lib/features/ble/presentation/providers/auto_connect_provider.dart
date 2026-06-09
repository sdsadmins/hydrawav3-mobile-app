import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether BLE auto-connect is enabled. App-scoped so the app-wide
/// [AutoConnectManager] and the device list screen share one source of truth.
/// Default OFF — the user opts in from the device list.
final autoConnectEnabledProvider = StateProvider<bool>((ref) => false);

/// Device ids with a connect attempt currently in flight. Shared dedupe guard
/// between the [AutoConnectManager] and the device list screen so the same
/// device is never connected twice concurrently.
final bleConnectingIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});
