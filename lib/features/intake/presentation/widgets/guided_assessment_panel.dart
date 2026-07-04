import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/extensions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../ai_report/data/ai_report_repository.dart';
import '../../../ai_report/presentation/providers/ai_report_providers.dart';
import '../../domain/intake_enums.dart';
import '../../domain/intake_models.dart';
import '../providers/guided_assessment_provider.dart';
import '../providers/rom_body_parts_provider.dart';
import 'body_map.dart';

// --- Web-parity option lists (exact labels/values) -------------------------

const _behaviorOptions = [
  'Always Present',
  'Comes and Goes',
  'Only with certain Activities',
  'Varies day to day',
];
const _durationOptions = [
  'Less than 6 weeks',
  '6 weeks to 3 months',
  '3 to 6 months',
  '6 months to 1 year',
  'More than 1 year',
];
const _romTests = [
  ('Forward Bend', 'assets/images/ROM_Forward_Bend.png', 'Lower back/Pelvis'),
  ('Squat', 'assets/images/ROM_Squat.png', 'Knees'),
  ('Trunk Rotation', 'assets/images/ROM_Trunk_Rotation.png',
      'Mid-back/Thoracic Spine'),
  ('Ankle Dorsiflexion', 'assets/images/ROM_Ankle_Dorsiflextion.png',
      'Ankles/lower leg'),
  ('Shoulder Flexion', 'assets/images/ROM_Shoulder_Flexion.png', 'Shoulders'),
  ('Neck Flexion', 'assets/images/ROM_Neck_Flexion.png', 'Neck/Cervical Spine'),
  ('Neck Rotation', 'assets/images/ROM_Neck_Rotation.png',
      'Neck/Cervical Spine'),
  ('Manual Entry', '', 'CUSTOM TEST'),
];
const _sensationOptions = [
  'Tight',
  'Stiff',
  'Achy',
  'Heavy or fatigued',
  'Sharp',
  'Burning',
  'Tingling',
  'Numb',
  'Manual Entry',
];
const _presetActivities = [
  'OFFICE / DESK WORK',
  'STANDING WORK',
  'MANUAL WORK',
  'SPORTS / TRAINING',
  'YOGA / MOBILITY',
  'RUNNING / CYCLING',
  'PROLONGED DRIVING',
];
const _worseningPresets = [
  'Sitting >30 min',
  'Standing >30 min',
  'Getting up from sitting',
  'Walking',
  'Stairs',
  'Bending backward',
  'Twisting',
  'Reaching',
  'Morning',
  'End of day',
  'During exercise',
  'After exercise',
  'None',
  'Not sure',
];
const _improvingPresets = [
  'Sitting',
  'Standing and moving',
  'Walking',
  'Stretching',
  'Knees-to-chest',
  'Heat',
  'Cold',
  'Gentle movement',
  'Massage',
  'Changing positions',
  'Rest',
  'Exercise',
  'Nothing yet',
];

// ---------------------------------------------------------------------------

/// Guided Assessment as 4 steps, each opened in a bottom sheet (web parity).
class GuidedAssessmentPanel extends ConsumerStatefulWidget {
  const GuidedAssessmentPanel({super.key});

  @override
  ConsumerState<GuidedAssessmentPanel> createState() =>
      _GuidedAssessmentPanelState();
}

