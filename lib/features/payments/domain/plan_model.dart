class SubscriptionPlan {
  final String? id;
  final String name;
  final String? status;
  final String? billingCycle;
  final double? amount;
  final String? currency;
  final DateTime? currentPeriodEnd;

  const SubscriptionPlan({
    this.id,
    required this.name,
    this.status,
    this.billingCycle,
    this.amount,
    this.currency,
    this.currentPeriodEnd,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        id: json['id']?.toString(),
        name: json['name'] as String? ?? 'Free',
        status: json['status'] as String?,
        billingCycle: json['billingCycle'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        currentPeriodEnd: json['currentPeriodEnd'] != null
            ? DateTime.tryParse(json['currentPeriodEnd'] as String)
            : null,
      );

  bool get isPaid =>
      status == 'active' &&
      name.toLowerCase() != 'free';

  bool get isExpired =>
      currentPeriodEnd != null &&
      currentPeriodEnd!.isBefore(DateTime.now());
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
