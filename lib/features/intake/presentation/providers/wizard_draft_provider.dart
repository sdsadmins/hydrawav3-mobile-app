import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Save-and-resume state for the Guided Assessment wizard.
///
/// The spec's `startWizard()` (app.js:2856) reuses an in-progress wizard rather
/// than restarting it, and advertises `Resume · step N of 5` on the entry card.
/// The answers themselves already live in `guidedAssessmentProvider`; the only
/// thing missing was WHERE the user had got to, plus the per-area range-of-motion
/// percentage — which the backend stores as a coarse `RomLevel`, so the exact
/// slider position would otherwise be lost on the way back in.
class WizardDraft {
  /// 1-based step, 1..5.
  final int step;

  /// Body part → comfortable range, 10–100%.
  final Map<String, int> romPercent;

  const WizardDraft({this.step = 1, this.romPercent = const {}});

  WizardDraft copyWith({int? step, Map<String, int>? romPercent}) =>
      WizardDraft(
        step: step ?? this.step,
        romPercent: romPercent ?? this.romPercent,
      );
}

class WizardDraftNotifier extends StateNotifier<WizardDraft> {
  WizardDraftNotifier() : super(const WizardDraft());

  void setStep(int step) => state = state.copyWith(step: step.clamp(1, 5));

  void setRomPercent(String bodyPart, int pct) => state = state.copyWith(
        romPercent: {...state.romPercent, bodyPart: pct},
      );

  /// The spec's default when an area is first selected (`areas[t] = {rom: 60}`).
  int romFor(String bodyPart) => state.romPercent[bodyPart] ?? 60;

  void reset() => state = const WizardDraft();
}

final wizardDraftProvider =
    StateNotifierProvider<WizardDraftNotifier, WizardDraft>(
        (ref) => WizardDraftNotifier());
