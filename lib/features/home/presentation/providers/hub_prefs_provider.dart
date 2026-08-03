import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/preferences.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';

/// The Hub's customizable module stack (`HUB_MODULES` in the UI spec).
enum HubModule {
  perfrec,
  quickpulse,
  gameday,
  week,
  lastsession,
  mobility,
  labs,
  resources,
}

/// Modules the spec allows to shrink to a compact row. The rest are fixed size.
const Set<HubModule> kResizableModules = {
  HubModule.gameday,
  HubModule.lastsession,
  HubModule.mobility,
  HubModule.labs,
};

/// Order + per-module size + hidden set, persisted so a practitioner's Hub
/// survives a restart (the spec's `S.hubLayout`).
class HubLayout {
  final List<HubModule> order;
  final Set<HubModule> small;
  final Set<HubModule> hidden;

  const HubLayout({
    required this.order,
    this.small = const {},
    this.hidden = const {},
  });

  static const HubLayout initial = HubLayout(order: HubModule.values);

  List<HubModule> get visible =>
      order.where((m) => !hidden.contains(m)).toList();

  bool isSmall(HubModule m) =>
      kResizableModules.contains(m) && small.contains(m);

  HubLayout copyWith({
    List<HubModule>? order,
    Set<HubModule>? small,
    Set<HubModule>? hidden,
  }) =>
      HubLayout(
        order: order ?? this.order,
        small: small ?? this.small,
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((m) => m.name).toList(),
        'small': small.map((m) => m.name).toList(),
        'hidden': hidden.map((m) => m.name).toList(),
      };

  static HubModule? _parse(Object? name) {
    for (final m in HubModule.values) {
      if (m.name == name) return m;
    }
    return null; // a module removed in a later build — drop it silently
  }

  factory HubLayout.fromJson(Map<String, dynamic> json) {
    final order = (json['order'] as List<dynamic>? ?? const [])
        .map(_parse)
        .whereType<HubModule>()
        .toList();
    // Modules added since the layout was saved append in declaration order,
    // so a new Hub card shows up instead of silently never rendering.
    for (final m in HubModule.values) {
      if (!order.contains(m)) order.add(m);
    }
    return HubLayout(
      order: order,
      small: (json['small'] as List<dynamic>? ?? const [])
          .map(_parse)
          .whereType<HubModule>()
          .toSet(),
      hidden: (json['hidden'] as List<dynamic>? ?? const [])
          .map(_parse)
          .whereType<HubModule>()
          .toSet(),
    );
  }
}

final hubLayoutProvider =
    StateNotifierProvider<HubLayoutNotifier, HubLayout>((ref) {
  return HubLayoutNotifier(ref.read(sharedPreferencesProvider));
});

class HubLayoutNotifier extends StateNotifier<HubLayout> {
  static const _key = 'hub_layout';
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

  Future<void> _save() =>
      _prefs.setString(_key, jsonEncode(state.toJson()));

  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = [...state.order];
    final item = order.removeAt(oldIndex);
    order.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    state = state.copyWith(order: order);
    await _save();
  }

  Future<void> toggleSize(HubModule m) async {
    if (!kResizableModules.contains(m)) return;
    final small = {...state.small};
    small.contains(m) ? small.remove(m) : small.add(m);
    state = state.copyWith(small: small);
    await _save();
  }

  Future<void> setHidden(HubModule m, bool hidden) async {
    final set = {...state.hidden};
    hidden ? set.add(m) : set.remove(m);
    state = state.copyWith(hidden: set);
    await _save();
  }

  Future<void> reset() async {
    state = HubLayout.initial;
    await _prefs.remove(_key);
  }
}

/// Whether the Hub is in customize mode. Session-scoped, never persisted.
final hubEditModeProvider = StateProvider<bool>((ref) => false);

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
final labsEnabledProvider =
    StateNotifierProvider<LabsNotifier, bool>((ref) {
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
