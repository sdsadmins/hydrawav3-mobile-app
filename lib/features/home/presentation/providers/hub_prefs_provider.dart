import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/preferences.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';

/// The Hub's customizable module stack — the v6 prototype's `HUB_MODULES`
/// (hydrawav3-app `hydrawav3-pro-v6.html`, v4 redesign layer + v5 `10-hub.js`).
///
/// Declaration order is the default Hub order.
enum HubModule {
  quick,
  recovery,
  athlete,
  gameprep,
  usage,
  learn,
  lease,
}

/// Per-widget size from Customize Hub (v5 `SIZES`): a compact one-line row, a
/// condensed card, or the full widget. Every v6 module is resizable.
enum HubSize { small, medium, large }

/// Order + per-module size + hidden set, persisted so a practitioner's Hub
/// survives a restart (the prototype's `S.hubLayout`).
class HubLayout {
  final List<HubModule> order;
  final Map<HubModule, HubSize> sizes;
  final Set<HubModule> hidden;

  const HubLayout({
    required this.order,
    this.sizes = const {},
    this.hidden = const {},
  });

  static const HubLayout initial = HubLayout(order: HubModule.values);

  List<HubModule> get visible =>
      order.where((m) => !hidden.contains(m)).toList();

  HubSize sizeOf(HubModule m) => sizes[m] ?? HubSize.large;

  HubLayout copyWith({
    List<HubModule>? order,
    Map<HubModule, HubSize>? sizes,
    Set<HubModule>? hidden,
  }) =>
      HubLayout(
        order: order ?? this.order,
        sizes: sizes ?? this.sizes,
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((m) => m.name).toList(),
        'sizes': {for (final e in sizes.entries) e.key.name: e.value.name},
        'hidden': hidden.map((m) => m.name).toList(),
      };

  static HubModule? _parse(Object? name) {
    for (final m in HubModule.values) {
      if (m.name == name) return m;
    }
    return null; // a module removed in a later build — drop it silently
  }

  static HubSize? _parseSize(Object? name) {
    for (final s in HubSize.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  factory HubLayout.fromJson(Map<String, dynamic> json) {
    final order = (json['order'] as List<dynamic>? ?? const [])
        .map(_parse)
        .whereType<HubModule>()
        .toList();
    final hidden = (json['hidden'] as List<dynamic>? ?? const [])
        .map(_parse)
        .whereType<HubModule>()
        .toSet();
    // Modules added since the layout was saved slot in after the module that
    // precedes them by default (Game Prep lands after Athlete Readiness, not
    // at the bottom), so a new Hub card shows up where it belongs.
    for (final m in HubModule.values) {
      if (order.contains(m) || hidden.contains(m)) continue;
      final before = m.index == 0 ? null : HubModule.values[m.index - 1];
      final at = before == null ? -1 : order.indexOf(before);
      at < 0 ? order.add(m) : order.insert(at + 1, m);
    }
    final sizes = <HubModule, HubSize>{};
    final rawSizes = json['sizes'];
    if (rawSizes is Map) {
      rawSizes.forEach((k, v) {
        final m = _parse(k);
        final s = _parseSize(v);
        if (m != null && s != null) sizes[m] = s;
      });
    }
    return HubLayout(order: order, sizes: sizes, hidden: hidden);
  }
}

final hubLayoutProvider =
    StateNotifierProvider<HubLayoutNotifier, HubLayout>((ref) {
  return HubLayoutNotifier(ref.read(sharedPreferencesProvider));
});

class HubLayoutNotifier extends StateNotifier<HubLayout> {
  // v6 changed the module set entirely, so it gets a fresh key rather than
  // inheriting a layout whose every entry would be dropped anyway.
  static const _key = 'hub_layout_v6';
  final SharedPreferences _prefs;

  HubLayoutNotifier(this._prefs) : super(HubLayout.initial) {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      state = HubLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable layout → fall back to the default rather than crash the Hub.
    }
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode(state.toJson()));

  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = [...state.order];
    final item = order.removeAt(oldIndex);
    order.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    state = state.copyWith(order: order);
    await _save();
  }