class _GuidedAssessmentPanelState
    extends ConsumerState<GuidedAssessmentPanel> {
  final PageController _pageController = PageController();
  // Page index lives in a ValueNotifier so swiping only rebuilds the small
  // indicator row — not the whole panel (which caused a flicker).
  final ValueNotifier<int> _page = ValueNotifier<int>(0);

  @override
  void dispose() {
    _pageController.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(guidedAssessmentProvider);

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'GUIDED ASSESSMENT',
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'View latest report',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openLatestReport(context, ref),
                icon: Icon(Icons.description_outlined,
                    size: 20, color: ThemeConstants.textSecondary),
              ),
              IconButton(
                tooltip: 'Report history',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final client = ref.read(selectedClientProvider);
                  final isGuest = ref.read(sessionClientModeProvider) ==
                      ClientMode.guest;
                  if (!isGuest && client != null) {
                    context.pushNamed(RouteNames.aiReports, extra: {
                      'clientId': client.id,
                      'title': client.displayName,
                    });
                  } else {
                    context.pushNamed(RouteNames.aiReportClients);
                  }
                },
                icon: Icon(Icons.history_rounded,
                    size: 20, color: ThemeConstants.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 84,
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => _page.value = i,
              children: [
                _stepCard(
                  context,
                  index: 1,
                  title: 'Area of Focus',
                  subtitle: data.discomfortAreas.isEmpty
                      ? 'Select areas on the body'
                      : '${data.discomfortAreas.length} area(s) selected',
                  done: data.discomfortAreas.isNotEmpty,
                  onTap: () => _openStep(context,
                      index: 1, sheet: const _AreaOfFocusSheet()),
                ),
                _stepCard(
                  context,
                  index: 2,
                  title: 'Range of Motion',
                  subtitle: data.romFindings.isEmpty
                      ? 'Record movement findings'
                      : '${data.romFindings.length} finding(s)',
                  done: data.romFindings.isNotEmpty,
                  onTap: () =>
                      _openStep(context, index: 2, sheet: const _RomSheet()),
                ),
                _stepCard(
                  context,
                  index: 3,
                  title: 'Daily Activities',
                  subtitle: (data.dailyActivities.isNotEmpty &&
                          data.sleepPosture != null &&
                          data.hardestPosition != null)
                      ? '${data.dailyActivities.length} activities'
                      : 'Activities, posture & factors',
                  done: data.dailyActivities.isNotEmpty &&
                      data.sleepPosture != null &&
                      data.hardestPosition != null,
                  onTap: () => _openStep(context,
                      index: 3, sheet: const _DailyActivitiesSheet()),
                ),
                _stepCard(
                  context,
                  index: 4,
                  title: 'Final Remarks',
                  subtitle: (data.missingRemark?.trim().isNotEmpty ?? false)
                      ? 'Added'
                      : 'Optional',
                  done: data.missingRemark?.trim().isNotEmpty ?? false,
                  onTap: () => _openStep(context,
                      index: 4, sheet: const _RemarksSheet()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Numbered position indicator (tracks the carousel — like dots,
          // but numbers).
          ValueListenableBuilder<int>(
            valueListenable: _page,
            builder: (context, page, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++) _pageIndicator(i, page),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // Background generation: kick it off and let the top banner track
              // it — the assessment stays free and you can start another while
              // one is running (web parity).
              onPressed: !data.canGenerateReport
                  ? null
                  : () {
                      final err = ref
                          .read(aiReportGenerationProvider.notifier)
                          .startGenerate();
                      context.showSnackBar(
                        err ??
                            'Generating AI report — you can keep working. '
                                'Track progress above.',
                        isError: err != null,
                      );
                    },
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Generate AI Report'),
            ),
          ),
          if (!data.canGenerateReport)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Complete Area of Focus, Range of Motion, Daily Activities, '
                'Sleep posture and Hardest position to generate a report.',
                style:
                    TextStyle(color: ThemeConstants.textTertiary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Open the latest report: the just-generated one if present, else the most
  /// recent persisted report (recent — client: by user+org, guest: org only).
  Future<void> _openLatestReport(BuildContext context, WidgetRef ref) async {
    final lastDone =
        ref.read(aiReportGenerationProvider.notifier).lastDoneReport;
    if (lastDone != null) {
      context.pushNamed(RouteNames.aiReport, extra: lastDone);
      return;
    }
    final auth = ref.read(authStateProvider);
    final orgId = int.tryParse(auth.selectedOrgId ?? '');
    final isGuest =
        ref.read(sessionClientModeProvider) == ClientMode.guest;
    try {
      final report = await ref.read(aiReportRepositoryProvider).recent(
            userId: isGuest ? null : auth.user?.id,
            organizationId: orgId,
          );
      if (!context.mounted) return;
      if (report != null) {
        context.pushNamed(RouteNames.aiReport, extra: report);
      } else {
        context.showSnackBar('No report found yet.', isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Failed to load report: $e', isError: true);
      }
    }
  }

  /// Open a step's sheet and, once it closes, auto-advance the carousel to the
  /// next step if this one is now complete (so the practitioner isn't forced to
  /// manually swipe after finishing each step).
  Future<void> _openStep(
    BuildContext context, {
    required int index,
    required Widget sheet,
  }) async {
    await _openSheet(context, sheet);
    if (!mounted) return;
    // `index` is 1-based; the next page's 0-based position equals `index`.
    if (index < 4 && _isStepDone(index)) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Whether the given 1-based step is complete (mirrors each step card's
  /// `done` condition), used to gate the auto-advance.
  bool _isStepDone(int index) {
    final d = ref.read(guidedAssessmentProvider);
    switch (index) {
      case 1:
        return d.discomfortAreas.isNotEmpty;
      case 2:
        return d.romFindings.isNotEmpty;
      case 3:
        return d.dailyActivities.isNotEmpty &&
            d.sleepPosture != null &&
            d.hardestPosition != null;
      case 4:
        return d.missingRemark?.trim().isNotEmpty ?? false;
      default:
        return false;
    }
  }

  /// Numbered position indicator below the carousel (active page filled with
  /// accent). Tapping jumps to that page.
  Widget _pageIndicator(int i, int current) {
    final active = current == i;
    return GestureDetector(
      onTap: () => _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: active ? 30 : 26,
        height: active ? 30 : 26,
        decoration: BoxDecoration(
          color:
              active ? ThemeConstants.accent : ThemeConstants.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(
              color: active ? ThemeConstants.accent : ThemeConstants.border),
        ),
        alignment: Alignment.center,
        child: Text('${i + 1}',
            style: TextStyle(
                color: active
                    ? ThemeConstants.onAccent
                    : ThemeConstants.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _stepCard(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onTap,
  }) {
    // Full-width card (one per carousel page), styled like the "Available
    // WiFi Devices" cards (_AvailableDeviceRow).
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: done ? ThemeConstants.accent : ThemeConstants.border,
            width: done ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            // Number indicator (filled with accent once the step is complete).
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: done
                    ? ThemeConstants.accent
                    : ThemeConstants.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color:
                        done ? ThemeConstants.accent : ThemeConstants.border),
              ),
              alignment: Alignment.center,
              child: Text('$index',
                  style: TextStyle(
                      color: done
                          ? ThemeConstants.onAccent
                          : ThemeConstants.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 12,
                          height: 1.2)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded,
                color: ThemeConstants.textTertiary),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => child,
  );
}

/// Common sheet shell: title, scrollable body, Done button.
class _SheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary)),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared bits -----------------------------------------------------------

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
            color: ThemeConstants.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          )),
    );

/// Wraps a section in a themed card with an optional (larger) title.
Widget _sectionCard({String? title, required Widget child}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title,
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  )),
            ),
          child,
        ],
      ),
    );

