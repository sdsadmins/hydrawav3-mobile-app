import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../ai_report/presentation/providers/ai_report_providers.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../domain/intake_enums.dart';
import '../../domain/intake_models.dart';
import '../../domain/rom_instructions.dart';
import '../providers/guided_assessment_provider.dart';
import '../providers/wizard_draft_provider.dart';
import '../widgets/body_map.dart';
import '../widgets/wizard_widgets.dart';

/// The 5-step Guided Assessment — the UI handoff's `scr-wizard`
/// (`renderWizard()`, app.js:2861).
///
/// Steps, per the spec: Area of Focus → Range of Motion → Daily Activities →
/// Usual Sleep Posture → Hardest position to tolerate. That is a step MORE than
/// the app's previous inline wizard, which folded activities, sleep and position
/// into one screen; the data collected is identical, so
/// `GuidedAssessmentData` and `canGenerateReport` are untouched.
///
/// A full screen rather than a card inside session setup: the body stage and the
/// per-area protractor need the room, and the old arrangement duplicated the
/// Generate button across two hosts.
///
/// TWO DELIBERATE DIVERGENCES FROM THE SPEC, both forced:
///
/// 1. Steps 4 and 5 render the BACKEND enums, not the spec's labels. The spec
///    offers `Back/Side/Stomach/Mixed` and `Overhead reach/Deep squat/…`; the
///    server validates `CreateIntakeDto` with `forbidNonWhitelisted`, so those
///    strings are a 400. The spec's step titles and phrasing are kept — see
///    `rom_instructions.dart`.
/// 2. Step 1 uses the existing tap-to-select [BodyMap] rather than the spec's
///    absolutely-positioned `.hotspot` buttons. BodyMap already is a tap-a-region
///    body model with per-region hit testing, so hotspots would be a second
///    interaction layer over the same thing. The spec's microcopy still applies
///    verbatim.
class GuidedAssessmentScreen extends ConsumerStatefulWidget {
  const GuidedAssessmentScreen({super.key});

  @override
  ConsumerState<GuidedAssessmentScreen> createState() =>
      _GuidedAssessmentScreenState();
}

