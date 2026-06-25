import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../providers/ai_report_providers.dart';

/// Top banner that mirrors the web's "Generating AI Report" pill: shows while a
/// report is generating in the background, then a tappable "ready — View", or an
/// error. Idle → nothing.
class AiReportStatusBanner extends ConsumerWidget {
  const AiReportStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiReportGenerationProvider);
    final phase = state.phase;

    if (phase == AiReportPhase.idle) return const SizedBox.shrink();

    final notifier = ref.read(aiReportGenerationProvider.notifier);

    if (phase == AiReportPhase.error) {
      return _shell(
        color: ThemeConstants.error,
        bg: ThemeConstants.error.withValues(alpha: 0.12),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 18, color: ThemeConstants.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.message ?? 'Report generation failed',
                style: TextStyle(
                    color: ThemeConstants.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
            _dismiss(notifier),
          ],
        ),
      );
    }

    if (phase == AiReportPhase.done) {
      return _shell(
        color: ThemeConstants.success,
        bg: ThemeConstants.success.withValues(alpha: 0.12),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: ThemeConstants.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text('AI report ready',
                  style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                final report = state.report;
                if (report != null) {
                  context.pushNamed(RouteNames.aiReport, extra: report);
                }
              },
              child: Text('View',
                  style: TextStyle(
                      color: ThemeConstants.accent,
                      fontWeight: FontWeight.w800)),
            ),
            _dismiss(notifier),
          ],
        ),
      );
    }

    // busy (analyzing / processing / persisting)
    return _shell(
      color: ThemeConstants.success,
      bg: ThemeConstants.success.withValues(alpha: 0.12),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: ThemeConstants.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Generating AI Report',
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
          Text('3–5 min',
              style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _dismiss(AiReportGenerationNotifier notifier) => IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: notifier.reset,
        icon: Icon(Icons.close_rounded,
            size: 16, color: ThemeConstants.textTertiary),
      );

  Widget _shell(
      {required Color color, required Color bg, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
