import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True once the splash screen has finished warming up the core app data
/// (goal tags + protocols). The router keeps an authenticated user on the
/// splash screen until this flips true, so the home screens never open before
/// their data is ready (fixes "goals sometimes not loaded").
///
/// Reset to false on logout so the next session warms up again.
final appWarmedUpProvider = StateProvider<bool>((ref) => false);
