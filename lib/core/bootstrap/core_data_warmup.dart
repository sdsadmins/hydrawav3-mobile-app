import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/protocols/presentation/providers/protocol_provider.dart';
import '../utils/logger.dart';

/// True once core app data (goal tags + protocols) has been warmed up after
/// login. Reset to false on logout so the next session warms up again.
final appWarmedUpProvider = StateProvider<bool>((ref) => false);

/// Fire-and-forget pre-load of the core data the home screens need (goal tags +
/// protocols), with a couple of retries for transient failures. This used to
/// gate the splash screen ("goals sometimes not loaded"); with the splash
/// removed it simply warms the caches early so the home screens open with data
/// ready. Safe to call repeatedly — it no-ops once warmed.
Future<void> warmUpCoreData(WidgetRef ref) async {
  if (ref.read(appWarmedUpProvider)) return;
  ref.read(appWarmedUpProvider.notifier).state = true;

  await _retry(() => ref.refresh(goalTagListProvider.future), label: 'goal tags');
  await _retry(() => ref.refresh(protocolListProvider.future), label: 'protocols');
}

Future<void> _retry(
  Future<Object?> Function() task, {
  required String label,
  int attempts = 3,
}) async {
  for (var i = 1; i <= attempts; i++) {
    try {
      await task();
      return;
    } catch (e) {
      appLogger.w('Core data warm-up: $label failed (attempt $i/$attempts): $e');
      if (i < attempts) {
        await Future<void>.delayed(Duration(milliseconds: 400 * i));
      }
    }
  }
  appLogger.e('Core data warm-up: $label gave up after $attempts attempts');
}
