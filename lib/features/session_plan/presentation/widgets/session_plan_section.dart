import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../ai_report/data/ai_report_repository.dart';
import '../../../ai_report/domain/kinetic_chain_payload.dart';
import '../../../ai_report/presentation/providers/ai_report_providers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../domain/session_plan.dart';
import '../providers/session_plan_provider.dart';

/// "Session Plan" panel on the AI tab (web parity). Collapsible dropdown whose
/// body carries the four header actions from the web Session Plan:
/// **Active Areas** (count; tap to reveal the areas + pad placements),
/// **View Detailed Report**, **3D-Pattern A**, **3D-Pattern B**.
class SessionPlanSection extends ConsumerStatefulWidget {
  const SessionPlanSection({super.key});

  @override
  ConsumerState<SessionPlanSection> createState() =>
      _SessionPlanSectionState();
}

class _SessionPlanSectionState extends ConsumerState<SessionPlanSection> {
  bool _open = false;
  bool _showAreas = false;

  @override
  Widget build(BuildContext context) {
    // Active Areas reflect the focus areas chosen in the Guided Assessment
    // ("Area of Focus" → discomfortAreas), matching the web's sessionAreas.
    final areas = ref
        .watch(guidedAssessmentProvider)
        .discomfortAreas
        .map((a) => a.bodyPart.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // Web parity (session.tsx `disabled = isGuestMode || !selectedClientId ||
    // generating`): View Detailed Report / 3D-Pattern A/B are enabled only in
    // Client mode, with a client selected, and no report currently generating.
    final isClientMode =
        ref.watch(sessionClientModeProvider) == ClientMode.client;
    final hasClient = ref.watch(selectedClientProvider) != null;
    final busy = ref.watch(aiReportBusyProvider);
    final canUse = isClientMode && hasClient && !busy;
    // Tell the user exactly which condition is blocking the buttons.
    final String? gateReason = canUse
        ? null
        : !isClientMode
            ? 'Switch to Client mode (Guest can\'t open the report / 3D).'
            : !hasClient
                ? 'Select a client above to open the report or 3D patterns.'
                : 'Wait for the AI report to finish generating.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (_open) ...[
            const SizedBox(height: 14),
            // The four Session Plan actions.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: Icons.place_rounded,
                  label: 'Active Areas (${areas.length})',
                  selected: _showAreas,
                  onTap: () => setState(() => _showAreas = !_showAreas),
                ),
                _actionButton(
                  icon: Icons.description_rounded,
                  label: 'View Detailed Report',
                  enabled: canUse,
                  onTap: _openReport,
                ),
                _actionButton(
                  icon: Icons.view_in_ar_rounded,
                  label: '3D-Pattern A',
                  enabled: canUse,
                  onTap: () => _open3d('A'),
                ),
                _actionButton(
                  icon: Icons.view_in_ar_rounded,
                  label: '3D-Pattern B',
                  enabled: canUse,
                  onTap: () => _open3d('B'),
                ),
              ],
            ),
            if (gateReason != null) ...[
              const SizedBox(height: 8),
              Text(
                gateReason,
                style: TextStyle(
                    fontSize: 11, color: ThemeConstants.textTertiary),
              ),
            ],
            // "Active Areas" reveals the focus-area editor + pad placements.
            if (_showAreas) ...[
              const SizedBox(height: 14),
              _activeAreasPanel(areas),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header() => InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Row(
          children: [
            Icon(Icons.map_rounded, size: 18, color: ThemeConstants.accent),
            const SizedBox(width: 8),
            Text('Session Plan',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: ThemeConstants.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('AI',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: ThemeConstants.accent)),
            ),
            const Spacer(),
            Icon(
              _open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: ThemeConstants.textSecondary,
            ),
          ],
        ),
      );

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? ThemeConstants.accent
                : ThemeConstants.navBackground,
            borderRadius: BorderRadius.circular(999),
          ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? ThemeConstants.onAccent : ThemeConstants.onNav),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color:
                    selected ? ThemeConstants.onAccent : ThemeConstants.onNav,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _activeAreasPanel(List<String> areas) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeConstants.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Focus Areas',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textPrimary)),
          const SizedBox(height: 8),
          if (areas.isEmpty)
            Text(
                'No focus areas yet — add them in the Guided Assessment '
                '(Area of Focus) above.',
                style: TextStyle(
                    fontSize: 12, color: ThemeConstants.textTertiary))
          else
            ...[
              for (var i = 0; i < areas.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _AreaPlan(bodyPart: areas[i]),
              ],
            ],
        ],
      ),
    );
  }

  bool _loading3d = false;

  /// Open the 3D kinetic-chain viewer for the given pattern ('A' or 'B').
  /// Fetches the latest AI report (web parity: `anatomyViewerData` reads the
  /// recent report's `kinetic_chain_pattern_a/_b`), derives the viewer payload,
  /// and navigates to the full-screen WebGL viewer.
  Future<void> _open3d(String pattern) async {
    if (_loading3d) return;
    setState(() => _loading3d = true);
    try {
      final auth = ref.read(authStateProvider);
      final client = ref.read(selectedClientProvider);
      final report = await ref.read(aiReportRepositoryProvider).recent(
            // Reports are stored under the CLIENT's id (a Mongo ObjectId), not
            // the practitioner's numeric id — the /recent endpoint rejects the
            // numeric id with "Invalid userId format".
            userId: client?.id,
            organizationId: int.tryParse(auth.selectedOrgId ?? ''),
          );
      if (!mounted) return;
      if (report == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Generate a report first to view the 3D kinetic chain.'),
        ));
        return;
      }
      final key = pattern.toLowerCase();
      if (!kineticChainPatternHasData(report, key)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pattern $pattern has no kinetic-chain data to show.'),
        ));
        return;
      }
      final payload = buildKineticChainPayload(report, key);
      context.pushNamed(
        RouteNames.kineticChain3d,
        extra: {
          'patternLabel':
              'Kinetic Chain Visualization - Pattern ${pattern.toUpperCase()}',
          'payload': payload,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Couldn\'t load the 3D view: $e'),
      ));
    } finally {
      if (mounted) setState(() => _loading3d = false);
    }
  }

  void _openReport() {
    final client = ref.read(selectedClientProvider);
    if (client != null) {
      context.pushNamed(
        RouteNames.aiReports,
        extra: {'clientId': client.id, 'title': client.displayName},
      );
    } else {
      context.pushNamed(RouteNames.aiReportClients);
    }
  }
}

