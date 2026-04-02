import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  try {
    return Connectivity().onConnectivityChanged.map((results) {
      return results.any((r) => r != ConnectivityResult.none);
    });
  } catch (_) {
    // Fallback for platforms where connectivity check fails
    return Stream.value(true);
  }
});

final isOnlineProvider = Provider<bool>((ref) {
  try {
    final connectivity = ref.watch(connectivityProvider);
    return connectivity.when(
      data: (isOnline) => isOnline,
      loading: () => true,
      error: (_, __) => true, // Assume online on error
    );
  } catch (_) {
    return true;
  }
});
