import 'dart:convert';

class AdvancedSettings {
  /// Mirrors the web app "Advanced Settings" payload controls.
  ///
  /// This model is stored inside presets (`advancedSettingsJson`) and can also
  /// be passed through navigation extras for per-session overrides.
  final bool lights;

  /// Web supports 'Off' | 'Sweep' | 'Single'. Mobile UI currently uses
  /// a simple toggle; we still keep the mode to match server/device payload.
  final String vibrationMode;
  final double vibrationSweepMin;
  final double vibrationSweepMax;
  final double vibrationSingleHz;

  final bool cycle1Initiation;
  final bool cycle5Completion;

  /// 0–11 intensity levels, mapped to PWM arrays when hotPack/coldPack enabled.
  final int hotLevel;
  final int coldLevel;
  final bool hotPack;
  final bool coldPack;

  final double hotDrop;
  final double coldDrop;
  final double vibMin;
  final double vibMax;

  /// Seconds. For multi-device sessions, the app can apply delay to one device.
  final int startDelay;

  /// Swap HotRed <-> ColdBlue in left/right functions.
  final bool flipSettings;

  const AdvancedSettings({
    this.lights = true,
    this.vibrationMode = 'Sweep',
    this.vibrationSweepMin = 1,
    this.vibrationSweepMax = 230,
    this.vibrationSingleHz = 100,
    this.cycle1Initiation = true,
    this.cycle5Completion = true,
    this.hotLevel = 5,
    this.coldLevel = 5,
    this.hotPack = false,
    this.coldPack = false,
    this.hotDrop = 0,
    this.coldDrop = 0,
    this.vibMin = 15,
    this.vibMax = 234,
    this.startDelay = 0,
    this.flipSettings = false,
  });

  bool get hasCustomOverrides {
    const defaults = AdvancedSettings();
    return lights != defaults.lights ||
        vibrationMode != defaults.vibrationMode ||
        vibrationSweepMin != defaults.vibrationSweepMin ||
        vibrationSweepMax != defaults.vibrationSweepMax ||
        vibrationSingleHz != defaults.vibrationSingleHz ||
        cycle1Initiation != defaults.cycle1Initiation ||
        cycle5Completion != defaults.cycle5Completion ||
        hotLevel != defaults.hotLevel ||
        coldLevel != defaults.coldLevel ||
        hotPack != defaults.hotPack ||
        coldPack != defaults.coldPack ||
        hotDrop != defaults.hotDrop ||
        coldDrop != defaults.coldDrop ||
        vibMin != defaults.vibMin ||
        vibMax != defaults.vibMax ||
        startDelay != defaults.startDelay ||
        flipSettings != defaults.flipSettings;
  }

  AdvancedSettings copyWith({
    bool? lights,
    String? vibrationMode,
    double? vibrationSweepMin,
    double? vibrationSweepMax,
    double? vibrationSingleHz,
    bool? cycle1Initiation,
    bool? cycle5Completion,
    int? hotLevel,
    int? coldLevel,
    bool? hotPack,
    bool? coldPack,
    double? hotDrop,
    double? coldDrop,
    double? vibMin,
    double? vibMax,
    int? startDelay,
    bool? flipSettings,
  }) {
    return AdvancedSettings(
      lights: lights ?? this.lights,
      vibrationMode: vibrationMode ?? this.vibrationMode,
      vibrationSweepMin: vibrationSweepMin ?? this.vibrationSweepMin,
      vibrationSweepMax: vibrationSweepMax ?? this.vibrationSweepMax,
      vibrationSingleHz: vibrationSingleHz ?? this.vibrationSingleHz,
      cycle1Initiation: cycle1Initiation ?? this.cycle1Initiation,
      cycle5Completion: cycle5Completion ?? this.cycle5Completion,
      hotLevel: hotLevel ?? this.hotLevel,
      coldLevel: coldLevel ?? this.coldLevel,
      hotPack: hotPack ?? this.hotPack,
      coldPack: coldPack ?? this.coldPack,
      hotDrop: hotDrop ?? this.hotDrop,
      coldDrop: coldDrop ?? this.coldDrop,
      vibMin: vibMin ?? this.vibMin,
      vibMax: vibMax ?? this.vibMax,
      startDelay: startDelay ?? this.startDelay,
      flipSettings: flipSettings ?? this.flipSettings,
    );
  }

  Map<String, dynamic> toJson() => {
        'lights': lights,
        'vibrationMode': vibrationMode,
        'vibrationSweepMin': vibrationSweepMin,
        'vibrationSweepMax': vibrationSweepMax,
        'vibrationSingleHz': vibrationSingleHz,
        'cycle1Initiation': cycle1Initiation,
        'cycle5Completion': cycle5Completion,
        'hotLevel': hotLevel,
        'coldLevel': coldLevel,
        'hotPack': hotPack,
        'coldPack': coldPack,
        'hotDrop': hotDrop,
        'coldDrop': coldDrop,
        'vibMin': vibMin,
        'vibMax': vibMax,
        'startDelay': startDelay,
        'flipSettings': flipSettings,
      };

  factory AdvancedSettings.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: older app versions stored different keys.
    // If we detect the legacy schema, fall back to defaults + whatever we can map.
    final hasLegacy = json.containsKey('hotPwm') ||
        json.containsKey('coldPwm') ||
        json.containsKey('lightIntensity') ||
        json.containsKey('overrideProtocolDefaults');

    if (hasLegacy) {
      // Legacy was percent-based; keep web default vibration mode/lights.
      return AdvancedSettings(
        lights: true,
        vibrationMode: 'Sweep',
        vibMin: (json['vibMin'] as num?)?.toDouble() ?? 15,
        vibMax: (json['vibMax'] as num?)?.toDouble() ?? 234,
      );
    }

    return AdvancedSettings(
      lights: json['lights'] as bool? ?? true,
      vibrationMode: json['vibrationMode'] as String? ?? 'Sweep',
      vibrationSweepMin: (json['vibrationSweepMin'] as num?)?.toDouble() ?? 1,
      vibrationSweepMax: (json['vibrationSweepMax'] as num?)?.toDouble() ?? 230,
      vibrationSingleHz: (json['vibrationSingleHz'] as num?)?.toDouble() ?? 100,
      cycle1Initiation: json['cycle1Initiation'] as bool? ?? true,
      cycle5Completion: json['cycle5Completion'] as bool? ?? true,
      hotLevel: (json['hotLevel'] as num?)?.toInt() ?? 5,
      coldLevel: (json['coldLevel'] as num?)?.toInt() ?? 5,
      hotPack: json['hotPack'] as bool? ?? false,
      coldPack: json['coldPack'] as bool? ?? false,
      hotDrop: (json['hotDrop'] as num?)?.toDouble() ?? 0,
      coldDrop: (json['coldDrop'] as num?)?.toDouble() ?? 0,
      vibMin: (json['vibMin'] as num?)?.toDouble() ?? 15,
      vibMax: (json['vibMax'] as num?)?.toDouble() ?? 234,
      startDelay: (json['startDelay'] as num?)?.toInt() ?? 0,
      flipSettings: json['flipSettings'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  factory AdvancedSettings.decode(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '{}') return const AdvancedSettings();
    return AdvancedSettings.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }
}
