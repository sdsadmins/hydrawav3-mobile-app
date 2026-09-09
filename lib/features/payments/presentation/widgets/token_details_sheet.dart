import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/plan_model.dart';
import '../providers/token_balance_provider.dart';

/// The plan / session-credits sheet behind the token badge, ported from the UI
/// spec's `tokenSheet()` (app.js:2245).
///
/// EVERY plan — Free, pay-as-you-go or a package — is presented in the same
/// Enterprise shape: the plan's own name heads the sheet, and each quota is a
/// card with its label on the left and what's left as a pill on the right.
/// Only the category word in the heading and the CTA differ. Copy rule from the
/// integration plan §3: tokens are "session credits" in anything
/// customer-facing.
void showTokenDetailsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Shown from inside the ShellRoute, whose Navigator stops at the Scaffold
    // body — without this the sheet renders behind the bottom nav.
    useRootNavigator: true,
    builder: (_) => const _TokenDetailsSheet(),
  );
}

/// Package plans are billed in session hours; everything else in credits.
/// The rule lives on the model so the badge and this sheet can't disagree.
bool _isEnterprise(SubscriptionPlan? plan) => plan?.isEnterprisePlan ?? false;

/// Seconds → "2 h 30 min", matching the spec's `hoursLeftStr()`.
String _sessionTimeLeft(int seconds) {
  final totalMin = (seconds / 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h > 0 && m > 0) return '$h h $m min';
  if (h > 0) return '$h h';
  return '$m min';
}

class _TokenDetailsSheet extends ConsumerWidget {
  const _TokenDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final planAsync = ref.watch(currentPlanProvider);
    final plan = planAsync.valueOrNull;
    // The socket-backed balance wins over the plan snapshot when both exist.
    final tokens = ref.watch(tokenBalanceProvider) ?? plan?.remainingTokens;
    // The period's token grant, which every usage bar measures against.
    final grant = ref.watch(planTokenGrantProvider).valueOrNull;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: planAsync.isLoading && plan == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _PlanBody(plan: plan, tokens: tokens, grant: grant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, HwSpace.s4, 18, HwSpace.s2),
              child: _PrimaryButton(
                label: _isEnterprise(plan)
                    ? 'Full plan & usage'
                    : 'Top up credits',
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push(RoutePaths.subscription);
                },
              ),
            ),
            HwPress(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 14),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontSize: HwType.cap,
                    fontWeight: FontWeight.w600,
                    color: p.ink3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One body for every plan.
//
// A package and a Free/pay-as-you-go plan differ only in the category word in
// the heading and the CTA at the bottom — the gauges are the same quantities
// off the same token pool, so they get the same layout. Previously a
// non-package plan fell to a stripped-down "Session credits" body with no plan
// name and no per-quota rows, which is what made Free look like a different
// (and emptier) product than Enterprise.
// ---------------------------------------------------------------------------

class _PlanBody extends ConsumerWidget {
  final SubscriptionPlan? plan;

  /// Live (socket-backed) credit balance; preferred over the plan snapshot.
  final double? tokens;

  /// The period's token grant — the denominator behind every bar.
  final double? grant;

