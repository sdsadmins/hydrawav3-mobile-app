import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global registry of Protocol Plus device ids currently frozen waiting to
/// reconnect (on break AND BLE-disconnected — see
/// `SessionEngine.protocolPlusAwaitingReconnectByDevice`).
///
/// Each live [SessionEngine] instance pushes its own device ids into this
/// registry directly (see `SessionEngine._publishAwaitingReconnectIds`)
/// instead of the reader trying to look the engine up by matching an
/// [ActiveSession] id to a `sessionEngineFamilyProvider` key: those two keys
/// can diverge — a session screen falls back to a locally-built engine key
/// (`SessionScreenState._buildFallbackEngineKey`) whenever the active-session
/// record hasn't been created yet, which made an id-matching lookup silently
/// find nothing and the global reconnect popup never fire.
///
/// Read by `PlusReconnectWatchdog` to drive the "bring your device back in
/// range" reminder from anywhere in the app.
final plusAwaitingReconnectDeviceIdsProvider =
    StateProvider<Set<String>>((ref) => const {});
