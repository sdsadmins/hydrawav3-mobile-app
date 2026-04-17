import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart'; // ✅ ADD THIS

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  final auth = ref.watch(authStateProvider);
  final repository = ref.read(protocolRepositoryProvider);
  if (auth.selectedOrgId != null) {
    return repository.getProtocols(
      orgId: auth.selectedOrgId!,
    );
  }
  return repository.getProtocols();
});

final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  final repository = ref.read(protocolRepositoryProvider);
  return repository.getProtocol(id);
});