Widget _chip(String label, bool selected, VoidCallback onTap) {
  return InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? ThemeConstants.segmentActiveBg
            : ThemeConstants.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: selected ? ThemeConstants.segmentActiveBg : ThemeConstants.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ThemeConstants.onNav : ThemeConstants.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

// =====================  STEP 1: AREA OF FOCUS  =============================

class _AreaOfFocusSheet extends ConsumerWidget {
  const _AreaOfFocusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(guidedAssessmentProvider);
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    final selected = data.discomfortAreas.map((a) => a.bodyPart).toList();

    void onSelect(String area) {
      final i = data.discomfortAreas.indexWhere((a) => a.bodyPart == area);
      if (i >= 0) {
        notifier.removeArea(i);
      } else {
        notifier.addArea(DiscomfortAreaInput(
          bodyPart: area,
          side: _sideFor(area),
          discomfortBefore: 5,
          romLevel: RomLevel.moderate,
        ));
      }
    }

    Widget view(String label, String forced) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6)),
              const SizedBox(height: 6),
              BodyMap(
                  selectedAreas: selected,
                  onSelect: onSelect,
                  forcedView: forced),
            ],
          ),
        );

    return _SheetShell(
      title: 'Area of Focus',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            title: 'Select Areas',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                view('FRONT VIEW', 'front'),
                const SizedBox(width: 12),
                view('BACK VIEW', 'back'),
              ],
            ),
          ),
          if (data.discomfortAreas.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: ThemeConstants.border,
                    style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.touch_app_outlined,
                      color: ThemeConstants.textTertiary, size: 32),
                  const SizedBox(height: 8),
                  Text('No Areas Selected',
                      style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Interact with the body map to populate this area.',
                      style: TextStyle(
                          color: ThemeConstants.textTertiary, fontSize: 11)),
                ],
              ),
            )
          else
            for (var i = 0; i < data.discomfortAreas.length; i++)
              _AreaCard(
                index: i,
                area: data.discomfortAreas[i],
                onChanged: (a) => notifier.updateArea(i, a),
                onRemove: () => notifier.removeArea(i),
              ),
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  final int index;
  final DiscomfortAreaInput area;
  final ValueChanged<DiscomfortAreaInput> onChanged;
  final VoidCallback onRemove;

  const _AreaCard({
    required this.index,
    required this.area,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(area.bodyPart,
                    style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(index == 0 ? 'PRIMARY' : 'SECONDARY',
                    style: TextStyle(
                        color: ThemeConstants.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6)),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: ThemeConstants.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Discomfort Level'),
              Text('${area.discomfortBefore}',
                  style: TextStyle(
                      color: ThemeConstants.accent,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(
            value: area.discomfortBefore.clamp(1, 10).toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: ThemeConstants.accent,
            onChanged: (v) =>
                onChanged(area.copyWith(discomfortBefore: v.round())),
          ),
          const SizedBox(height: 4),
          _label('Behavior'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _behaviorOptions
                .map((o) => _chip(o, area.behavior.value == o,
                    () => onChanged(area.copyWith(behavior: _behaviorFrom(o)))))
                .toList(),
          ),
          const SizedBox(height: 12),
          _label('Duration'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durationOptions
                .map((o) => _chip(o, area.temporalDuration.value == o,
                    () => onChanged(
                        area.copyWith(temporalDuration: _durationFrom(o)))))
                .toList(),
          ),
          const SizedBox(height: 12),
          _label('Notes'),
          TextFormField(
            initialValue: area.notes,
            maxLines: 2,
            style:
                TextStyle(color: ThemeConstants.textPrimary, fontSize: 13),
            onChanged: (v) => onChanged(area.copyWith(notes: v)),
            decoration: _inputDecoration('Specific observation notes...'),
          ),
        ],
      ),
    );
  }
}

