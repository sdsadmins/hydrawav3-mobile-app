import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payments/data/payment_repository.dart';
import '../../../payments/domain/plan_model.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';

/// Full "Plan & usage" screen — the destination `token_details_sheet.dart`'s
/// "Full plan & usage" button pushes to. Shows the org's real current-plan
/// usage plus every purchasable tier, pulled from the same backend the web
/// app uses (`GET /payments/current-plan/:org`, `GET /products/subscriptions`).
///
/// Information only, identically on both platforms — no Stripe SDK, no card
/// fields, no native payment sheet, no "Upgrade" button, and no purchase
/// link/redirect of any kind anywhere in this file. Apple's Guideline 3.1.1
/// (In-App Purchase) treats ANY button, link, or call-to-action — even
/// plain, non-tappable text — that points a purchase of in-app functionality
/// anywhere other than Apple's own In-App Purchase as a rejection; Netflix
/// and Spotify's iOS apps don't even mention where to sign up for exactly
/// this reason. Rather than have iOS and Android diverge, this screen simply
/// never offers a way to buy anything on either platform until real StoreKit
/// (iOS) and a matching purchase flow (Android) are built.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final planAsync = ref.watch(currentPlanProvider);
    final plan = planAsync.valueOrNull;
    final tokens = ref.watch(tokenBalanceProvider) ?? plan?.remainingTokens;
    final grant = ref.watch(planTokenGrantProvider).valueOrNull;
    final productsAsync = ref.watch(subscriptionProductsProvider);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('Plan & usage'),
        foregroundColor: p.ink,
        backgroundColor: p.bg,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentPlanProvider);
          ref.invalidate(subscriptionProductsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CurrentPlanCard(plan: plan, tokens: tokens, grant: grant),
            const SizedBox(height: HwSpace.s4),
            const HwEyebrow('Compare plans'),
            switch (productsAsync) {
              AsyncData(:final value) when value.isNotEmpty => Column(
                  children: [
                    for (final product in value) ...[
                      _ProductCard(
                        product: product,
                        isCurrent: plan != null &&
                            plan.productId != null &&
                            plan.productId == product.id,
                      ),
                      const SizedBox(height: HwSpace.s2),
                    ],
                  ],
                ),
              AsyncError() => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    "Couldn't load plans. Pull down to try again.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink3, fontSize: HwType.sm),
                  ),
                ),
              _ => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
            },
          ],
        ),
      ),
    );
  }
}

