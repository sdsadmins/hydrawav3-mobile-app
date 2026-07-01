class SubscriptionPlan {
  final String? id;
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

  const SubscriptionPlan({
    this.id,
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
  });

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
    );
  }

  bool get isPaid => status == 'active' && name.toLowerCase() != 'free';

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

  const Product({
    this.id,
    required this.name,
    this.description,
    this.monthlyPrice,
    this.yearlyPrice,
    this.currency,
    this.features = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id']?.toString(),
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble(),
        yearlyPrice: (json['yearlyPrice'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        features: (json['features'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}
