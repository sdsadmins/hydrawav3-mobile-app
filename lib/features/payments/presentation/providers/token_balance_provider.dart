import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/logger.dart';
import '../../../session/services/sessions_socket.dart';
import '../../data/payment_repository.dart';
import '../../domain/plan_model.dart';

/// Current token balance for the selected org. Mirrors the web header's
/// `Tokens: N` badge: an initial fetch from `/payments/current-plan/:org`
/// (`remainingTokens`), then live updates from the `/payments` socket
/// `credits:update` event.
final tokenBalanceProvider =
    StateNotifierProvider<TokenBalanceNotifier, double?>((ref) {
  final notifier = TokenBalanceNotifier(ref);
  ref.onDispose(notifier.stop);
  return notifier;
});

/// The selected org's current subscription plan. Null when no org is selected
/// or the lookup fails — callers render a neutral line rather than a made-up
/// plan name.
final currentPlanProvider =
    FutureProvider.autoDispose<SubscriptionPlan?>((ref) async {
  // Re-fetch when the balance moves, so the plan row can't drift from the badge.
  ref.watch(tokenBalanceProvider);
  final orgId = await ref.read(secureStorageProvider).getSelectedOrgId();
  if (orgId == null || orgId.isEmpty) return null;
  try {
    return await ref.read(paymentRepositoryProvider).getCurrentPlan(orgId);
  } catch (_) {
    return null;
  }
});

/// Tokens granted per period for the current plan — the product's `aiCredit`.
///
/// The plan endpoint reports only what remains, but a subscription seeds
/// `remainingTokens` from its product's `aiCredit` (payment.service.ts:174),
/// so that value is the period allowance and the honest denominator for the
/// plan sheet's usage bars. Null when the product can't be resolved, in which
/// case the sheet omits the bars rather than guessing a total.
///
/// A FREE org's plan points at the product named "Free", and `GET /products`
/// strips that one out server-side (`product.service.ts:150`) because it can't
/// be bought. That lookup therefore always missed on a free plan, so the sheet
/// had no denominator and drew no usage bar at all. `/products/subscriptions`
/// applies no such filter, so it's the fallback.
final planTokenGrantProvider =
    FutureProvider.autoDispose<double?>((ref) async {
  final plan = await ref.watch(currentPlanProvider.future);
  final productId = plan?.productId;
  if (productId == null || productId.isEmpty) return null;
  final repo = ref.read(paymentRepositoryProvider);
  try {
    final products = await repo.getProducts();
    for (final p in products) {
      if (p.id == productId) return p.aiCredit;
    }
  } catch (_) {
    // Purchasable-product list unavailable — fall through to the full list.
  }
  for (final p in await repo.getSubscriptionProducts()) {
    if (p.id == productId) return p.aiCredit;
  }
  return null;
});

/// The current plan's max concurrent device limit (backend `deviceLimit`).
/// `0` means unlimited; `null` means unknown (not loaded / no org). Used to cap
/// how many devices can be selected/run at once (web parity).
final planDeviceLimitProvider = FutureProvider.autoDispose<int?>((ref) async {
  final orgId = await ref.read(secureStorageProvider).getSelectedOrgId();
  if (orgId == null || orgId.isEmpty) return null;
  try {
    final plan = await ref.read(paymentRepositoryProvider).getCurrentPlan(orgId);
    return plan.deviceLimit;
  } catch (_) {
    return null;
  }
});

class TokenBalanceNotifier extends StateNotifier<double?> {
  final Ref _ref;
  io.Socket? _socket;
  String? _orgId;

  TokenBalanceNotifier(this._ref) : super(null);

  Future<void> start(String orgId) async {
    if (orgId.isEmpty) return;
    if (_orgId == orgId && _socket != null) return;
    appLogger.i('TokenBalance: start(org=$orgId)');
    await stop();
    _orgId = orgId;
    await _fetch();
    await _connectSocket();
  }

  Future<void> stop() async {
    _socket?.dispose();
    _socket = null;
    _orgId = null;
    if (mounted) state = null;
  }

  Future<void> _fetch() async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      // Raw dump so we can see the actual response shape / field names.
      final dio = _ref.read(nodeDioProvider);
      final raw = await dio.get(ApiEndpoints.currentPlan(orgId));
      appLogger.i('TokenBalance: raw current-plan for org=$orgId → ${raw.data}');

      final plan = await _ref.read(paymentRepositoryProvider).getCurrentPlan(orgId);
      appLogger.i(
        'TokenBalance: parsed name=${plan.name} status=${plan.status} '
        'remainingTokens=${plan.remainingTokens}',
      );
      if (mounted) state = plan.remainingTokens;
    } catch (e) {
      appLogger.i('TokenBalance: fetch failed: $e');
    }
  }

  Future<void> _connectSocket() async {
    try {
      final token = await _ref.read(secureStorageProvider).getAccessToken();
      final socket =
          SessionsSocket.buildSocket(token: token, namespace: '/payments');
      _socket = socket;

      socket.onConnect((_) {
        SessionsSocket.subscribeOrganization(socket, _orgId);
        appLogger.i('TokenBalance: socket connected, subscribed org-$_orgId');
      });
      socket.onConnectError(
          (e) => appLogger.e('TokenBalance: connect error: $e'));

      socket.on('credits:update', (data) {
        final value = _asDouble(data);
        if (value != null && mounted) state = value;
      });

      socket.connect();
    } catch (e) {
      appLogger.e('TokenBalance: socket setup failed: $e');
    }
  }

  /// The `credits:update` payload may be a bare number or a `{credits: n}` map.
  double? _asDouble(dynamic data) {
    if (data is num) return data.toDouble();
    if (data is Map) {
      final v = data['credits'] ?? data['remainingTokens'];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }
    if (data is String) return double.tryParse(data);
    return null;
  }
}
