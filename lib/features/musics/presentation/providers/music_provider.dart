import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_remote_source.dart';
import '../../domain/music_model.dart';

/// The list of session "Atmosphere" tracks from the backend. Used by the
/// atmosphere picker in the live session screen.
final musicListProvider = FutureProvider<List<Music>>((ref) {
  return ref.read(musicRemoteSourceProvider).getMusics();
});
