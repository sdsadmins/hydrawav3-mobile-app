import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/client_model.dart';
import 'client_remote_source.dart';

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  return ClientRepository(ref.read(clientRemoteSourceProvider));
});

class ClientRepository {
  final ClientRemoteSource _remote;

  ClientRepository(this._remote);

  Future<List<Client>> getClients(String organizationId) =>
      _remote.getClients(organizationId);

  Future<Client> getById(String clientId) => _remote.getById(clientId);

  Future<Client> create(CreateClientRequest request) =>
      _remote.create(request);

  Future<Client> updateClient(String clientId, Map<String, dynamic> patch) =>
      _remote.updateClient(clientId, patch);
}
