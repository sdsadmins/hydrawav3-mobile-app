import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payments/data/payment_repository.dart';
import '../../../payments/data/store_region.dart';
import '../../../payments/domain/plan_model.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';

/// Full "Plan & usage" screen — the destination `token_details_sheet.dart`'s
/// "Full plan & usage" button pushes to. Shows the org's real current-plan
/// usage plus every purchasable tier, pulled from the same backend the web
/// app uses (`GET /payments/current-plan/:org`, `GET /products/subscriptions`).
///
/// Outside the US this stays information only — no Stripe SDK, no card
/// fields, no "Upgrade" button, no purchase link: Apple's Guideline 3.1.1 and
/// Google Play's billing policy reject any call-to-action that sends a
/// purchase anywhere but their own billing there.
///
/// US storefront only ([isUsStorefrontProvider]): the Epic v. Apple and Epic
/// v. Google court orders let US apps send users to the website to buy, so a
/// "Buy tokens" card opens the website's plan page in a Chrome Custom Tab /
/// Safari sheet (like More → Buy More Products) — the browser's own page,
/// not an app web view.
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
            if (ref.watch(isUsStorefrontProvider)) ...[
              const SizedBox(height: HwSpace.s3),
              const _BuyOnWebCard(),
            ],
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
                left == null ? '--' : '${left.round()} credits',
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
                  value: seconds == null ? '--' : _sessionTimeLeft(seconds),
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: reportsTotal != null && reports != null
                      ? 'AI reports (of ${reportsTotal.round()})'
                      : 'AI reports left',
                  value: reports?.toString() ?? '--',
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: 'Devices',
                  value: devices == null
                      ? '--'
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

/// US storefront only: opens the website's plan page in the phone's browser
/// to buy tokens or change plan. New credits reach the app through the live
/// balance socket; pull down here to refresh the plan details.
class _BuyOnWebCard extends ConsumerWidget {
  const _BuyOnWebCard();

  /// The website's login handoff, which saves this login as the website's
  /// cookies and forwards to the plan page:
  /// `<site>/auth/handoff?token=<Bearer access>&refreshToken=<Bearer refresh>`
  /// `&orgId=<org>&redirect=/practitioner/subscription`.
  /// Tokens carry the "Bearer " prefix, as the website's own login stores
  /// them. Without a stored login it falls back to the plan page itself.
  static Future<Uri> _planLink(WidgetRef ref) async {
    final plan = Uri.parse(ApiEndpoints.practitionerSubscriptionUrl);
    final storage = ref.read(secureStorageProvider);
    final access = await storage.getAccessToken();
    final refresh = await storage.getRefreshToken();
    final org = ref.read(authStateProvider).selectedOrgId ??
        await storage.getSelectedOrgId();
    if (access == null || access.isEmpty) return plan;
    String bearer(String t) => t.startsWith('Bearer ') ? t : 'Bearer $t';
    return Uri(
      scheme: plan.scheme,
      host: plan.host,
      port: plan.hasPort ? plan.port : null,
      path: '/auth/handoff',
      queryParameters: {
        'token': bearer(access),
        if (refresh != null && refresh.isNotEmpty)
          'refreshToken': bearer(refresh),
        if (org != null && org.isNotEmpty) 'orgId': org,
        'redirect': plan.path.isEmpty ? '/practitioner/subscription' : plan.path,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    return HwCard(
      accented: true,
      onTap: () async {
        final link = await _planLink(ref);
        final ok = await launchUrl(
          link,
          // Same as More → Buy More Products: a Chrome Custom Tab /
          // Safari sheet over the app.
          mode: LaunchMode.inAppBrowserView,
        );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't open the browser.")),
          );
        }
      },
      child: Row(
        children: [
          Icon(Icons.shopping_bag_outlined, color: p.copperInk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buy tokens or change plan',
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Opens your plan page on '
                  '${Uri.parse(ApiEndpoints.practitionerSubscriptionUrl).host}',
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded, size: 20, color: p.ink3),
        ],
      ),
    );
  }
}
