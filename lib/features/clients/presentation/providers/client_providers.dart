import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';

/// Whether the session is being run for a real client or anonymously (guest).
/// Mirrors the web `isGuestMode` toggle — default is GUEST (web parity).
enum ClientMode { client, guest }

/// Current Client/Guest selection for the session being set up.
final sessionClientModeProvider =
    StateProvider<ClientMode>((ref) => ClientMode.guest);

/// The client selected for the session (only meaningful in [ClientMode.client]).
final selectedClientProvider = StateProvider<Client?>((ref) => null);

/// Free-text search applied to the client picker.
final clientSearchQueryProvider = StateProvider<String>((ref) => '');

/// All clients for the currently selected organization.
final clientListProvider = FutureProvider.autoDispose<List<Client>>((ref) async {
  final orgId = ref.watch(authStateProvider).selectedOrgId;
  if (orgId == null || orgId.isEmpty) return const [];
  return ref.read(clientRepositoryProvider).getClients(orgId);
});

/// [clientListProvider] filtered by [clientSearchQueryProvider] (name/nickname),
/// matching the web `ClientSelectionSection` filter.
final filteredClientsProvider =
    Provider.autoDispose<AsyncValue<List<Client>>>((ref) {
  final query = ref.watch(clientSearchQueryProvider).trim().toLowerCase();
  return ref.watch(clientListProvider).whenData((clients) {
    if (query.isEmpty) return clients;
    return clients
        .where((c) =>
            c.clientName.toLowerCase().contains(query) ||
            (c.nickname?.toLowerCase().contains(query) ?? false))
        .toList();
  });
});
