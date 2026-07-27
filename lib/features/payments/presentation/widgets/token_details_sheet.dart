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
/// Two shapes, exactly as the spec splits them: an **Enterprise** package shows
/// what's left of the team's allowance, while **pay-as-you-go** shows a credit
/// balance. Copy rule from the integration plan §3: tokens are "session
/// credits" in anything customer-facing.
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
                    : _isEnterprise(plan)
                        ? _EnterpriseBody(plan: plan!, grant: grant)
                        : _CreditsBody(
                            tokens: tokens, plan: plan, grant: grant),
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
// Enterprise — a package billed in session hours
// ---------------------------------------------------------------------------

class _EnterpriseBody extends ConsumerWidget {
  final SubscriptionPlan plan;
  final double? grant;
  const _EnterpriseBody({required this.plan, required this.grant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final org = ref.watch(authStateProvider).selectedOrgName;
    final seconds = plan.sessionDurationSeconds;
    final reports = plan.aiReportsAvailable;
    final devices = plan.deviceLimit;
    // One pool drives every gauge, so one fraction fills every bar.
    final fraction = plan.fractionOfGrant(grant);
    final secondsTotal = plan.totalForGrant(seconds, grant);
    final reportsTotal = plan.totalForGrant(reports, grant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${plan.name} · Enterprise',
          style: TextStyle(
            fontSize: HwType.lg,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          org == null || org.isEmpty
              ? "Your team's package"
              : "$org · your team's package",
          style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
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
                  seconds == null ? '—' : _sessionTimeLeft(seconds),
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
                _hoursUsedLine(seconds, secondsTotal, devices),
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
                  reports?.toString() ?? '—',
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
                    : 'AI reports available on this package',
                style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
              ),
            ],
          ),
        ),

        if (plan.currentPeriodEnd != null) ...[
          const SizedBox(height: HwSpace.s3),
          Text(
            'Renews on ${_fmtDate(plan.currentPeriodEnd!)}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
          ),
        ],
      ],
    );
  }

  /// The spec's line: "12.5 of 40 device-hours used · 6 units". Falls back to
  /// just the unit count while the allowance is unknown.
  static String _hoursUsedLine(int? left, num? total, int? devices) {
    final unitsSuffix = devices == null
        ? ''
        : (devices == 0
            ? ' · unlimited units'
            : ' · $devices unit${devices == 1 ? '' : 's'}');

    if (total == null || left == null) {
      return devices == null
          ? 'Device-hours are shared across your team'
          : 'Device-hours are shared across your team$unitsSuffix';
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

// ---------------------------------------------------------------------------
// Pay-as-you-go — a session-credit balance
// ---------------------------------------------------------------------------

class _CreditsBody extends StatelessWidget {
  final double? tokens;
  final SubscriptionPlan? plan;
  final double? grant;
  const _CreditsBody({
    required this.tokens,
    required this.plan,
    required this.grant,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final total = plan?.tokensTotal ?? grant;
    final fraction = plan?.fractionOfGrant(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Session credits',
          style: TextStyle(
            fontSize: HwType.lg,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        Center(
          child: Text(
            tokens == null ? '—' : tokens!.round().toString(),
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1.5,
              color: p.copperInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          total == null
              ? '1 credit ≈ one ~9-min session'
              : 'of ${total.round()} this month · 1 credit ≈ one ~9-min session',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
        ),
        const SizedBox(height: HwSpace.s3),
        if (fraction != null) ...[
          HwBar(fraction),
          const SizedBox(height: HwSpace.s2),
        ],
        Text(
          'Credits are shared across every practitioner in this organization.',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: HwType.cap, height: 1.5, color: p.ink2),
        ),
      ],
    );
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
