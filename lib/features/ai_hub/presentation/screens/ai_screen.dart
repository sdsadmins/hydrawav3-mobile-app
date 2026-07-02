import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../ai_report/data/ai_report_repository.dart';
import '../../../ai_report/presentation/widgets/ai_report_status_banner.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../clients/presentation/widgets/client_selection_section.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../../intake/presentation/widgets/guided_assessment_panel.dart';
import '../../../intake/presentation/widgets/session_type_cards.dart';
import '../../../notifications/domain/app_notification.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../payments/presentation/widgets/token_balance_badge.dart';
import '../../../session_plan/presentation/widgets/session_plan_section.dart';

/// The "AI" tab: hosts the Client/Guest selection, the Guided-vs-QuickStart
/// chooser, the Guided Assessment wizard, and the AI report banner — moved off
/// the Devices screen so device management stays minimal. All state lives in
/// global providers, so the Devices screen's Start button still reads the
/// choices made here (client, session type, guided intake).
class AiScreen extends ConsumerWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same gating as the old DeviceListScreen._buildClientGuestSection():
    // client sessions always run the Guided Assessment (web parity), so the
    // Guided vs Quick Start chooser is Guest-only.
    final isGuest = ref.watch(sessionClientModeProvider) == ClientMode.guest;
    final isGuided =
        !isGuest || ref.watch(sessionTypeProvider) == SessionType.guided;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Header matching the other tabs: title on the left, token badge on
            // the right, then a subtitle.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const Spacer(),
                const _NotificationBell(),
                const SizedBox(width: 8),
                const TokenBalanceBadge(),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Client mode, guided assessment & AI reports',
              style: TextStyle(
                fontSize: 14,
                color: ThemeConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const AiReportStatusBanner(),
            const SizedBox(height: 12),
            const ClientSelectionSection(),
            if (isGuest) ...[
              const SizedBox(height: 12),
              const SessionTypeCards(),
            ],
            if (isGuided) ...[
              const SizedBox(height: 12),
              const GuidedAssessmentPanel(),
            ],
            const SizedBox(height: 12),
            const SessionPlanSection(),
          ],
        ),
      ),
    );
  }
}

/// Bell button with an unread badge. Tapping opens the notifications sheet.
/// The unread count comes from [unreadNotificationCountProvider], which fetches
/// `/notifications/:userId` and live-refreshes off the /payments credits socket
/// (the same signal fired when an AI report finishes generating).
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 24, color: ThemeConstants.textPrimary),
            if (unread > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: ThemeConstants.error,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: ThemeConstants.background, width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeConstants.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _NotificationsSheet(),
    );
  }
}

/// Scrollable list of notifications; tapping one marks it read.
class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Notifications',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ThemeConstants.textPrimary)),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: Icon(Icons.refresh_rounded,
                      color: ThemeConstants.textSecondary),
                  onPressed: () => ref.invalidate(notificationsProvider),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 380,
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Could not load notifications.',
                      style: TextStyle(color: ThemeConstants.error)),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_rounded,
                              size: 40, color: ThemeConstants.textTertiary),
                          const SizedBox(height: 10),
                          Text('No notifications yet',
                              style: TextStyle(
                                  color: ThemeConstants.textSecondary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _NotificationTile(items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification n;
  const _NotificationTile(this.n);

  IconData get _icon {
    switch (n.type) {
      case 'success':
        return Icons.check_circle_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _color() {
    switch (n.type) {
      case 'success':
        return ThemeConstants.success;
      case 'warning':
        return ThemeConstants.warning;
      case 'error':
        return ThemeConstants.error;
      default:
        return ThemeConstants.accent;
    }
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '';
    final local = t.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm · $hh:$mi';
  }

  /// Mark read, then (if the notification carries a report id) fetch that report
  /// and open [AiReportScreen] — mirrors the web's notification click.
  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    if (!n.read) markNotificationRead(ref, n.id);

    final reportId = n.reportId;
    if (reportId == null || reportId.isEmpty) return;

    // Capture router + messenger before popping the sheet (its context dies).
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Opening report…'), duration: Duration(seconds: 1)),
    );
    try {
      final report =
          await ref.read(aiReportRepositoryProvider).getById(reportId);
      if (report == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Report not found.')),
        );
        return;
      }
      router.pushNamed(RouteNames.aiReport, extra: report);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the report.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _color();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _onTap(context, ref),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: n.read
              ? ThemeConstants.surface
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: n.read
                ? ThemeConstants.border
                : color.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ThemeConstants.textPrimary)),
                  const SizedBox(height: 2),
                  Text(n.message,
                      style: TextStyle(
                          fontSize: 12,
                          color: ThemeConstants.textSecondary)),
                  if (n.createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(_fmtTime(n.createdAt),
                        style: TextStyle(
                            fontSize: 10,
                            color: ThemeConstants.textTertiary)),
                  ],
                ],
              ),
            ),
            if (!n.read) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
