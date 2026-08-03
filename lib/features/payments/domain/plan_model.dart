class SubscriptionPlan {
  final String? id;

  /// The product this subscription was bought against. Its `aiCredit` is the
  /// period's token grant — the denominator behind the usage bars.
  final String? productId;

  final String name;
  final String? status;
  final String? billingCycle;
  final double? amount;
  final String? currency;
  final DateTime? currentPeriodEnd;

  /// Available (unlocked) tokens for the organization — the same value the web
  /// header shows as "Tokens: N". `lockTokens` (reserved during a running
  /// session) is intentionally not surfaced.
  final double? remainingTokens;
  final int? sessionsAvailable;
  final int? aiReportsAvailable;

  /// Remaining session quota expressed as duration in seconds (backend
  /// `sessionDurationSeconds`). The web header renders this as "Sessions (min)"
  /// (`sessionDurationSeconds / 60`). The backend migrated the sessions quota
  /// from a per-session count (`sessionsAvailable`) to this duration model, so
  /// this is the field to prefer; `sessionsAvailable` is kept only as a
  /// fallback for older backends.
  final int? sessionDurationSeconds;

  /// Max devices this plan can run concurrently (backend `deviceLimit`).
  /// `0` (or null) means unlimited.
  final int? deviceLimit;

  /// Session-credit allowance for the period, if the plan endpoint ever starts
  /// reporting one directly. Today it does not — the allowance comes from the
  /// product's `aiCredit` (see `planTokenGrantProvider`) — so this is normally
  /// null and callers fall back to that grant.
  ///
  /// There are no separate session-time or AI-report allowances to read: the
  /// backend derives both from this single token pool
  /// (payment.service.ts:1302-1315).
  final double? tokensTotal;

  /// The untouched response, so a newly-added quota field can be read without
  /// waiting on a model change.
  final Map<String, dynamic> raw;

  const SubscriptionPlan({
    this.id,
    this.productId,
    required this.name,
    this.status,
    this.billingCycle,
    this.amount,
    this.currency,
    this.currentPeriodEnd,
    this.remainingTokens,
    this.sessionsAvailable,
    this.aiReportsAvailable,
    this.sessionDurationSeconds,
    this.deviceLimit,
    this.tokensTotal,
    this.raw = const {},
  });

  /// First key present with a numeric value, or null.
  static num? _firstNum(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is num) return v;
    }
    return null;
  }

  /// Fraction of [total] still available, or null when either side is unknown
  /// or the allowance is unlimited (`0`). Never guesses a denominator.
  static double? _fraction(num? left, num? total) {
    if (left == null || total == null || total <= 0) return null;
    return (left / total).clamp(0.0, 1.0).toDouble();
  }

  /// Everything on this plan is one token pool. `remainingTokens` is seeded
  /// from the product's `aiCredit` and both `sessionDurationSeconds` and
  /// `aiReportsAvailable` are computed from it server-side
  /// (payment.service.ts:1302-1315), so a single fraction describes all three
  /// gauges: how much of the period's grant is left.
  ///
  /// [grant] is the product's `aiCredit`. Null (or zero) means the allowance
  /// isn't known and no bar is drawn.
  double? fractionOfGrant(double? grant) =>
      _fraction(remainingTokens, grant);

  /// Scale a remaining figure back up to what a full grant would buy. Both
  /// session time and AI reports are linear in tokens, so the period total is
  /// `remaining * grant / remainingTokens`.
  num? totalForGrant(num? remainingUnits, double? grant) {
    final left = remainingTokens;
    if (remainingUnits == null ||
        grant == null ||
        left == null ||
        left <= 0) {
      return null;
    }
    return remainingUnits * grant / left;
  }

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    // Backend `getCurrentPlan` returns `planName` (= product name, e.g. "Pro"),
    // not `name`, and exposes `hasActivePlan`/`isFreePlan` rather than a status.
    final displayName = (json['planName'] ?? json['plan'] ?? json['name'])
            ?.toString() ??
        'Free';
    final hasActive = json['hasActivePlan'] == true;
    final isFree = json['isFreePlan'] == true;
    final status = json['status']?.toString() ??
        (isFree ? 'Free plan' : (hasActive ? 'Active' : 'Inactive'));
    return SubscriptionPlan(
      id: json['id']?.toString() ?? json['paymentId']?.toString(),
      productId: json['productId']?.toString(),
      name: displayName,
      status: status,
      billingCycle: json['billingCycle'] as String?,
      amount: (json['amountInDollars'] ?? json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      currentPeriodEnd: json['currentPeriodEnd'] != null
          ? DateTime.tryParse(json['currentPeriodEnd'].toString())
          : null,
      remainingTokens: (json['remainingTokens'] as num?)?.toDouble(),
      sessionsAvailable: (json['sessionsAvailable'] as num?)?.toInt(),
      aiReportsAvailable: (json['aiReportsAvailable'] as num?)?.toInt(),
      sessionDurationSeconds:
          (json['sessionDurationSeconds'] as num?)?.toInt(),
      deviceLimit: (json['deviceLimit'] as num?)?.toInt(),
      // A credit allowance isn't part of the response today; accept the names
      // it would plausibly arrive under so it works the moment it is added.
      tokensTotal: _firstNum(json, const [
        'totalTokens',
        'tokensTotal',
        'tokensAllowed',
        'planTokens',
      ])?.toDouble(),
      raw: json,
    );
  }

  bool get isPaid => status == 'active' && name.toLowerCase() != 'free';

  /// The spec's `isEnterprise()` (app.js:2235): anything that isn't
  /// free/guest/trial/pay-as-you-go is a package plan billed in session hours.
  ///
  /// This is a *category*, not the product name — "Pro+", "Pro Team" and any
  /// custom package all badge as **Enterprise**, which is what the UI spec puts
  /// in the top-bar pill. The product's own name still heads the plan sheet.
  bool get isEnterprisePlan =>
      name.isNotEmpty &&
      !RegExp(r'free|guest|trial|pay', caseSensitive: false).hasMatch(name);

  /// What the top-bar badge reads: the category for package plans, the plan's
  /// own name otherwise (e.g. "Free").
  String get badgeLabel => isEnterprisePlan ? 'Enterprise' : name;

  bool get isExpired =>
      currentPeriodEnd != null && currentPeriodEnd!.isBefore(DateTime.now());
}

class Product {
  final String? id;
  final String name;
  final String? description;
  final double? monthlyPrice;
  final double? yearlyPrice;
  final String? currency;
  final List<String> features;

  /// Tokens granted per billing period (backend `aiCredit`). A new or renewed
  /// subscription seeds `remainingTokens` from this, so it is the allowance
  /// the plan sheet's usage bars measure against.
  final double? aiCredit;

  const Product({
    this.id,
    required this.name,
    this.description,
    this.monthlyPrice,
    this.yearlyPrice,
    this.currency,
    this.features = const [],
    this.aiCredit,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        // Mongo documents come back with `_id`.
        id: (json['id'] ?? json['_id'])?.toString(),
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble(),
        yearlyPrice: (json['yearlyPrice'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        features: (json['features'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        aiCredit: (json['aiCredit'] as num?)?.toDouble(),
      );
}
