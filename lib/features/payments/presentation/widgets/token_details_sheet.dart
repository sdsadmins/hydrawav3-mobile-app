import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/payment_repository.dart';
import '../../domain/plan_model.dart';
import '../providers/token_balance_provider.dart';

/// Show the token balance / plan breakdown bottom sheet (web parity: the header
/// "Plan Usage" dropdown). Usable from any screen that has the token chip.
void showTokenDetailsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _TokenDetailsSheet(),
  );
}

class _TokenDetailsSheet extends ConsumerWidget {
  const _TokenDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final orgId = auth.selectedOrgId ?? auth.user?.organizationId;
    final orgName = auth.selectedOrgName;
    final liveTokens = ref.watch(tokenBalanceProvider);
    final accent = ThemeConstants.accent;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: FutureBuilder<SubscriptionPlan>(
            future: orgId == null
                ? null
                : ref.read(paymentRepositoryProvider).getCurrentPlan(orgId),
            builder: (ctx, snap) {
              final plan = snap.data;
              final tokens = liveTokens ?? plan?.remainingTokens;
              final loading = snap.connectionState == ConnectionState.waiting;
              final low = tokens != null && tokens < 80;
              final heroColor = low ? Colors.red.shade600 : accent;
              final ph = loading ? '…' : '—';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ThemeConstants.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Token Balance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Hero balance card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          heroColor.withValues(alpha: 0.18),
                          heroColor.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: heroColor.withValues(alpha: 0.25)),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _HeroStat(
                              label: 'Tokens available',
                              value: tokens != null
                                  ? tokens.toStringAsFixed(0)
                                  : '—',
                              valueColor: heroColor,
                              labelColor: heroColor.withValues(alpha: 0.9),
                            ),
                          ),
                          _HeroVDivider(color: heroColor),
                          Expanded(
                            child: _HeroStat(
                              label: 'Plan usage',
                              value: plan?.name ?? ph,
                              valueColor: accent,
                              labelColor: ThemeConstants.textSecondary,
                            ),
                          ),
                          _HeroVDivider(color: heroColor),
                          Expanded(
                            child: _HeroStat(
                              label: 'Status',
                              value: plan?.status ?? ph,
                              valueColor: plan?.status != null
                                  ? _statusColor(plan!.status!)
                                  : ThemeConstants.textTertiary,
                              labelColor: ThemeConstants.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Usage stat cards ──
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.play_circle_outline_rounded,
                          // Web parity: the header shows the sessions quota as
                          // minutes derived from `sessionDurationSeconds`. Fall
                          // back to the legacy per-session count if a backend
                          // still returns `sessionsAvailable` instead.
                          label: plan?.sessionDurationSeconds != null
                              ? 'Sessions (min)'
                              : 'Sessions left',
                          value: plan?.sessionDurationSeconds != null
                              ? (plan!.sessionDurationSeconds! / 60)
                                  .round()
                                  .toString()
                              : (plan?.sessionsAvailable?.toString() ?? ph),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.auto_awesome_rounded,
                          label: 'AI reports left',
                          value: plan?.aiReportsAvailable?.toString() ?? ph,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Org / renewal info card ──
                  Container(
                    decoration: BoxDecoration(
                      color: ThemeConstants.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        _TokenDetailRow(
                            label: 'Organization', value: orgName ?? ph),
                        const _SheetDivider(),
                        _TokenDetailRow(
                          // Max devices this plan can run at once (0 = unlimited).
                          label: 'Devices you can run',
                          value: plan == null
                              ? ph
                              : (plan.deviceLimit == null
                                  ? ph
                                  : (plan.deviceLimit == 0
                                      ? 'Unlimited'
                                      : plan.deviceLimit.toString())),
                        ),
                        if (plan?.currentPeriodEnd != null) ...[
                          const _SheetDivider(),
                          _TokenDetailRow(
                            label: 'Renews on',
                            value: _fmtDate(plan!.currentPeriodEnd!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('active')) return ThemeConstants.success;
    if (s.contains('free')) return ThemeConstants.accent;
    return ThemeConstants.textTertiary;
  }

  static String _fmtDate(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$day/$m/${local.year}';
  }
}

/// Usage stat tile (Sessions left / AI reports left).
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ThemeConstants.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ThemeConstants.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: ThemeConstants.textTertiary,
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

/// A label/value row in the info card.
class _TokenDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _TokenDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: ThemeConstants.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: ThemeConstants.border);
  }
}

/// One column of the hero card: a small label over a bold value.
class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color labelColor;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: valueColor,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Thin vertical separator between hero columns.
class _HeroVDivider extends StatelessWidget {
  final Color color;
  const _HeroVDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: color.withValues(alpha: 0.2),
    );
  }
}
