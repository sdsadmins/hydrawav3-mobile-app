import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/intake_enums.dart';
import '../../domain/intake_models.dart';

/// How the session is configured: a multi-step Guided Assessment (AI intake)
/// or a Quick Start (straight to device/protocol setup). Mirrors the web's
/// Guided Assessment vs Quick Start choice.
enum SessionType { guided, quick }

// Default to Quick Start so a Guest session can start immediately from the
// Devices screen without needing the Guided Assessment (which now lives on the
// AI tab and is opt-in). Selecting Client mode or Guided on the AI tab re-gates
// Start on a completed assessment.
final sessionTypeProvider =
    StateProvider<SessionType>((ref) => SessionType.quick);

/// Holds the in-progress Guided Assessment wizard state.
class GuidedAssessmentNotifier extends StateNotifier<GuidedAssessmentData> {
  GuidedAssessmentNotifier() : super(const GuidedAssessmentData());

  void reset() => state = const GuidedAssessmentData();

  // --- Discomfort areas ---
  void addArea(DiscomfortAreaInput area) =>
      state = state.copyWith(discomfortAreas: [...state.discomfortAreas, area]);

  void updateArea(int index, DiscomfortAreaInput area) {
    final next = [...state.discomfortAreas];
    if (index < 0 || index >= next.length) return;
    next[index] = area;
    state = state.copyWith(discomfortAreas: next);
  }

  void removeArea(int index) {
    final next = [...state.discomfortAreas]..removeAt(index);
    state = state.copyWith(discomfortAreas: next);
  }

  // --- ROM findings ---
  void addRomFinding(RomFinding finding) =>
      state = state.copyWith(romFindings: [...state.romFindings, finding]);

  void removeRomFinding(int index) {
    final next = [...state.romFindings]..removeAt(index);
    state = state.copyWith(romFindings: next);
  }

  // --- Daily activities ---
  void addActivity(DailyActivityInput activity) => state = state
      .copyWith(dailyActivities: [...state.dailyActivities, activity]);

  void removeActivity(int index) {
    final next = [...state.dailyActivities]..removeAt(index);
    state = state.copyWith(dailyActivities: next);
  }

  // --- Single-value fields ---
  void setSleepPosture(SleepPosture? v) =>
      state = GuidedAssessmentData(
        discomfortAreas: state.discomfortAreas,
        romFindings: state.romFindings,
        dailyActivities: state.dailyActivities,
        sleepPosture: v,
        worseningFactors: state.worseningFactors,
        improvingFactors: state.improvingFactors,
        hardestPosition: state.hardestPosition,
        hipTightness: state.hipTightness,
        missingRemark: state.missingRemark,
      );

  void setHardestPosition(HardPositionTolerance? v) =>
      state = GuidedAssessmentData(
        discomfortAreas: state.discomfortAreas,
        romFindings: state.romFindings,
        dailyActivities: state.dailyActivities,
        sleepPosture: state.sleepPosture,
        worseningFactors: state.worseningFactors,
        improvingFactors: state.improvingFactors,
        hardestPosition: v,
        hipTightness: state.hipTightness,
        missingRemark: state.missingRemark,
      );

  void setHipTightness(HipTightness? v) => state = GuidedAssessmentData(
        discomfortAreas: state.discomfortAreas,
        romFindings: state.romFindings,
        dailyActivities: state.dailyActivities,
        sleepPosture: state.sleepPosture,
        worseningFactors: state.worseningFactors,
        improvingFactors: state.improvingFactors,
        hardestPosition: state.hardestPosition,
        hipTightness: v,
        missingRemark: state.missingRemark,
      );

  void setWorseningFactors(List<String> v) =>
      state = state.copyWith(worseningFactors: v);

  void setImprovingFactors(List<String> v) =>
      state = state.copyWith(improvingFactors: v);

  void setMissingRemark(String? v) => state = state.copyWith(missingRemark: v);
}

final guidedAssessmentProvider =
    StateNotifierProvider<GuidedAssessmentNotifier, GuidedAssessmentData>(
        (ref) => GuidedAssessmentNotifier());