class _GuidedAssessmentScreenState
    extends ConsumerState<GuidedAssessmentScreen> {
  static const _stepCount = 5;

  /// The spec's per-step sub-line, shown under "Guided Assessment".
  static const _subs = [
    'tap regions on the model',
    'same values as the web app',
    'select all that apply',
    'one choice',
    'one choice',
  ];

  int get _step => ref.read(wizardDraftProvider).step;

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  void _back() {
    final step = _step;
    // Spec: step 1's back leaves the flow; 2–5 step backwards.
    if (step <= 1) {
      Navigator.of(context).maybePop();
    } else {
      ref.read(wizardDraftProvider.notifier).setStep(step - 1);
    }
  }

  void _next(GuidedAssessmentData d) {
    final step = _step;
    switch (step) {
      case 1:
        if (d.discomfortAreas.isEmpty) {
          return _toast('Select at least one area of focus before starting.');
        }
        break;
      case 4:
        if (d.sleepPosture == null) return _toast('Select sleep posture');
        break;
      case 5:
        if (d.hardestPosition == null) {
          return _toast('Select the hardest position');
        }
        return _generate();
    }
    ref.read(wizardDraftProvider.notifier).setStep(step + 1);
  }

  /// Kick generation off in the BACKGROUND and go to the reports list, as the
  /// spec's `wizGenerate()` does — the user is never made to wait on a screen.
  void _generate() {
    final err = ref.read(aiReportGenerationProvider.notifier).startGenerate();
    if (!mounted) return;
    if (err != null) return _toast(err);

    // startGenerate already snapshotted the intake, so clearing is safe and
    // leaves the next assessment starting clean.
    ref.read(guidedAssessmentProvider.notifier).reset();
    ref.read(wizardDraftProvider.notifier).reset();
    _toast('Generating AI report…');
    context.pushReplacement(RoutePaths.aiReports);
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final d = ref.watch(guidedAssessmentProvider);
    final draft = ref.watch(wizardDraftProvider);
    final step = draft.step;
    final client = ref.watch(selectedClientProvider);
    final who = client?.displayName ?? 'Guest';
    final isLast = step == _stepCount;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HwSpace.s4),
              child: HwBackBar(
                // The spec's header is always "Guided Assessment"; the step is
                // carried by the sub-line and the pill.
                title: 'Guided Assessment',
                subtitle: '$who · ${_subs[step - 1]}',
                onBack: _back,
                trailing: HwPill('Step $step / $_stepCount',
                    tone: HwPillTone.copper),
              ),
            ),
            WizardStepDots(count: _stepCount, step: step),
            const SizedBox(height: HwSpace.s4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    HwSpace.s4, 0, HwSpace.s4, HwSpace.s4),
                children: [_stepBody(p, d, draft)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  HwSpace.s4, 0, HwSpace.s4, HwSpace.s4),
              child: HwButton(
                label: isLast ? 'Generate AI report' : 'Continue',
                onTap: () => _next(d),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(RefPalette p, GuidedAssessmentData d, WizardDraft draft) {
    switch (draft.step) {
      case 1:
        return _StepAreas(
          areas: d.discomfortAreas,
          onToggle: _toggleArea,
          onEdit: _editArea,
        );
      case 2:
        return _StepRom(areas: d.discomfortAreas);
      case 3:
        return _StepActivities(selected: d.dailyActivities);
      case 4:
        return _StepSleep(value: d.sleepPosture);
      default:
        return _StepHardest(value: d.hardestPosition);
    }
  }

  // -------------------------------------------------------------------------
  // Step 1 mutations
  // -------------------------------------------------------------------------

  /// Tapping a region adds it; tapping a selected region removes it — the spec's
  /// "Tap a selected region again to remove it."
  void _toggleArea(String bodyPart) {
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    final areas = ref.read(guidedAssessmentProvider).discomfortAreas;
    final idx = areas.indexWhere((a) => a.bodyPart == bodyPart);
    if (idx >= 0) {
      notifier.removeArea(idx);
      return;
    }
    notifier.addArea(DiscomfortAreaInput(
      bodyPart: bodyPart,
      // `sideFromAreaName` returns the display string ('Left'/'Right'/'Both'),
      // which is also the backend enum's `.value` — map it back to the enum.
      side: enumFromValue(DiscomfortSide.values, sideFromAreaName(bodyPart),
              (e) => e.value) ??
          DiscomfortSide.both,
      // The spec's defaults for a newly tapped area: discomfort 4, ROM 60%.
      discomfortBefore: 4,
      romLevel: romLevelFromPercent(60),
    ));
    ref.read(wizardDraftProvider.notifier).setRomPercent(bodyPart, 60);
  }

  /// The spec's `areaEditSheet(t)` — discomfort, comfortable range, and a note.
  Future<void> _editArea(int index) async {
    final area = ref.read(guidedAssessmentProvider).discomfortAreas[index];
    var discomfort = area.discomfortBefore;
    var rom = ref.read(wizardDraftProvider.notifier).romFor(area.bodyPart);
    final noteCtrl = TextEditingController(text: area.notes ?? '');

    await showHwSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final sp = RefPalette.of(sheetContext);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                area.bodyPart,
                style: TextStyle(
                  fontSize: HwType.lg,
                  fontWeight: FontWeight.w700,
                  color: sp.ink,
                ),
              ),
              const SizedBox(height: HwSpace.s3),
              WizardSlider(
                label: 'Discomfort level',
                valueLabel: '$discomfort/10',
                value: discomfort.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) =>
                    setSheetState(() => discomfort = v.round()),
              ),
              WizardSlider(
                label: 'Comfortable range of motion',
                valueLabel: '$rom%',
                value: rom.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                onChanged: (v) => setSheetState(() => rom = v.round()),
              ),
              const SizedBox(height: HwSpace.s2),
              HwField(
                label: 'Note (optional)',
                controller: noteCtrl,
                hint: 'e.g., worse in the morning',
              ),
              const SizedBox(height: HwSpace.s2),
              HwButton(
                label: 'Done',
                onTap: () {
                  ref.read(guidedAssessmentProvider.notifier).updateArea(
                        index,
                        area.copyWith(
                          discomfortBefore: discomfort,
                          romLevel: romLevelFromPercent(rom),
                          notes: noteCtrl.text.trim(),
                        ),
                      );
                  ref
                      .read(wizardDraftProvider.notifier)
                      .setRomPercent(area.bodyPart, rom);
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          );
        },
      ),
    );
    noteCtrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Step 1 · Area of Focus
// ---------------------------------------------------------------------------

class _StepAreas extends StatelessWidget {
  final List<DiscomfortAreaInput> areas;
  final ValueChanged<String> onToggle;
  final ValueChanged<int> onEdit;

  const _StepAreas({
    required this.areas,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HwCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            children: [
              SizedBox(
                height: 380,
                child: BodyMap(
                  selectedAreas: areas.map((a) => a.bodyPart).toList(),
                  onSelect: onToggle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        // Spec microcopy, verbatim.
        Text(
          'Tap a selected region again to remove it. Use the pencil to set '
          'discomfort level, range of motion and more.',
          style: TextStyle(fontSize: HwType.eyebrow, height: 1.5, color: p.ink3),
        ),
        const SizedBox(height: HwSpace.s3),
        // The spec's `.padnote` rows.
        for (var i = 0; i < areas.length; i++) _padNote(context, p, i, areas[i]),
      ],
    );
  }

  Widget _padNote(
    BuildContext context,
    RefPalette p,
    int index,
    DiscomfortAreaInput area,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line2),
        borderRadius: BorderRadius.circular(HwRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.tanSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w800,
                color: p.copperInk,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.bodyPart,
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'discomfort ${area.discomfortBefore}/10',
                    'ROM ${area.romLevel.label}',
                    if ((area.notes ?? '').isNotEmpty) area.notes!,
                  ].join(' · '),
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
              ],
            ),
          ),
          HwPress(
            onTap: () => onEdit(index),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.edit_outlined, size: 17, color: p.copperInk),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 · Range of Motion
