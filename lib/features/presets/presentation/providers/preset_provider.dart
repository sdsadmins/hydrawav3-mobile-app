import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/local_db.dart';
import '../../data/preset_repository.dart';

/// The saved Quick Presets, live from the local database.
///
/// `PresetRepository` has always been complete; nothing was reading it, so the
/// Presets screen showed hard-coded names instead. This is the missing wire.
final presetListProvider = StreamProvider.autoDispose<List<Preset>>((ref) {
  return ref.read(presetRepositoryProvider).watchPresets();
});

/// Whether another slot is free (`AppConstants.maxPresets`, currently 3).
final canAddPresetProvider = FutureProvider.autoDispose<bool>((ref) async {
  final presets = await ref.watch(presetListProvider.future);
  return presets.length < 3;
});
