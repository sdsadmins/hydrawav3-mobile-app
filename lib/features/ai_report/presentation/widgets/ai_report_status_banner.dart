import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../providers/ai_report_providers.dart';

/// Background AI-report tracker (web parity with the header's "Generating N AI
/// Reports" pill). Shows a summary pill while reports generate, then one row per
/// finished job — completed ("ready → View") or errored — each dismissable.
/// Multiple concurrent generations are supported. Idle → nothing.
class AiReportStatusBanner extends ConsumerWidget {
  const AiReportStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(aiReportGenerationProvider);
    if (jobs.isEmpty) return const SizedBox.shrink();

    final notifier = ref.read(aiReportGenerationProvider.notifier);
    final busyCount = jobs.where((j) => j.isBusy).length;
    final finished =
        jobs.where((j) => !j.isBusy).toList(growable: false);

    return Column(
      children: [
        if (busyCount > 0) _busyPill(busyCount),
        for (final j in finished) ...[
          if (busyCount > 0 || j != finished.first) const SizedBox(height: 8),
          j.phase == AiReportPhase.error
              ? _errorRow(context, notifier, j)
              : _doneRow(context, notifier, j),
        ],
      ],
    );
  }

  Widget _busyPill(int count) {
    final label = count == 1
        ? 'Generating AI Report'
        : 'Generating $count AI Reports';
    return _shell(
      color: ThemeConstants.success,
      bg: ThemeConstants.success.withValues(alpha: 0.12),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: ThemeConstants.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
          Text('3–5 min each',
              style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _doneRow(
      BuildContext context, AiReportGenerationNotifier notifier, AiReportJob j) {
    return _shell(
      color: ThemeConstants.success,
      bg: ThemeConstants.success.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: ThemeConstants.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${j.label} ready',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () {
              final report = j.report;
              if (report != null) {
                context.pushNamed(RouteNames.aiReport, extra: report);
              }
            },
            child: Text('View',
                style: TextStyle(
                    color: ThemeConstants.accent, fontWeight: FontWeight.w800)),
          ),
          _dismiss(notifier, j.id),
        ],
      ),
    );
  }

  Widget _errorRow(
      BuildContext context, AiReportGenerationNotifier notifier, AiReportJob j) {
    return _shell(
      color: ThemeConstants.error,
      bg: ThemeConstants.error.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: ThemeConstants.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              j.message ?? '${j.label} generation failed',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: ThemeConstants.error,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700),
            ),
          ),
          _dismiss(notifier, j.id),
        ],
      ),
    );
  }

  Widget _dismiss(AiReportGenerationNotifier notifier, String id) => IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => notifier.dismiss(id),
        icon: Icon(Icons.close_rounded,
            size: 16, color: ThemeConstants.textTertiary),
      );

  Widget _shell(
      {required Color color, required Color bg, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}