  const _PlanBody({
    required this.plan,
    required this.tokens,
    required this.grant,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final org = ref.watch(authStateProvider).selectedOrgName;
    final enterprise = _isEnterprise(plan);
    final seconds = plan?.sessionDurationSeconds;
    final reports = plan?.aiReportsAvailable;
    final devices = plan?.deviceLimit;

    // One pool drives every gauge, so one fraction fills every bar. The live
    // balance wins over the plan snapshot when both are known.
    final left = tokens ?? plan?.remainingTokens;
    final total = plan?.tokensTotal ?? grant;
    final fraction = (left != null && total != null && total > 0)
        ? (left / total).clamp(0.0, 1.0).toDouble()
        : null;
    final secondsTotal = plan?.totalForGrant(seconds, grant);
    final reportsTotal = plan?.totalForGrant(reports, grant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plan on the left, credits left on the right — the balance belongs to
        // the plan line itself, not to a card of its own.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _heading(plan),
                    style: TextStyle(
                      fontSize: HwType.lg,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subheading(org, plan, enterprise),
                    style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HwSpace.s2),
            HwPill(
              left == null ? '--' : '${left.round()} credits',
              tone: HwPillTone.copper,
              tabular: true,
            ),
          ],
        ),
        const SizedBox(height: HwSpace.s3),

        // Session time left — pill, usage bar, "X of Y used" line.
        HwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwCardHeader(
                'Session time left',
                trailing: HwPill(
                  seconds == null ? '--' : _sessionTimeLeft(seconds),
                  tone: HwPillTone.copper,
                  tabular: true,
                ),
              ),
              if (fraction != null) ...[
                const SizedBox(height: 7),
                HwBar(fraction),
              ],
              const SizedBox(height: 6),
              Text(
                _hoursUsedLine(seconds, secondsTotal, devices, enterprise),
                style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s2),

        HwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwCardHeader(
                'Full Mobility Reports left',
                trailing: HwPill(
                  reports?.toString() ?? '--',
                  tone: HwPillTone.info,
                  tabular: true,
                ),
              ),
              if (fraction != null) ...[
                const SizedBox(height: 7),
                HwBar(fraction, gradient: HwBar.infoToGood),
              ],
              const SizedBox(height: 6),
              Text(
                reportsTotal != null && reports != null
                    ? '${reportsTotal.round() - reports} of '
                        '${reportsTotal.round()} AI reports used this period'
                    : 'AI reports available on this plan',
                style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
              ),
            ],
          ),
        ),

        const SizedBox(height: HwSpace.s3),
        Text(
          plan?.currentPeriodEnd != null
              ? 'Renews on ${_fmtDate(plan!.currentPeriodEnd!)} · credits are '
                  'shared across every practitioner in this organization'
              : 'Credits are shared across every practitioner in this '
                  'organization',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
        ),
      ],
    );
  }

  /// `<plan name> · <category>`, collapsed to just the name when the two are
  /// the same — a Free plan badges as "Free", and "Free · Free" reads as a bug.
  static String _heading(SubscriptionPlan? plan) {
    if (plan == null || plan.name.isEmpty) return 'Session credits';
    final badge = plan.badgeLabel;
    return badge == plan.name ? plan.name : '${plan.name} · $badge';
  }

  static String _subheading(
    String? org,
    SubscriptionPlan? plan,
    bool enterprise,
  ) {
    final status = plan?.status;
    if (org == null || org.isEmpty) {
      if (enterprise) return "Your team's package";
      return (status != null && status.isNotEmpty) ? status : 'Session credits';
    }
    if (enterprise) return "$org · your team's package";
    return (status != null && status.isNotEmpty)
        ? '$org · ${status.toLowerCase()}'
        : '$org · session credits';
  }

  /// The spec's line: "12.5 of 40 device-hours used · 6 units". Falls back to
  /// just the unit count while the allowance is unknown.
  static String _hoursUsedLine(
    int? left,
    num? total,
    int? devices,
    bool enterprise,
  ) {
    final unitsSuffix = devices == null
        ? ''
        : (devices == 0
            ? ' · unlimited units'
            : ' · $devices unit${devices == 1 ? '' : 's'}');

    if (total == null || left == null) {
      final base = enterprise
          ? 'Device-hours are shared across your team'
          : 'Session time is drawn from your credits';
      return '$base$unitsSuffix';
    }

    String hrs(num seconds) {
      final h = seconds / 3600;
      // 12.5 reads better than 12.50, and 40 better than 40.0.
      return h == h.roundToDouble()
          ? h.round().toString()
          : h.toStringAsFixed(1);
    }

    return '${hrs(total - left)} of ${hrs(total)} device-hours '
        'used$unitsSuffix';
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }
}


class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: p.sunGrad,
          borderRadius: BorderRadius.circular(HwRadius.sm),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