  Future<void> setSize(HubModule m, HubSize size) async {
    state = state.copyWith(sizes: {...state.sizes, m: size});
    await _save();
  }

  Future<void> setHidden(HubModule m, bool hidden) async {
    final set = {...state.hidden};
    final order = [...state.order];
    if (hidden) {
      set.add(m);
    } else {
      set.remove(m);
      if (!order.contains(m)) order.add(m);
    }
    state = state.copyWith(hidden: set, order: order);
    await _save();
  }

  Future<void> reset() async {
    state = HubLayout.initial;
    await _prefs.remove(_key);
  }
}

/// Whether the Hub is in customize mode. Session-scoped, never persisted.
final hubEditModeProvider = StateProvider<bool>((ref) => false);

/// The order the Hub renders in: the saved layout, except that on game day
/// Game Prep leads (without being written into the practitioner's layout,
/// and not while customizing).
final hubOrderProvider = Provider<List<HubModule>>((ref) {
  final visible = ref.watch(hubLayoutProvider).visible;
  if (!ref.watch(gameDayActiveProvider) || ref.watch(hubEditModeProvider)) {
    return visible;
  }
  if (!visible.contains(HubModule.gameprep)) return visible;
  return [
    HubModule.gameprep,
    ...visible.where((m) => m != HubModule.gameprep),
  ];
});

/// "Hub animations" (Customize Hub): entrance springs, cascades, the graph
/// drawing in, shimmer and ambient glow. On by default; the OS reduce-motion
/// setting always wins regardless.
final hubMotionProvider = StateNotifierProvider<HubMotionNotifier, bool>((ref) {
  return HubMotionNotifier(ref.read(sharedPreferencesProvider));
});

class HubMotionNotifier extends StateNotifier<bool> {
  static const _key = 'hub_motion_on';
  final SharedPreferences _prefs;

  HubMotionNotifier(this._prefs) : super(_prefs.getBool(_key) ?? true);

  Future<void> set(bool on) async {
    state = on;
    await _prefs.setBool(_key, on);
  }
}

// ---------------------------------------------------------------------------
// Game Prep (v5 `20-gameprep.js`)
// ---------------------------------------------------------------------------

enum GamePrepFilter { prep, done, all }

/// Which players the Game Prep row lists. Session-scoped, like the prototype.
final gamePrepFilterProvider =
    StateProvider<GamePrepFilter>((ref) => GamePrepFilter.prep);

/// Team (sport) filter for multi-sport rosters; null = every team.
final gamePrepTeamProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Usage Statistics window (v5 `S.v5UsageWin`)
// ---------------------------------------------------------------------------

/// The Improvement Score window: last 7 days, last 30 days, or all time.
enum UsageWindow {
  d7('7D', 'last 7 days', '7 days', 'day'),
  d30('30D', 'last 30 days', '30 days', '5-day block'),
  all('ALL', 'all time', 'All time', 'month');

  /// Compact form, for the one-line Small row.
  final String label;
  final String caption;

  /// Spelled out, for the window chips.
  final String chip;

  /// What one point on the graph covers in this window.
  final String bucket;
  const UsageWindow(this.label, this.caption, this.chip, this.bucket);
}

final usageWindowProvider =
    StateNotifierProvider<UsageWindowNotifier, UsageWindow>((ref) {
  return UsageWindowNotifier(ref.read(sharedPreferencesProvider));
});

class UsageWindowNotifier extends StateNotifier<UsageWindow> {
  static const _key = 'hub_usage_window';
  final SharedPreferences _prefs;

  UsageWindowNotifier(this._prefs)
      : super(UsageWindow.values.firstWhere(
          (w) => w.name == _prefs.getString(_key),
          orElse: () => UsageWindow.d7,
        ));

  Future<void> set(UsageWindow w) async {
    state = w;
    await _prefs.setString(_key, w.name);
  }
}

