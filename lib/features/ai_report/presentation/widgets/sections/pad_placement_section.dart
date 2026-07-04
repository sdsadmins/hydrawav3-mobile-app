import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../session_plan/domain/session_plan.dart';
import '../../../../session_plan/presentation/providers/session_plan_provider.dart';
import '../../ai_report_style.dart';
import '../report_widgets.dart';

/// Focus-area names for pad placement, preferring the persisted intake's
/// discomfort areas and falling back to the AI's recommended focus areas.
List<String> padPlacementAreas(Map<String, dynamic> report) {
  final intake = RW.asMap(report['intakeData']);
  final fromIntake = [
    for (final a in RW.asMapList(intake['discomfort_areas']))
      RW.str(a, 'body_area'),
  ].where((s) => s.isNotEmpty).toList();
  if (fromIntake.isNotEmpty) return fromIntake.toSet().toList();

  final nextSteps = RW.asMap(report['next_steps']);
  return RW.asStrList(nextSteps['recommended_focus_areas']).toSet().toList();
}

/// The gradient "AI PAD PLACEMENT" card shell shared by the live + static
/// variants.
Widget _padShell({required List<Widget> children}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HydraReport.darkTeal.withValues(alpha: 0.06),
          HydraReport.cream.withValues(alpha: 0.5),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: HydraReport.darkTeal.withValues(alpha: 0.1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: HydraReport.darkTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.bolt_rounded,
                  size: 18, color: HydraReport.darkTeal),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI PAD PLACEMENT',
                      style: TextStyle(
                          color: HydraReport.darkTeal,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8)),
                  SizedBox(height: 2),
                  Text('Hydrawav3 pad placement from this analysis',
                      style: TextStyle(
                          color: HydraReport.gray400, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

Widget _noAreasText() => const Text(
      'No focus areas were captured for this report, so pad placement '
      'can\'t be generated.',
      style: TextStyle(color: HydraReport.muted, fontSize: 12.5),
    );

/// One focus area's white card (title + body).
Widget _areaCard(String bodyPart, Widget body) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: HydraReport.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.place_rounded, size: 15, color: HydraReport.tanDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text(bodyPart,
                  style: const TextStyle(
                      color: HydraReport.darkTeal,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        body,
      ],
    ),
  );
}

/// The list of option cards for a fetched plan (or a message when empty).
Widget _planBody(SessionPlan? plan) {
  if (plan == null) {
    return const Text('No plan available for this area.',
        style: TextStyle(color: HydraReport.muted, fontSize: 12));
  }
  if (plan.areas.isEmpty) {
    return const Text('No pad placements configured for this area.',
        style: TextStyle(color: HydraReport.muted, fontSize: 12));
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < plan.areas.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        PadOptionCard(plan.areas[i], i),
      ],
    ],
  );
}

/// AI Pad Placement (web `PractitionerReport` first section). Reuses the
/// existing Session Plan data layer: for each focus area derived from the
/// report it fetches `GET treatment-plans/body-part/:name` and shows the
/// Sun/Moon electrode placements.
class PadPlacementSection extends ConsumerWidget {
  final Map<String, dynamic> report;
  const PadPlacementSection(this.report, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = padPlacementAreas(report);
    return _padShell(children: [
      if (areas.isEmpty)
        _noAreasText()
      else
        for (var i = 0; i < areas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _AreaPadLive(bodyPart: areas[i]),
        ],
    ]);
  }
}

/// Static pad placement built from PRE-FETCHED plans (used by the image PDF,
/// which can't run async fetches while capturing).
class PadPlacementStatic extends StatelessWidget {
  final Map<String, dynamic> report;
  final Map<String, SessionPlan?> plans;
  const PadPlacementStatic(
      {required this.report, required this.plans, super.key});

  @override
  Widget build(BuildContext context) {
    final areas = padPlacementAreas(report);
    return _padShell(children: [
      if (areas.isEmpty)
        _noAreasText()
      else
        for (var i = 0; i < areas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _areaCard(areas[i], _planBody(plans[areas[i]])),
        ],
    ]);
  }
}

/// One focus area (live fetch) for the on-screen practitioner tab.
class _AreaPadLive extends ConsumerWidget {
  final String bodyPart;
  const _AreaPadLive({required this.bodyPart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionPlanByBodyPartProvider(bodyPart));
    return _areaCard(
      bodyPart,
      async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => _planBody(null),
        data: (plan) => _planBody(plan),
      ),
    );
  }
}

/// One placement option (OPTION N + heading + protocol + Sun/Moon).
class PadOptionCard extends StatelessWidget {
  final PlacementArea area;
  final int index;
  const PadOptionCard(this.area, this.index, {super.key});

  @override
  Widget build(BuildContext context) {
    final heading = area.areaname?.trim().isNotEmpty == true
        ? area.areaname!.trim()
        : (area.sun?.muscle.isNotEmpty == true
            ? area.sun!.muscle
            : area.moon?.muscle ?? 'Placement');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HydraReport.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HydraReport.tanLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OPTION ${index + 1}',
              style: const TextStyle(
                  color: HydraReport.tanDark,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(heading, style: RW.bodyBold(size: 14)),
          if (area.protocolName?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.electrical_services_rounded,
                    size: 14, color: HydraReport.muted),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(area.protocolName!, style: RW.bodyBold(size: 12))),
                if (area.protocolDurationFormatted.isNotEmpty)
                  Text(area.protocolDurationFormatted,
                      style: const TextStyle(
                          color: HydraReport.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (area.sun != null)
            _polarity('Sun', area.sun!, HydraReport.orange600,
                Icons.wb_sunny_rounded),
          if (area.moon != null) ...[
            const SizedBox(height: 8),
            _polarity('Moon', area.moon!, HydraReport.blue800,
                Icons.nightlight_round),
          ],
          if (area.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            RW.kv('Description', area.description!.trim()),
          ],
        ],
      ),
    );
  }

  Widget _polarity(
      String polarity, PlacementPoint p, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(polarity,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              if (p.view.isNotEmpty) ...[
                const SizedBox(width: 6),
                RW.miniBadge(p.view,
                    bg: HydraReport.gray100, fg: HydraReport.muted),
              ],
            ],
          ),
          if (p.label.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.label.trim(), style: RW.bodyBold(size: 13)),
          ],
          if (p.muscle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            RW.kv('Muscle', p.muscle.trim()),
          ],
          if (p.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(p.description!.trim(),
                style: const TextStyle(
                    color: HydraReport.muted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
