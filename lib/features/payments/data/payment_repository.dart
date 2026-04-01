import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/plan_model.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.read(nodeDioProvider));
});

class PaymentRepository {
  final Dio _dio;

  PaymentRepository(this._dio);

  Future<String> getPublishableKey() async {
    try {
      final response = await _dio.get(ApiEndpoints.publishableKey);
      return response.data['publishableKey'] as String? ?? '';
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to get Stripe key',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<SubscriptionPlan> getCurrentPlan(String orgId) async {
    try {
      final response =
          await _dio.get(ApiEndpoints.currentPlan(orgId));
      return SubscriptionPlan.fromJson(response.data);
    } on DioException catch (e) {
      // Default to free plan if no plan found
      if (e.response?.statusCode == 404) {
        return const SubscriptionPlan(name: 'Free');
      }
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to get plan',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<Product>> getProducts() async {
    try {
      final response = await _dio.get(ApiEndpoints.products);
      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);
      return items
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to get products',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<String> createCheckoutSession({
    required String orgId,
    required String plan,
    required String billingCycle,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.createCheckoutSession(orgId),
        data: {
          'plan': plan,
          'billingCycle': billingCycle,
          'userId': userId,
        },
      );
      return response.data['url'] as String? ?? '';
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to create checkout',
        statusCode: e.response?.statusCode,
      );
    }
  }
}

/// Provider to check if user has paid subscription.
final isPaidUserProvider = FutureProvider<bool>((ref) async {
  // TODO: Read org ID from auth state
  try {
    final repo = ref.read(paymentRepositoryProvider);
    final plan = await repo.getCurrentPlan('default');
    return plan.isPaid;
  } catch (_) {
    return false;
  }
});
