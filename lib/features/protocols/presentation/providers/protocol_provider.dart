import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  final repository = ref.read(protocolRepositoryProvider);
  return repository.getProtocols();
});

final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  final repository = ref.read(protocolRepositoryProvider);
  return repository.getProtocol(id);
});
