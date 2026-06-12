import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences.dart';

/// Whether BLE auto-connect is enabled. App-scoped so the app-wide
/// [AutoConnectManager] and the device list screen share one source of truth.
/// Persisted to preferences (like dark theme) so it stays on once toggled.
final autoConnectEnabledProvider =
    StateNotifierProvider<AutoConnectController, bool>((ref) {
  return AutoConnectController(ref.read(preferencesProvider));
});

class AutoConnectController extends StateNotifier<bool> {
  final PreferencesService _preferences;

  AutoConnectController(this._preferences)
      : super(_preferences.autoConnectEnabled);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _preferences.setAutoConnectEnabled(enabled);
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Device ids with a connect attempt currently in flight. Shared dedupe guard
/// between the [AutoConnectManager] and the device list screen so the same
/// device is never connected twice concurrently.
final bleConnectingIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});
