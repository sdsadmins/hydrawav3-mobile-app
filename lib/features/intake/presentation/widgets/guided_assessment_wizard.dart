import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ai_report/presentation/providers/ai_report_providers.dart';
import '../../domain/intake_enums.dart';
import '../../domain/intake_models.dart';
import '../providers/guided_assessment_provider.dart';
import 'body_map.dart';
import 'option_picker.dart';

const _worseningPresets = [
  'Sitting', 'Standing', 'Walking', 'Bending', 'Lifting', 'Twisting',
  'Lying down', 'Exercise', 'Stress', 'Cold weather',
];
const _improvingPresets = [
  'Rest', 'Movement', 'Heat', 'Ice', 'Stretching', 'Massage',
  'Medication', 'Sleep', 'Light exercise',
];

/// The 4-step Guided Assessment wizard (web parity). Shown inline on the
/// session setup screen when SessionType.guided is selected.
class GuidedAssessmentWizard extends ConsumerStatefulWidget {
  const GuidedAssessmentWizard({super.key});

  @override
  ConsumerState<GuidedAssessmentWizard> createState() =>
      _GuidedAssessmentWizardState();
}

class _GuidedAssessmentWizardState
    extends ConsumerState<GuidedAssessmentWizard> {
  int _step = 0;

  static const _titles = [
    'Area of Focus',
    'Range of Motion',
    'Daily Activities',
    'Final Remarks',
  ];

  bool _canAdvance(GuidedAssessmentData d) {
    switch (_step) {
      case 0:
        return d.discomfortAreas.isNotEmpty;
      case 1:
        return d.romFindings.isNotEmpty;
      case 2:
        return d.dailyActivities.isNotEmpty &&
            d.sleepPosture != null &&
            d.hardestPosition != null;
      default:
        return true;
    }
  }

  /// Kick generation off in the BACKGROUND and let the user keep working —
  /// progress + the finished report surface on the AI screen's status banner
  /// (web parity). No inline await, no forced navigation.
  void _generate() {
    final err = ref.read(aiReportGenerationProvider.notifier).startGenerate();
    if (!mounted) return;
    if (err != null) {
      context.showSnackBar(err, isError: true);
    } else {
      // Clear the assessment selections so the next report starts fresh
      // (startGenerate already snapshotted the intake for the background run).
      ref.read(guidedAssessmentProvider.notifier).reset();
      context.showSnackBar(
        'Generating AI report in the background — you can keep working. '
        'Track progress on the AI screen.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(guidedAssessmentProvider);
    final isLast = _step == _titles.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress chips
          Row(
            children: [
              for (var i = 0; i < _titles.length; i++) ...[
                _StepDot(index: i, active: i == _step, done: i < _step),
                if (i != _titles.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i < _step
                          ? ThemeConstants.accent
                          : ThemeConstants.border,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Step ${_step + 1} of ${_titles.length} · ${_titles[_step]}',
            style: TextStyle(
              color: ThemeConstants.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _buildStep(data),
          const SizedBox(height: 20),
          Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeConstants.textPrimary,
                      side: BorderSide(color: ThemeConstants.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Previous'),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                child: isLast
                    ? ElevatedButton(
                        // Non-blocking: kick off in the background and stay free
                        // to start another (web parity).
                        onPressed:
                            !data.canGenerateReport ? null : _generate,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Generate AI Report'),
                      )
                    : ElevatedButton(
                        onPressed: _canAdvance(data)
                            ? () => setState(() => _step++)
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Next'),
                      ),
              ),
            ],
          ),
          if (isLast && !data.canGenerateReport)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Complete Area of Focus, Range of Motion, Daily Activities, '
                'Sleep posture and Hardest position to generate a report.',
                style: TextStyle(
                  color: ThemeConstants.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep(GuidedAssessmentData data) {
    switch (_step) {
      case 0:
        return _AreaStep(data: data);
      case 1:
        return _RomStep(data: data);
      case 2:
        return _ActivitiesStep(data: data);
      default:
        return _RemarksStep(data: data);
    }
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool active;
  final bool done;
  const _StepDot({required this.index, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final filled = active || done;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: filled ? ThemeConstants.accent : ThemeConstants.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(
          color: filled ? ThemeConstants.accent : ThemeConstants.border,
        ),
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check_rounded,
              size: 16, color: ThemeConstants.onAccent)
          : Text(
              '${index + 1}',
              style: TextStyle(
                color: active
                    ? ThemeConstants.onAccent
                    : ThemeConstants.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

// ----------------------------------------------------------------------------
// Step 1 — Area of Focus
// ----------------------------------------------------------------------------
class _AreaStep extends ConsumerWidget {
  final GuidedAssessmentData data;
  const _AreaStep({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tap a body region to select it', style: _sectionLabel()),
        const SizedBox(height: 10),
        Builder(builder: (context) {
          final selected =
              data.discomfortAreas.map((a) => a.bodyPart).toList();
          void onSelect(String area) {
            // Toggle: tap to add (with defaults), tap again to remove.
            final existing =
                data.discomfortAreas.indexWhere((a) => a.bodyPart == area);
            if (existing >= 0) {
              notifier.removeArea(existing);
            } else {
              notifier.addArea(DiscomfortAreaInput(
                bodyPart: area,
                side: _sideEnumFor(area),
                discomfortBefore: 5,
              ));
            }
          }

          Widget view(String label, String forced) => Expanded(
                child: Column(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    BodyMap(
                      selectedAreas: selected,
                      onSelect: onSelect,
                      forcedView: forced,
                    ),
                  ],
                ),
              );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              view('Front View', 'front'),
              const SizedBox(width: 12),
              view('Back View', 'back'),
            ],
          );
        }),
        const SizedBox(height: 8),
        Text(
          'Tap a selected region again to remove it. Use the pencil to set '
          'pain level, range of motion and more.',
          style: TextStyle(color: ThemeConstants.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < data.discomfortAreas.length; i++)
          _itemCard(
            title: data.discomfortAreas[i].bodyPart,
            subtitle:
                '${data.discomfortAreas[i].side.label} · Pain ${data.discomfortAreas[i].discomfortBefore}→${data.discomfortAreas[i].discomfortAfter} · ${data.discomfortAreas[i].romLevel.label}',
            onEdit: () async {
              final edited = await _showAreaSheet(context,
                  existing: data.discomfortAreas[i]);
              if (edited != null) notifier.updateArea(i, edited);
            },
            onRemove: () => notifier.removeArea(i),
          ),
      ],
    );
  }
}

DiscomfortSide _sideEnumFor(String area) {
  switch (sideFromAreaName(area)) {
    case 'Left':
      return DiscomfortSide.left;
    case 'Right':
      return DiscomfortSide.right;
    default:
      return DiscomfortSide.both;
  }
}

// ----------------------------------------------------------------------------
// Step 2 — Range of Motion
// ----------------------------------------------------------------------------
class _RomStep extends ConsumerWidget {
  final GuidedAssessmentData data;
  const _RomStep({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < data.romFindings.length; i++)
          _itemCard(
            title: data.romFindings[i].testName,
            subtitle:
                '${data.romFindings[i].bodyPart} · ${data.romFindings[i].sensation}',
            onRemove: () => notifier.removeRomFinding(i),
          ),
        _addButton('Add movement finding', () async {
          final finding = await _showRomSheet(context);
          if (finding != null) notifier.addRomFinding(finding);
        }),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Step 3 — Daily Activities + posture/factors
// ----------------------------------------------------------------------------
class _ActivitiesStep extends ConsumerWidget {
  final GuidedAssessmentData data;
  const _ActivitiesStep({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily activities',
            style: _sectionLabel()),
        const SizedBox(height: 8),
        for (var i = 0; i < data.dailyActivities.length; i++)
          _itemCard(
            title: data.dailyActivities[i].name,
            subtitle: 'Rank ${data.dailyActivities[i].rank}',
            onRemove: () => notifier.removeActivity(i),
          ),
        _addButton('Add activity', () async {
          final a = await _showActivitySheet(context);
          if (a != null) notifier.addActivity(a);
        }),
        const SizedBox(height: 16),
        PickerField(
          label: 'Sleep posture',
          value: data.sleepPosture?.label,
          placeholder: 'Select sleep posture',
          onTap: () async {
            final v = await showOptionPicker<SleepPosture>(
              context,
              title: 'Sleep posture',
              options: SleepPosture.values,
              labelOf: (e) => e.label,
              selected: data.sleepPosture,
            );
            if (v != null) notifier.setSleepPosture(v);
          },
        ),
        const SizedBox(height: 12),
        PickerField(
          label: 'Hardest position to tolerate',
          value: data.hardestPosition?.label,
          placeholder: 'Select position',
          onTap: () async {
            final v = await showOptionPicker<HardPositionTolerance>(
              context,
              title: 'Hardest position',
              options: HardPositionTolerance.values,
              labelOf: (e) => e.label,
              selected: data.hardestPosition,
            );
            if (v != null) notifier.setHardestPosition(v);
          },
        ),
        const SizedBox(height: 12),
        PickerField(
          label: 'Hip tightness',
          value: data.hipTightness?.label,
          placeholder: 'Select (optional)',
          onTap: () async {
            final v = await showOptionPicker<HipTightness>(
              context,
              title: 'Hip tightness',
              options: HipTightness.values,
              labelOf: (e) => e.label,
              selected: data.hipTightness,
            );
            if (v != null) notifier.setHipTightness(v);
          },
        ),
        const SizedBox(height: 12),
        PickerField(
          label: 'Worsening factors',
          value: data.worseningFactors.isEmpty
              ? null
              : data.worseningFactors.join(', '),
          placeholder: 'Select factors (optional)',
          icon: Icons.tune_rounded,
          onTap: () async {
            final v = await showMultiSelectPicker(
              context,
              title: 'Worsening factors',
              options: _worseningPresets,
              selected: data.worseningFactors,
            );
            if (v != null) notifier.setWorseningFactors(v);
          },
        ),
        const SizedBox(height: 12),
        PickerField(
          label: 'Improving factors',
          value: data.improvingFactors.isEmpty
              ? null
              : data.improvingFactors.join(', '),
          placeholder: 'Select factors (optional)',
          icon: Icons.tune_rounded,
          onTap: () async {
            final v = await showMultiSelectPicker(
              context,
              title: 'Improving factors',
              options: _improvingPresets,
              selected: data.improvingFactors,
            );
            if (v != null) notifier.setImprovingFactors(v);
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Step 4 — Final remarks
// ----------------------------------------------------------------------------
class _RemarksStep extends ConsumerWidget {
  final GuidedAssessmentData data;
  const _RemarksStep({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Anything else to note?', style: _sectionLabel()),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: data.missingRemark,
          maxLines: 4,
          style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
          onChanged: notifier.setMissingRemark,
          decoration: InputDecoration(
            hintText: 'Optional final remarks for the report…',
            hintStyle: TextStyle(color: ThemeConstants.textTertiary),
            filled: true,
            fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.accent),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Shared bits -----------------------------------------------------------

TextStyle _sectionLabel() => TextStyle(
      color: ThemeConstants.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );

Widget _itemCard({
  required String title,
  required String subtitle,
  VoidCallback? onEdit,
  required VoidCallback onRemove,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: ThemeConstants.surfaceVariant.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ThemeConstants.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined,
                size: 18, color: ThemeConstants.textTertiary),
          ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: ThemeConstants.error),
        ),
      ],
    ),
  );
}

Widget _addButton(String label, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeConstants.accent,
          side: BorderSide(color: ThemeConstants.accent),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        label: Text(label),
      ),
    ),
  );
}

// ---- Add/edit sheets -------------------------------------------------------

Future<DiscomfortAreaInput?> _showAreaSheet(
  BuildContext context, {
  DiscomfortAreaInput? existing,
}) {
  return showModalBottomSheet<DiscomfortAreaInput>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _AreaSheet(existing: existing),
  );
}

class _AreaSheet extends StatefulWidget {
  final DiscomfortAreaInput? existing;
  const _AreaSheet({this.existing});

  @override
  State<_AreaSheet> createState() => _AreaSheetState();
}

class _AreaSheetState extends State<_AreaSheet> {
  late final TextEditingController _bodyPart;
  late final TextEditingController _notes;
  late DiscomfortSide _side;
  late RomLevel _rom;
  late DiscomfortBehavior _behavior;
  late TemporalDuration _duration;
  late double _before;
  late double _after;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _bodyPart = TextEditingController(text: e?.bodyPart ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _side = e?.side ?? DiscomfortSide.both;
    _rom = e?.romLevel ?? RomLevel.normal;
    _behavior = e?.behavior ?? DiscomfortBehavior.comesAndGoes;
    _duration = e?.temporalDuration ?? TemporalDuration.lessThan6Weeks;
    _before = (e?.discomfortBefore ?? 0).toDouble();
    _after = (e?.discomfortAfter ?? 0).toDouble();
  }

  @override
  void dispose() {
    _bodyPart.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Area of focus',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary)),
            const SizedBox(height: 16),
            _textField('Body part', _bodyPart, hint: 'e.g. Lower back'),
            const SizedBox(height: 12),
            PickerField(
              label: 'Side',
              value: _side.label,
              onTap: () async {
                final v = await showOptionPicker<DiscomfortSide>(context,
                    title: 'Side',
                    options: DiscomfortSide.values,
                    labelOf: (e) => e.label,
                    selected: _side);
                if (v != null) setState(() => _side = v);
              },
            ),
            const SizedBox(height: 16),
            _slider('Pain before', _before, (v) => setState(() => _before = v)),
            _slider('Pain after', _after, (v) => setState(() => _after = v)),
            const SizedBox(height: 8),
            PickerField(
              label: 'Range of motion',
              value: _rom.label,
              onTap: () async {
                final v = await showOptionPicker<RomLevel>(context,
                    title: 'Range of motion',
                    options: RomLevel.values,
                    labelOf: (e) => e.label,
                    selected: _rom);
                if (v != null) setState(() => _rom = v);
              },
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Behavior',
              value: _behavior.label,
              onTap: () async {
                final v = await showOptionPicker<DiscomfortBehavior>(context,
                    title: 'Behavior',
                    options: DiscomfortBehavior.values,
                    labelOf: (e) => e.label,
                    selected: _behavior);
                if (v != null) setState(() => _behavior = v);
              },
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Duration',
              value: _duration.label,
              onTap: () async {
                final v = await showOptionPicker<TemporalDuration>(context,
                    title: 'Duration',
                    options: TemporalDuration.values,
                    labelOf: (e) => e.label,
                    selected: _duration);
                if (v != null) setState(() => _duration = v);
              },
            ),
            const SizedBox(height: 12),
            _textField('Notes', _notes, hint: 'Optional'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final bp = _bodyPart.text.trim();
                  if (bp.isEmpty) return;
                  Navigator.of(context).pop(DiscomfortAreaInput(
                    bodyPart: bp,
                    side: _side,
                    discomfortBefore: _before.round(),
                    discomfortAfter: _after.round(),
                    romLevel: _rom,
                    behavior: _behavior,
                    temporalDuration: _duration,
                    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  ));
                },
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(), style: _sectionLabel()),
            Text('${value.round()}',
                style: TextStyle(
                    color: ThemeConstants.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 10,
          divisions: 10,
          activeColor: ThemeConstants.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

Future<RomFinding?> _showRomSheet(BuildContext context) {
  return showModalBottomSheet<RomFinding>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final test = TextEditingController();
      final body = TextEditingController();
      final sensation = TextEditingController();
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Movement finding',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary)),
              const SizedBox(height: 16),
              _textField('Test name', test, hint: 'e.g. Shoulder flexion'),
              const SizedBox(height: 12),
              _textField('Body part', body, hint: 'e.g. Shoulder'),
              const SizedBox(height: 12),
              _textField('Sensation', sensation,
                  hint: 'e.g. Tightness, sharp pain'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    if (test.text.trim().isEmpty ||
                        body.text.trim().isEmpty ||
                        sensation.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.of(ctx).pop(RomFinding(
                      testName: test.text.trim(),
                      bodyPart: body.text.trim(),
                      sensation: sensation.text.trim(),
                    ));
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<DailyActivityInput?> _showActivitySheet(BuildContext context) {
  return showModalBottomSheet<DailyActivityInput>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final name = TextEditingController();
      double rank = 1;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily activity',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ThemeConstants.textPrimary)),
                const SizedBox(height: 16),
                _textField('Activity', name, hint: 'e.g. Desk work'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('PRIORITY RANK', style: _sectionLabel()),
                    Text('${rank.round()}',
                        style: TextStyle(
                            color: ThemeConstants.accent,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  value: rank,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: ThemeConstants.accent,
                  onChanged: (v) => setSheet(() => rank = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (name.text.trim().isEmpty) return;
                      Navigator.of(ctx).pop(DailyActivityInput(
                        name: name.text.trim(),
                        rank: rank.round(),
                      ));
                    },
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _textField(String label, TextEditingController controller,
    {String? hint}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _sectionLabel()),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: ThemeConstants.textTertiary),
          filled: true,
          fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ThemeConstants.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ThemeConstants.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ThemeConstants.accent),
          ),
        ),
      ),
    ],
  );
}