/// Real usage for the org's current plan — session time, AI reports, device
/// limit — same data and math as the token badge's sheet (`_PlanBody`), laid
/// out full-page.
class _CurrentPlanCard extends ConsumerWidget {
  final SubscriptionPlan? plan;
  final double? tokens;
  final double? grant;
  const _CurrentPlanCard({
    required this.plan,
    required this.tokens,
    required this.grant,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final org = ref.watch(authStateProvider).selectedOrgName;
    final seconds = plan?.sessionDurationSeconds;
    final reports = plan?.aiReportsAvailable;
    final devices = plan?.deviceLimit;

    final left = tokens ?? plan?.remainingTokens;
    final total = plan?.tokensTotal ?? grant;
    final fraction = (left != null && total != null && total > 0)
        ? (left / total).clamp(0.0, 1.0).toDouble()
        : null;
    final secondsTotal = plan?.totalForGrant(seconds, grant);
    final reportsTotal = plan?.totalForGrant(reports, grant);

    return HwCard(
      decoration: BoxDecoration(
        gradient: p.heroGrad,
        borderRadius: BorderRadius.circular(HwRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan == null || plan!.name.isEmpty
                          ? 'Session credits'
                          : plan!.name,
                      style: const TextStyle(
                        fontSize: HwType.lg,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF2E9E2),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      org == null || org.isEmpty
                          ? (plan?.status ?? 'Session credits')
                          : '$org · ${plan?.status?.toLowerCase() ?? 'session credits'}',
                      style: const TextStyle(
                        fontSize: HwType.eyebrow,
                        color: Color(0xFFDDCABF),
                      ),
                    ),
                  ],
                ),
              ),
              HwPill(
                left == null ? '—' : '${left.round()} credits',
                tone: HwPillTone.copper,
                tabular: true,
              ),
            ],
          ),
          const SizedBox(height: HwSpace.s4),
          Row(
            children: [
              Expanded(
                child: _UsageStat(
                  label: 'Session time',
                  value: seconds == null ? '—' : _sessionTimeLeft(seconds),
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: reportsTotal != null && reports != null
                      ? 'AI reports (of ${reportsTotal.round()})'
                      : 'AI reports left',
                  value: reports?.toString() ?? '—',
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: 'Devices',
                  value: devices == null
                      ? '—'
                      : (devices == 0 ? 'Unlimited' : '$devices'),
                ),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: HwSpace.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(HwRadius.pill),
              child: Container(
                height: 9,
                color: Colors.white.withValues(alpha: 0.18),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: const Color(0xFFF2E9E2)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              secondsTotal != null && seconds != null
                  ? '${_sessionTimeLeft((secondsTotal - seconds).round())} used of '
                      '${_sessionTimeLeft(secondsTotal.round())} this period'
                  : 'Credits are shared across every practitioner in this '
                      'organization',
              style: const TextStyle(
                fontSize: HwType.eyebrow,
                color: Color(0xFFDDCABF),
              ),
            ),
          ],
          if (plan?.currentPeriodEnd != null) ...[
            const SizedBox(height: 4),
            Text(
              'Renews on ${_fmtDate(plan!.currentPeriodEnd!)}',
              style: const TextStyle(
                fontSize: HwType.eyebrow,
                color: Color(0xFFDDCABF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _sessionTimeLeft(int seconds) {
    final totalMin = (seconds / 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
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

class _UsageStat extends StatelessWidget {
  final String label;
  final String value;
  const _UsageStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: HwType.md,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF2E9E2),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: HwType.eyebrow,
            color: Color(0xFFDDCABF),
          ),
        ),
      ],
    );
  }
}

/// One tier's price, credit allowance and feature list — read-only, no CTA.
/// A monthly price is shown when the product has one; there is no
/// billing-cycle toggle since it has no purchase action to feed.
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isCurrent;

  const _ProductCard({
    required this.product,
    required this.isCurrent,
  });

  String get _priceLabel {
    final price = product.monthlyPrice ?? product.yearlyPrice;
    if (price == null) return 'Contact us';
    if (price == 0) return 'Free';
    final suffix = product.monthlyPrice != null ? '/mo' : '/yr';
    final currency = product.currency?.toUpperCase() == 'USD' ||
            product.currency == null
        ? '\$'
        : '${product.currency} ';
    final formatted = price == price.roundToDouble()
        ? price.round().toString()
        : price.toStringAsFixed(2);
    return '$currency$formatted$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwCard(
      accented: isCurrent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
              ),
              Text(
                _priceLabel,
                style: TextStyle(
                  fontSize: HwType.md,
                  fontWeight: FontWeight.w800,
                  color: p.copperInk,
                ),
              ),
            ],
          ),
          if (product.description != null &&
              product.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              product.description!,
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
          ],
          if (product.aiCredit != null) ...[
            const SizedBox(height: 6),
            Text(
              '${product.aiCredit!.round()} credits per period',
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
            ),
          ],
          if (product.features.isNotEmpty) ...[
            const SizedBox(height: HwSpace.s2),
            for (final feature in product.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: p.good),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(fontSize: HwType.sm, color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (isCurrent) ...[
            const SizedBox(height: HwSpace.s2),
            const Text(
              '✓ Your current plan',
              style: TextStyle(
                fontSize: HwType.eyebrow,
                fontWeight: FontWeight.w700,
                color: Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
