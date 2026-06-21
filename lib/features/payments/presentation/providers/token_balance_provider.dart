import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/logger.dart';
import '../../../session/services/sessions_socket.dart';
import '../../data/payment_repository.dart';

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
