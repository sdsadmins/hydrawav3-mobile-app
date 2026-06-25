import '../../clients/domain/client_model.dart';
import 'intake_enums.dart';

/// One "Area of Focus" entry → backend `discomfortAreas[]`.
class DiscomfortAreaInput {
  final String bodyPart;
  final DiscomfortSide side;
  final int discomfortBefore; // 0-10
  final int discomfortAfter; // 0-10
  final RomLevel romLevel;
  final DiscomfortBehavior behavior;
  final TemporalDuration temporalDuration;
  final String? notes;

  const DiscomfortAreaInput({
    required this.bodyPart,
    this.side = DiscomfortSide.both,
    this.discomfortBefore = 0,
    this.discomfortAfter = 0,
    this.romLevel = RomLevel.normal,
    this.behavior = DiscomfortBehavior.comesAndGoes,
    this.temporalDuration = TemporalDuration.lessThan6Weeks,
    this.notes,
  });

  DiscomfortAreaInput copyWith({
    String? bodyPart,
    DiscomfortSide? side,
    int? discomfortBefore,
    int? discomfortAfter,
    RomLevel? romLevel,
    DiscomfortBehavior? behavior,
    TemporalDuration? temporalDuration,
    String? notes,
  }) {
    return DiscomfortAreaInput(
      bodyPart: bodyPart ?? this.bodyPart,
      side: side ?? this.side,
      discomfortBefore: discomfortBefore ?? this.discomfortBefore,
      discomfortAfter: discomfortAfter ?? this.discomfortAfter,
      romLevel: romLevel ?? this.romLevel,
      behavior: behavior ?? this.behavior,
      temporalDuration: temporalDuration ?? this.temporalDuration,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toIntakeJson() => {
        'discompfortbodyPart': bodyPart,
        'side': side.value,
        'discomfortBefore': discomfortBefore,
        'discomfortAfter': discomfortAfter,
        'temporalDuration': temporalDuration.value,
        'behavior': behavior.value,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
      };

  Map<String, dynamic> toJson() => {
        'bodyPart': bodyPart,
        'side': side.value,
        'discomfortBefore': discomfortBefore,
        'discomfortAfter': discomfortAfter,
        'romLevel': romLevel.value,
        'behavior': behavior.value,
        'temporalDuration': temporalDuration.value,
        'notes': notes,
      };

  factory DiscomfortAreaInput.fromJson(Map<String, dynamic> j) {
    return DiscomfortAreaInput(
      bodyPart: (j['bodyPart'] ?? '').toString(),
      side: enumFromValue(
              DiscomfortSide.values, j['side']?.toString(), (e) => e.value) ??
          DiscomfortSide.both,
      discomfortBefore: (j['discomfortBefore'] as num?)?.toInt() ?? 0,
      discomfortAfter: (j['discomfortAfter'] as num?)?.toInt() ?? 0,
      romLevel: enumFromValue(
              RomLevel.values, j['romLevel']?.toString(), (e) => e.value) ??
          RomLevel.normal,
      behavior: enumFromValue(DiscomfortBehavior.values,
              j['behavior']?.toString(), (e) => e.value) ??
          DiscomfortBehavior.comesAndGoes,
      temporalDuration: enumFromValue(TemporalDuration.values,
              j['temporalDuration']?.toString(), (e) => e.value) ??
          TemporalDuration.lessThan6Weeks,
      notes: j['notes']?.toString(),
    );
  }
}

/// One range-of-motion finding → backend `romFindings[]`.
class RomFinding {
  final String testName;
  final String bodyPart;
  final String sensation;

  const RomFinding({
    required this.testName,
    required this.bodyPart,
    required this.sensation,
  });

  Map<String, dynamic> toJson() => {
        'testName': testName,
        'bodyPart': bodyPart,
        'sensation': sensation,
      };

  factory RomFinding.fromJson(Map<String, dynamic> j) => RomFinding(
        testName: (j['testName'] ?? '').toString(),
        bodyPart: (j['bodyPart'] ?? '').toString(),
        sensation: (j['sensation'] ?? '').toString(),
      );
}

/// One daily activity → backend `dailyActivities[]` (rank >= 1).
class DailyActivityInput {
  final String name;
  final int rank;

  const DailyActivityInput({required this.name, this.rank = 1});

  Map<String, dynamic> toJson() => {'name': name, 'rank': rank < 1 ? 1 : rank};

  factory DailyActivityInput.fromJson(Map<String, dynamic> j) =>
      DailyActivityInput(
        name: (j['name'] ?? '').toString(),
        rank: (j['rank'] as num?)?.toInt() ?? 1,
      );
}

/// Mutable state for the Guided Assessment wizard. Holds everything collected
/// across the 4 steps. Serialises to:
///   - [toIntakeFields] — camelCase fragment for `POST /intake`.
///   - [toPatientIntakeInput] — snake_case payload for `POST ai/analyze`.
///   - [toJson]/[fromJson] — for offline persistence (Drift `intakeJson`).
class GuidedAssessmentData {
  final List<DiscomfortAreaInput> discomfortAreas;
  final List<RomFinding> romFindings;
  final List<DailyActivityInput> dailyActivities;
  final SleepPosture? sleepPosture;
  final List<String> worseningFactors;
  final List<String> improvingFactors;
  final HardPositionTolerance? hardestPosition;
  final HipTightness? hipTightness;
  final String? missingRemark;

  const GuidedAssessmentData({
    this.discomfortAreas = const [],
    this.romFindings = const [],
    this.dailyActivities = const [],
    this.sleepPosture,
    this.worseningFactors = const [],
    this.improvingFactors = const [],
    this.hardestPosition,
    this.hipTightness,
    this.missingRemark,
  });

  GuidedAssessmentData copyWith({
    List<DiscomfortAreaInput>? discomfortAreas,
    List<RomFinding>? romFindings,
    List<DailyActivityInput>? dailyActivities,
    SleepPosture? sleepPosture,
    List<String>? worseningFactors,
    List<String>? improvingFactors,
    HardPositionTolerance? hardestPosition,
    HipTightness? hipTightness,
    String? missingRemark,
  }) {
    return GuidedAssessmentData(
      discomfortAreas: discomfortAreas ?? this.discomfortAreas,
      romFindings: romFindings ?? this.romFindings,
      dailyActivities: dailyActivities ?? this.dailyActivities,
      sleepPosture: sleepPosture ?? this.sleepPosture,
      worseningFactors: worseningFactors ?? this.worseningFactors,
      improvingFactors: improvingFactors ?? this.improvingFactors,
      hardestPosition: hardestPosition ?? this.hardestPosition,
      hipTightness: hipTightness ?? this.hipTightness,
      missingRemark: missingRemark ?? this.missingRemark,
    );
  }

  /// Whether the required fields for generating an AI report are present
  /// (mirrors the web `canGenerateReport`).
  bool get canGenerateReport =>
      discomfortAreas.isNotEmpty &&
      romFindings.isNotEmpty &&
      dailyActivities.isNotEmpty &&
      sleepPosture != null &&
      hardestPosition != null;

  /// camelCase fragment merged into the `POST /intake` body.
  Map<String, dynamic> toIntakeFields() {
    return {
      if (sleepPosture != null) 'sleepPosture': sleepPosture!.value,
      if (hardestPosition != null)
        'hardPositionTolerance': hardestPosition!.value,
      if (hipTightness != null) 'hipTightness': hipTightness!.value,
      if (worseningFactors.isNotEmpty) 'worseningFactors': worseningFactors,
      if (improvingFactors.isNotEmpty) 'improvingFactors': improvingFactors,
      if (discomfortAreas.isNotEmpty)
        'discomfortAreas':
            discomfortAreas.map((a) => a.toIntakeJson()).toList(),
      if (romFindings.isNotEmpty)
        'romFindings': romFindings.map((r) => r.toJson()).toList(),
      if (dailyActivities.isNotEmpty)
        'dailyActivities': dailyActivities.map((d) => d.toJson()).toList(),
      if (missingRemark != null && missingRemark!.trim().isNotEmpty)
        'missingRemark': missingRemark,
    };
  }

  /// snake_case `PatientIntakeInput` for `POST ai/analyze`. Demographics come
  /// from the selected [client] (omitted in guest mode). Replicates the web
  /// `mapSessionDataToIntakeInput`.
  Map<String, dynamic> toPatientIntakeInput(Client? client) {
    final demographics = <String, dynamic>{};
    if (client?.age != null) demographics['age'] = client!.age;
    if (client?.gender != null && client!.gender!.trim().isNotEmpty) {
      demographics['gender'] = client.gender;
    }

    final painDurationMonths = discomfortAreas.isNotEmpty
        ? discomfortAreas.first.temporalDuration.aiMonths
        : '3';

    return {
      if (demographics.isNotEmpty) 'demographics': demographics,
      'daily_activities': dailyActivities
          .map((d) => {'activity': d.name, 'hours': d.rank})
          .toList(),
      'discomfort_areas': discomfortAreas
          .map((a) => {
                'body_area': a.bodyPart,
                'side': a.side.aiValue,
                'pain_level': a.discomfortBefore,
                'range_of_motion': a.romLevel.aiValue,
                'behavior': a.behavior.value,
                if (a.notes != null && a.notes!.trim().isNotEmpty)
                  'description': a.notes,
                'temporalDuration': a.temporalDuration.value,
              })
          .toList(),
      'movement_findings': romFindings
          .map((r) => {
                'movement_test': r.testName,
                'discomfort_area': r.bodyPart,
                'sensation': r.sensation,
              })
          .toList(),
      'pain_duration_months': painDurationMonths,
      if (sleepPosture != null) 'sleep_posture': sleepPosture!.value,
      if (hipTightness != null) 'hip_tightness': hipTightness!.value,
      if (worseningFactors.isNotEmpty) 'worsening_factors': worseningFactors,
      if (improvingFactors.isNotEmpty) 'improving_factors': improvingFactors,
      if (hardestPosition != null)
        'position_intolerance': hardestPosition!.value,
      if (missingRemark != null && missingRemark!.trim().isNotEmpty)
        'missingRemark': missingRemark,
    };
  }

  Map<String, dynamic> toJson() => {
        'discomfortAreas': discomfortAreas.map((a) => a.toJson()).toList(),
        'romFindings': romFindings.map((r) => r.toJson()).toList(),
        'dailyActivities': dailyActivities.map((d) => d.toJson()).toList(),
        'sleepPosture': sleepPosture?.value,
        'worseningFactors': worseningFactors,
        'improvingFactors': improvingFactors,
        'hardPositionTolerance': hardestPosition?.value,
        'hipTightness': hipTightness?.value,
        'missingRemark': missingRemark,
      };

  factory GuidedAssessmentData.fromJson(Map<String, dynamic> j) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) build) {
      final raw = j[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => build(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<String> strList(String key) {
      final raw = j[key];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList();
    }

    return GuidedAssessmentData(
      discomfortAreas: listOf('discomfortAreas', DiscomfortAreaInput.fromJson),
      romFindings: listOf('romFindings', RomFinding.fromJson),
      dailyActivities: listOf('dailyActivities', DailyActivityInput.fromJson),
      sleepPosture: enumFromValue(
          SleepPosture.values, j['sleepPosture']?.toString(), (e) => e.value),
      worseningFactors: strList('worseningFactors'),
      improvingFactors: strList('improvingFactors'),
      hardestPosition: enumFromValue(HardPositionTolerance.values,
          j['hardPositionTolerance']?.toString(), (e) => e.value),
      hipTightness: enumFromValue(
          HipTightness.values, j['hipTightness']?.toString(), (e) => e.value),
      missingRemark: j['missingRemark']?.toString(),
    );
  }
}
