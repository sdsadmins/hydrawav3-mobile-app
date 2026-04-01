import 'dart:convert';

class AdvancedSettings {
  final double hotPwm;
  final double coldPwm;
  final double vibMin;
  final double vibMax;
  final double lightIntensity;
  final double customCyclePause;
  final bool overrideProtocolDefaults;

  const AdvancedSettings({
    this.hotPwm = 50,
    this.coldPwm = 50,
    this.vibMin = 0,
    this.vibMax = 100,
    this.lightIntensity = 50,
    this.customCyclePause = 0,
    this.overrideProtocolDefaults = false,
  });

  AdvancedSettings copyWith({
    double? hotPwm,
    double? coldPwm,
    double? vibMin,
    double? vibMax,
    double? lightIntensity,
    double? customCyclePause,
    bool? overrideProtocolDefaults,
  }) {
    return AdvancedSettings(
      hotPwm: hotPwm ?? this.hotPwm,
      coldPwm: coldPwm ?? this.coldPwm,
      vibMin: vibMin ?? this.vibMin,
      vibMax: vibMax ?? this.vibMax,
      lightIntensity: lightIntensity ?? this.lightIntensity,
      customCyclePause: customCyclePause ?? this.customCyclePause,
      overrideProtocolDefaults:
          overrideProtocolDefaults ?? this.overrideProtocolDefaults,
    );
  }

  Map<String, dynamic> toJson() => {
        'hotPwm': hotPwm,
        'coldPwm': coldPwm,
        'vibMin': vibMin,
        'vibMax': vibMax,
        'lightIntensity': lightIntensity,
        'customCyclePause': customCyclePause,
        'overrideProtocolDefaults': overrideProtocolDefaults,
      };

  factory AdvancedSettings.fromJson(Map<String, dynamic> json) =>
      AdvancedSettings(
        hotPwm: (json['hotPwm'] as num?)?.toDouble() ?? 50,
        coldPwm: (json['coldPwm'] as num?)?.toDouble() ?? 50,
        vibMin: (json['vibMin'] as num?)?.toDouble() ?? 0,
        vibMax: (json['vibMax'] as num?)?.toDouble() ?? 100,
        lightIntensity:
            (json['lightIntensity'] as num?)?.toDouble() ?? 50,
        customCyclePause:
            (json['customCyclePause'] as num?)?.toDouble() ?? 0,
        overrideProtocolDefaults:
            json['overrideProtocolDefaults'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());

  factory AdvancedSettings.decode(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '{}') return const AdvancedSettings();
    return AdvancedSettings.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }
}