// ---------------------------------------------------------------------------
// Quick Start unit selection
// ---------------------------------------------------------------------------

/// Units armed on the Hub's Quick Start card (BLE device ids).
///
/// Null until the practitioner touches the list — while null, the card arms
/// the first free connected unit on its own (v4 `v4AutoArm`), so one tap on
/// Start Now is enough in the common single-unit case.
final hubQuickStartUnitsProvider = StateProvider<Set<String>?>((ref) => null);

// ---------------------------------------------------------------------------
// Session defaults (More → Session defaults, read by the Hub's Quick Start)
// ---------------------------------------------------------------------------

/// The org's default protocol for Quick Start.
///
/// Falls back to the most recently used protocol so a practitioner who has run
/// anything at all gets a working one-tap start without configuring it first.
/// Null when neither exists — Quick Start then renders disabled with a reason
/// rather than inventing a protocol.
final defaultProtocolIdProvider =
    StateNotifierProvider<DefaultProtocolNotifier, String?>((ref) {
  final recents = ref.watch(recentProtocolIdsProvider);
  return DefaultProtocolNotifier(
    ref.read(sharedPreferencesProvider),
    recents.isEmpty ? null : recents.first,
  );
});

class DefaultProtocolNotifier extends StateNotifier<String?> {
  static const _key = 'hub_default_protocol_id';
  final SharedPreferences _prefs;

  DefaultProtocolNotifier(this._prefs, String? fallback)
      : super(_prefs.getString(_key) ?? fallback);

  Future<void> set(String protocolId) async {
    state = protocolId;
    await _prefs.setString(_key, protocolId);
  }
}

/// Labs (experimental readiness) — off by default per the spec; the Hub's
/// Breath Readiness card only renders when this is on.
final labsEnabledProvider = StateNotifierProvider<LabsNotifier, bool>((ref) {
  return LabsNotifier(ref.read(sharedPreferencesProvider));
});

class LabsNotifier extends StateNotifier<bool> {
  static const _key = 'hub_labs_enabled';
  final SharedPreferences _prefs;

  LabsNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);

  Future<void> toggle() async {
    state = !state;
    await _prefs.setBool(_key, state);
  }
}

/// Global switch (Devices List screen) for the Protocol Plus "2 beeps only"
/// behaviour: while a Plus run is BLE and has more than one sub-protocol, the
/// app arms the firmware's `{"muteSeconds": N}` window (~10s before
/// protocol[0] ends) so every mid-stack stop/start chime is silenced and only
/// the first start + last end beep sound. This is now OPT-IN — default OFF,
/// so the firmware beeps normally (every sub-protocol switch) unless the
/// practitioner turns this on. See [SessionEngine._maybeArmPlusMute].
final protocolPlusMuteEnabledProvider =
    StateNotifierProvider<ProtocolPlusMuteNotifier, bool>((ref) {
  return ProtocolPlusMuteNotifier(ref.read(sharedPreferencesProvider));
});

class ProtocolPlusMuteNotifier extends StateNotifier<bool> {
  static const _key = 'protocol_plus_mute_enabled';
  final SharedPreferences _prefs;

  ProtocolPlusMuteNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _prefs.setBool(_key, enabled);
  }
}

/// Game day is a per-day switch the practitioner flips; there is no backend
/// concept for it, so it lives in preferences keyed by date. Flipping to a new
/// calendar day clears it automatically.
final gameDayActiveProvider =
    StateNotifierProvider<GameDayNotifier, bool>((ref) {
  return GameDayNotifier(ref.read(sharedPreferencesProvider));
});

class GameDayNotifier extends StateNotifier<bool> {
  static const _key = 'hub_game_day_on';
  final SharedPreferences _prefs;

  static String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  GameDayNotifier(this._prefs) : super(_prefs.getString(_key) == _today);

  Future<void> activate() async {
    state = true;
    await _prefs.setString(_key, _today);
  }

  Future<void> end() async {
    state = false;
    await _prefs.remove(_key);
  }
}
