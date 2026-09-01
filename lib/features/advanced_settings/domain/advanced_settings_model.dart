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

  /// Hot/cold pad intensity adjustment, as a percentage applied
  /// INDEPENDENTLY to each cycle's own base PWM value (see
  /// [SessionEngine.applyIndividualPercent]) — no coupling between cycles,
  /// no pooling. 0 means "unmodified, use the protocol's own values".
  /// A cycle whose base value is 0 always stays 0, at any percent.
  final double hotPercent;
  final double coldPercent;

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
    this.hotPercent = 0,
    this.coldPercent = 0,
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
        hotPercent != defaults.hotPercent ||
        coldPercent != defaults.coldPercent ||
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
    double? hotPercent,
    double? coldPercent,
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
      hotPercent: hotPercent ?? this.hotPercent,
      coldPercent: coldPercent ?? this.coldPercent,
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
        'hotPercent': hotPercent,
        'coldPercent': coldPercent,
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
        json.containsKey('overrideProtocolDefaults') ||
        json.containsKey('hotLevel') ||
        json.containsKey('hotPwmByCycle');

    if (hasLegacy) {
      // Legacy was level- or array-based; keep web default vibration
      // mode/lights and drop the intensity override rather than guess at a
      // conversion.
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
      hotPercent: (json['hotPercent'] as num?)?.toDouble() ?? 0,
      coldPercent: (json['coldPercent'] as num?)?.toDouble() ?? 0,
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