// ---------------------------------------------------------------------------

class _StepRom extends ConsumerWidget {
  final List<DiscomfortAreaInput> areas;
  const _StepRom({required this.areas});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    if (areas.isEmpty) {
      return Text(
        'Pick an area of focus first.',
        style: TextStyle(fontSize: HwType.cap, color: p.ink3),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < areas.length; i++)
          _romStage(context, ref, p, i, areas[i]),
      ],
    );
  }

  Widget _romStage(
    BuildContext context,
    WidgetRef ref,
    RefPalette p,
    int index,
    DiscomfortAreaInput area,
  ) {
    final draft = ref.watch(wizardDraftProvider);
    final pct = draft.romPercent[area.bodyPart] ?? 60;
    final image = romImageFor(area.bodyPart);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line2),
        borderRadius: BorderRadius.circular(HwRadius.md),
      ),
      child: Column(
        children: [
          // The spec animates a protractor. Where a real ROM photo exists for
          // this movement it's more useful, so the image wins and the protractor
          // is the fallback.
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(HwRadius.sm),
              child: Image.asset(image, height: 120, fit: BoxFit.contain),
            )
          else
            const RomProtractor(),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${area.bodyPart}: ',
                style: TextStyle(
                  fontSize: HwType.cap,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              TextSpan(
                text: romInstructionFor(area.bodyPart),
                style: TextStyle(
                    fontSize: HwType.cap, height: 1.5, color: p.ink2),
              ),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          WizardSlider(
            label: 'Comfortable range of motion',
            valueLabel: '$pct%',
            value: pct.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            onChanged: (v) => _setRom(ref, index, area, v.round()),
          ),
        ],
      ),
    );
  }

  /// Writes BOTH the level on the area AND a `RomFinding`.
  ///
  /// This is the load-bearing bit of step 2. `canGenerateReport` requires
  /// `romFindings.isNotEmpty`, but the spec's step 2 is only a percentage
  /// slider — so without synthesising a finding here, completing all five spec
  /// steps would leave the Generate button permanently disabled.
  void _setRom(
    WidgetRef ref,
    int index,
    DiscomfortAreaInput area,
    int pct,
  ) {
    ref.read(wizardDraftProvider.notifier).setRomPercent(area.bodyPart, pct);

    final notifier = ref.read(guidedAssessmentProvider.notifier);
    notifier.updateArea(index, area.copyWith(romLevel: romLevelFromPercent(pct)));

    final testName = romTestNameFor(area.bodyPart);
    final sensation = romSensationFromPercent(pct);
    final existing = ref.read(guidedAssessmentProvider).romFindings;
    final at = existing.indexWhere(
        (f) => f.bodyPart == area.bodyPart && f.testName == testName);
    final finding = RomFinding(
      testName: testName,
      bodyPart: area.bodyPart,
      sensation: sensation,
    );
    if (at >= 0) {
      // No `updateRomFinding` on the notifier — remove then add keeps this
      // additive rather than widening the provider's API.
      notifier.removeRomFinding(at);
    }
    notifier.addRomFinding(finding);
  }
}

// ---------------------------------------------------------------------------
// Step 3 · Daily Activities
// ---------------------------------------------------------------------------

class _StepActivities extends ConsumerWidget {
  final List<DailyActivityInput> selected;
  const _StepActivities({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = selected.map((e) => e.name).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in kDailyActivityOptions)
          WizardOptCard(
            label: option,
            multi: true,
            selected: names.contains(option),
            onTap: () {
              final notifier = ref.read(guidedAssessmentProvider.notifier);
              final idx = names.indexOf(option);
              if (idx >= 0) {
                notifier.removeActivity(idx);
              } else {
                // rank = 1-based selection order, matching the existing payload.
                notifier.addActivity(
                    DailyActivityInput(name: option, rank: names.length + 1));
              }
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 · Usual Sleep Posture
// ---------------------------------------------------------------------------

class _StepSleep extends ConsumerWidget {
  final SleepPosture? value;
  const _StepSleep({required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in SleepPosture.values)
          WizardOptCard(
            label: sleepPostureLabel(option),
            selected: value == option,
            onTap: () => ref
                .read(guidedAssessmentProvider.notifier)
                .setSleepPosture(option),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5 · Hardest position to tolerate
// ---------------------------------------------------------------------------

class _StepHardest extends ConsumerWidget {
  final HardPositionTolerance? value;
  const _StepHardest({required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: HwSpace.s3),
          child: Text(
            'Which position is hardest to tolerate for long?',
            style: TextStyle(fontSize: HwType.cap, color: p.ink2),
          ),
        ),
        for (final option in HardPositionTolerance.values)
          WizardOptCard(
            label: hardPositionLabel(option),
            selected: value == option,
            onTap: () => ref
                .read(guidedAssessmentProvider.notifier)
                .setHardestPosition(option),
          ),
      ],
    );
  }
}