/// Collapsible pad-placement plan for a single focus area. Fetches its plan
/// only once expanded (keeps the panel light when several areas are added).
class _AreaPlan extends ConsumerStatefulWidget {
  final String bodyPart;
  const _AreaPlan({required this.bodyPart});

  @override
  ConsumerState<_AreaPlan> createState() => _AreaPlanState();
}

class _AreaPlanState extends ConsumerState<_AreaPlan> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(Icons.place_rounded,
                    size: 15, color: ThemeConstants.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.bodyPart,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ThemeConstants.textPrimary)),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: ThemeConstants.textSecondary,
                ),
              ],
            ),
          ),
          // Lazy fetch: only watch (and load) the plan while expanded.
          if (_open) ...[
            const SizedBox(height: 10),
            _content(),
          ],
        ],
      ),
    );
  }

  Widget _content() {
    final async = ref.watch(sessionPlanByBodyPartProvider(widget.bodyPart));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text('No plan available for this area.',
          style: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
      data: (plan) {
        if (plan.areas.isEmpty) {
          return Text('No pad placements configured for this area.',
              style:
                  TextStyle(fontSize: 12, color: ThemeConstants.textTertiary));
        }
        final n = plan.areas.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n muscle option${n == 1 ? '' : 's'} available',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: ThemeConstants.accent)),
            const SizedBox(height: 10),
            for (var i = 0; i < plan.areas.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _PlacementCard(plan.areas[i], i),
            ],
          ],
        );
      },
    );
  }
}

class _PlacementCard extends StatelessWidget {
  final PlacementArea area;
  final int index;
  const _PlacementCard(this.area, this.index);

  @override
  Widget build(BuildContext context) {
    final heading = area.areaname?.trim().isNotEmpty == true
        ? area.areaname!.trim()
        : (area.sun?.muscle.isNotEmpty == true
            ? area.sun!.muscle
            : (area.moon?.muscle.isNotEmpty == true
                ? area.moon!.muscle
                : 'Placement'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeConstants.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OPTION ${index + 1}',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: ThemeConstants.accent)),
          const SizedBox(height: 2),
          // Heading (muscle/area name) — full, wraps, never truncated.
          Text(heading,
              softWrap: true,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textPrimary)),
          if (area.protocolName?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.electrical_services_rounded,
                    size: 14, color: ThemeConstants.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(area.protocolName!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary)),
                ),
                if (area.protocolDurationFormatted.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(area.protocolDurationFormatted,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textSecondary)),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (area.sun != null)
            _polarityBlock(
                'Sun', area.sun!, ThemeConstants.warning, Icons.wb_sunny_rounded),
          if (area.moon != null) ...[
            const SizedBox(height: 8),
            _polarityBlock(
                'Moon', area.moon!, ThemeConstants.info, Icons.nightlight_round),
          ],
          if (area.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            _kv('Description', area.description!.trim()),
          ],
        ],
      ),
    );
  }

  /// One polarity (Sun/Moon) block — label + muscle + description shown in full
  /// (soft-wrapped, never truncated), full card width so nothing overflows.
  Widget _polarityBlock(
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
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 6),
              Text(polarity,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color)),
              if (p.view.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(p.view,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textTertiary)),
                ),
              ],
            ],
          ),
          if (p.label.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.label.trim(),
                softWrap: true,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary)),
          ],
          if (p.muscle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Muscle', p.muscle.trim()),
          ],
          if (p.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(p.description!.trim(),
                softWrap: true,
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: ThemeConstants.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: ThemeConstants.textSecondary),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