// =====================  STEP 2: RANGE OF MOTION  ===========================

class _RomSheet extends ConsumerStatefulWidget {
  const _RomSheet();

  @override
  ConsumerState<_RomSheet> createState() => _RomSheetState();
}

class _RomSheetState extends ConsumerState<_RomSheet> {
  String _activeTest = _romTests.first.$1;
  final _manualTest = TextEditingController();
  final _manualSensation = TextEditingController();
  String? _bodyPart;
  String _side = 'BOTH';
  String _position = 'BOTH';
  final Set<String> _sensations = {'Tight'};

  @override
  void dispose() {
    _manualTest.dispose();
    _manualSensation.dispose();
    super.dispose();
  }

  void _addFinding() {
    if (_bodyPart == null || _bodyPart!.isEmpty) return;
    final loc = <String>[];
    if (_side != 'BOTH') loc.add(_side);
    if (_position != 'BOTH') loc.add(_position);
    final locStr = loc.isEmpty ? 'BOTH' : loc.join(' ');
    final sensations = _sensations.where((s) => s != 'Manual Entry').toList();
    if (_sensations.contains('Manual Entry') &&
        _manualSensation.text.trim().isNotEmpty) {
      sensations.add(_manualSensation.text.trim());
    }
    final testName = _activeTest == 'Manual Entry'
        ? (_manualTest.text.trim().isEmpty ? 'Custom Test' : _manualTest.text.trim())
        : _activeTest;
    ref.read(guidedAssessmentProvider.notifier).addRomFinding(RomFinding(
          testName: testName,
          bodyPart: '$_bodyPart - $locStr',
          sensation: sensations.join(','),
        ));
    setState(() {
      _bodyPart = null;
      _side = 'BOTH';
      _position = 'BOTH';
      _sensations
        ..clear()
        ..add('Tight');
      _manualSensation.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(guidedAssessmentProvider);
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    final bodyPartsAsync = ref.watch(romBodyPartsProvider);

    return _SheetShell(
      title: 'Range of Motion',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Test cards
          _sectionCard(
            title: 'Movement Test',
            child: SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _romTests.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final t = _romTests[i];
                final active = _activeTest == t.$1;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _activeTest = t.$1),
                  child: Container(
                    width: 120,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: active
                          ? ThemeConstants.segmentActiveBg
                          : ThemeConstants.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: active
                              ? ThemeConstants.segmentActiveBg
                              : ThemeConstants.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: t.$2.isEmpty
                              ? Icon(Icons.settings_rounded,
                                  size: 40,
                                  color: active
                                      ? ThemeConstants.onNav
                                      : ThemeConstants.textSecondary)
                              : Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(4),
                                  child: Image.asset(t.$2, fit: BoxFit.contain),
                                ),
                        ),
                        const SizedBox(height: 6),
                        Text(t.$1,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                                color: active
                                    ? ThemeConstants.onNav
                                    : ThemeConstants.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                );
              },
            ),
          )),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text('Record Finding for $_activeTest',
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (_activeTest == 'Manual Entry') ...[
            _label('Test Name'),
            TextField(
              controller: _manualTest,
              style:
                  TextStyle(color: ThemeConstants.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Enter custom test name...'),
            ),
            const SizedBox(height: 12),
          ],
          _label('Impacted Body Part'),
          bodyPartsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text('Failed to load body parts',
                style: TextStyle(color: ThemeConstants.error, fontSize: 12)),
            data: (parts) => _PickerRow(
              value: _bodyPart,
              placeholder: 'Select Affected Part',
              onTap: () async {
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  backgroundColor: ThemeConstants.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  builder: (ctx) => _SimpleListSheet(
                      title: 'Impacted Body Part', options: parts),
                );
                if (picked != null) setState(() => _bodyPart = picked);
              },
            ),
          ),
          if (_bodyPart != null) ...[
            const SizedBox(height: 12),
            _label('Side'),
            _Segmented(
              options: const ['LEFT', 'BOTH', 'RIGHT'],
              value: _side,
              onChanged: (v) => setState(() => _side = v),
            ),
            const SizedBox(height: 12),
            _label('Position'),
            _Segmented(
              options: const ['FRONT', 'BOTH', 'BACK'],
              value: _position,
              onChanged: (v) => setState(() => _position = v),
            ),
          ],
          const SizedBox(height: 12),
          _label('Sensation'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sensationOptions
                .map((o) => _chip(
                      o == 'Heavy or fatigued' ? 'HEAVY/FATIGUED' : o.toUpperCase(),
                      _sensations.contains(o),
                      () => setState(() {
                        if (_sensations.contains(o)) {
                          _sensations.remove(o);
                        } else {
                          _sensations.add(o);
                        }
                      }),
                    ))
                .toList(),
          ),
          if (_sensations.contains('Manual Entry')) ...[
            const SizedBox(height: 10),
            _label('Custom Sensation'),
            TextField(
              controller: _manualSensation,
              style:
                  TextStyle(color: ThemeConstants.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Enter custom sensation'),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _bodyPart == null ? null : _addFinding,
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeConstants.accent,
                side: BorderSide(color: ThemeConstants.accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('+ Add Finding'),
            ),
          ),
              ],
            ),
          ),
          if (data.romFindings.isNotEmpty)
            _sectionCard(
              title: 'Recorded findings for session',
              child: Column(
                children: [
                  for (var i = 0; i < data.romFindings.length; i++)
                    Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
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
                          Text(data.romFindings[i].testName.toUpperCase(),
                              style: TextStyle(
                                  color: ThemeConstants.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(data.romFindings[i].bodyPart,
                              style: TextStyle(
                                  color: ThemeConstants.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          if (data.romFindings[i].sensation.isNotEmpty)
                            Text(
                                data.romFindings[i].sensation
                                    .split(',')
                                    .join(' · '),
                                style: TextStyle(
                                    color: ThemeConstants.textSecondary,
                                    fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => notifier.removeRomFinding(i),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: ThemeConstants.error),
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =====================  STEP 3: DAILY ACTIVITIES  =========================

class _DailyActivitiesSheet extends ConsumerStatefulWidget {
  const _DailyActivitiesSheet();

  @override
  ConsumerState<_DailyActivitiesSheet> createState() =>
      _DailyActivitiesSheetState();
}

class _DailyActivitiesSheetState
    extends ConsumerState<_DailyActivitiesSheet> {
  final _manualActivity = TextEditingController();
  final _manualWorse = TextEditingController();
  final _manualImprove = TextEditingController();

  @override
  void dispose() {
    _manualActivity.dispose();
    _manualWorse.dispose();
    _manualImprove.dispose();
    super.dispose();
  }

  void _toggleActivity(String name) {
    final data = ref.read(guidedAssessmentProvider);
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    final i = data.dailyActivities.indexWhere((a) => a.name == name);
    if (i >= 0) {
      notifier.removeActivity(i);
    } else {
      final ranks = data.dailyActivities.map((a) => a.rank).toList();
      final next = ranks.isEmpty
          ? 1
          : (ranks.reduce((a, b) => a > b ? a : b) + 1);
      notifier.addActivity(DailyActivityInput(name: name, rank: next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(guidedAssessmentProvider);
    final notifier = ref.read(guidedAssessmentProvider.notifier);
    final ranked = [...data.dailyActivities]
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return _SheetShell(
      title: 'Daily Activities',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ThemeConstants.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: ThemeConstants.info.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: ThemeConstants.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Activity Ranking: prioritized from most time spent (1) to least.',
                    style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Daily Activities',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presetActivities
                      .map((a) => _chip(
                          a,
                          data.dailyActivities.any((x) => x.name == a),
                          () => _toggleActivity(a)))
                      .toList(),
                ),
                const SizedBox(height: 10),
                _ManualAdd(
                  controller: _manualActivity,
                  hint: 'Manual entry...',
                  onAdd: (v) {
                    if (data.dailyActivities.any((x) => x.name == v)) return;
                    _toggleActivity(v);
                  },
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Ranked Priority (Most to Least)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ranked.isEmpty)
                  Text('No items ranked',
                      style: TextStyle(
                          color: ThemeConstants.textTertiary, fontSize: 12))
                else
                  for (final a in ranked)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surfaceVariant
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: ThemeConstants.accent,
                            child: Text('${a.rank}',
                                style: TextStyle(
                                    color: ThemeConstants.onAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(a.name,
                                style: TextStyle(
                                    color: ThemeConstants.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                          InkWell(
                            onTap: () {
                              final idx = data.dailyActivities
                                  .indexWhere((x) => x.name == a.name);
                              if (idx >= 0) notifier.removeActivity(idx);
                            },
                            child: Icon(Icons.close_rounded,
                                size: 18, color: ThemeConstants.textTertiary),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Usual Sleep Posture',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SleepPosture.values
                  .map((p) => _chip(p.value.toUpperCase(),
                      data.sleepPosture == p,
                      () => notifier.setSleepPosture(p)))
                  .toList(),
            ),
          ),
          _sectionCard(
            title: 'Factor Synthesis',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('What activities make primary discomfort worse?'),
                _FactorChips(
                  presets: _worseningPresets,
                  selected: data.worseningFactors,
                  controller: _manualWorse,
                  onChanged: notifier.setWorseningFactors,
                ),
                const SizedBox(height: 16),
                _label('What activities make primary discomfort better?'),
                _FactorChips(
                  presets: _improvingPresets,
                  selected: data.improvingFactors,
                  controller: _manualImprove,
                  onChanged: notifier.setImprovingFactors,
                ),
                const SizedBox(height: 16),
                _label('Which position is harder to tolerate overall?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: HardPositionTolerance.values
                      .map((p) => _chip(p.value.toUpperCase(),
                          data.hardestPosition == p,
                          () => notifier.setHardestPosition(p)))
                      .toList(),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Do you feel tightness in the front of your hips?',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HipTightness.values
                  .map((h) => _chip(h.value.toUpperCase(),
                      data.hipTightness == h,
                      () => notifier.setHipTightness(h)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================  STEP 4: FINAL REMARKS  ============================

class _RemarksSheet extends ConsumerStatefulWidget {
  const _RemarksSheet();

  @override
  ConsumerState<_RemarksSheet> createState() => _RemarksSheetState();
}

class _RemarksSheetState extends ConsumerState<_RemarksSheet> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: ref.read(guidedAssessmentProvider).missingRemark);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Final Remarks',
      child: _sectionCard(
        title: 'Anything else to note?',
        child: TextField(
          controller: _c,
          maxLines: 5,
          style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
          onChanged: (v) =>
              ref.read(guidedAssessmentProvider.notifier).setMissingRemark(v),
          decoration:
              _inputDecoration('Optional final remarks for the report...'),
        ),
      ),
    );
  }
}

// --- Small shared widgets --------------------------------------------------

class _Segmented extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  const _Segmented(
      {required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: options.map((o) {
          final active = value == o;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color:
                      active ? ThemeConstants.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: active
                      ? Border.all(color: ThemeConstants.border)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(o,
                    style: TextStyle(
                        color: active
                            ? ThemeConstants.textPrimary
                            : ThemeConstants.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  const _PickerRow(
      {required this.value, required this.placeholder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(has ? value! : placeholder,
                  style: TextStyle(
                      color: has
                          ? ThemeConstants.textPrimary
                          : ThemeConstants.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: ThemeConstants.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SimpleListSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  const _SimpleListSheet({required this.title, required this.options});

  @override
  State<_SimpleListSheet> createState() => _SimpleListSheetState();
}

class _SimpleListSheetState extends State<_SimpleListSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = _q.isEmpty
        ? widget.options
        : widget.options
            .where((o) => o.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary)),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style:
                    TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
                decoration: _inputDecoration('Search...'),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No matches',
                            style: TextStyle(
                                color: ThemeConstants.textSecondary)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: ThemeConstants.border),
                        itemBuilder: (ctx, i) => ListTile(
                          title: Text(list[i],
                              style: TextStyle(
                                  color: ThemeConstants.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          onTap: () => Navigator.of(ctx).pop(list[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualAdd extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onAdd;
  const _ManualAdd(
      {required this.controller, required this.hint, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    void submit() {
      final v = controller.text.trim();
      if (v.isEmpty) return;
      onAdd(v);
      controller.clear();
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 13),
            onSubmitted: (_) => submit(),
            decoration: _inputDecoration(hint),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: submit,
          icon: Icon(Icons.add_circle_rounded, color: ThemeConstants.accent),
        ),
      ],
    );
  }
}

class _FactorChips extends StatelessWidget {
  final List<String> presets;
  final List<String> selected;
  final TextEditingController controller;
  final ValueChanged<List<String>> onChanged;
  const _FactorChips({
    required this.presets,
    required this.selected,
    required this.controller,
    required this.onChanged,
  });

  void _toggle(String f) {
    final next = [...selected];
    if (next.contains(f)) {
      next.remove(f);
    } else {
      next.add(f);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      ...presets,
      ...selected.where((s) => !presets.contains(s)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: all
              .map((f) => _chip(f, selected.contains(f), () => _toggle(f)))
              .toList(),
        ),
        const SizedBox(height: 10),
        _ManualAdd(
          controller: controller,
          hint: 'Manual entry...',
          onAdd: (v) {
            if (!selected.contains(v)) onChanged([...selected, v]);
          },
        ),
      ],
    );
  }
}

// --- helpers ---------------------------------------------------------------

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: ThemeConstants.textTertiary),
      filled: true,
      fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );

DiscomfortSide _sideFor(String area) {
  switch (sideFromAreaName(area)) {
    case 'Left':
      return DiscomfortSide.left;
    case 'Right':
      return DiscomfortSide.right;
    default:
      return DiscomfortSide.both;
  }
}

DiscomfortBehavior _behaviorFrom(String v) =>
    DiscomfortBehavior.values.firstWhere((e) => e.value == v,
        orElse: () => DiscomfortBehavior.comesAndGoes);

TemporalDuration _durationFrom(String v) =>
    TemporalDuration.values.firstWhere((e) => e.value == v,
        orElse: () => TemporalDuration.lessThan6Weeks);
