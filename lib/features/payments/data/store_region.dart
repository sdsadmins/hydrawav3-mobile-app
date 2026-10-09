import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Test override for the store country, honoured in debug/profile builds only
/// (never in release): `flutter run --dart-define=HW_STORE_COUNTRY=US`.
const _forcedCountry = String.fromEnvironment('HW_STORE_COUNTRY');

/// The user's App Store / Play Store country — what Apple's and Google's US
/// link-out rules are based on (not the phone's language or region setting).
/// iOS returns ISO alpha-3 ("USA"), Android alpha-2 ("US"). Null when the
/// store can't be reached (no Play services, simulator without an account…),
/// which is treated as "not US".
final storeCountryProvider = FutureProvider<String?>((ref) async {
  if (!kReleaseMode && _forcedCountry.isNotEmpty) {
    return _forcedCountry.toUpperCase();
  }
  try {
    final code = await InAppPurchase.instance.countryCode();
    return code.isEmpty ? null : code.toUpperCase();
  } catch (_) {
    return null;
  }
});

/// True only for US-storefront users: they may be sent to the website to buy
/// tokens. Everyone else keeps the information-only Plan & usage screen.
final isUsStorefrontProvider = Provider<bool>((ref) {
  final code = ref.watch(storeCountryProvider).valueOrNull;
  return code == 'US' || code == 'USA';
});
