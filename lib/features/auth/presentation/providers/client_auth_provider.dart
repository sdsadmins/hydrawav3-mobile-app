import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/client_auth_remote_source.dart';

class ClientAuthState {
  final bool isLoading;
  final String? error;
  final ClientSession? session;

  const ClientAuthState({
    this.isLoading = false,
    this.error,
    this.session,
  });

  bool get isAuthenticated => session != null;

  ClientAuthState copyWith({
    bool? isLoading,
    String? error,
    ClientSession? session,
  }) {
    return ClientAuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      session: session ?? this.session,
    );
  }
}

final clientAuthProvider =
    StateNotifierProvider<ClientAuthNotifier, ClientAuthState>((ref) {
  return ClientAuthNotifier(
    remote: ref.read(clientAuthRemoteSourceProvider),
    storage: ref.read(secureStorageProvider),
  );
});

/// At-home client authentication (parity with the web `/client` login). On a
/// successful login the client's JWT is written to the shared secure storage so
/// the Node Dio auth interceptor attaches it to subsequent client-scoped calls
/// (e.g. session start). Login is gated server-side on an active lease, so a
/// deactivated lease surfaces "Lease is not active" here.
class ClientAuthNotifier extends StateNotifier<ClientAuthState> {
  final ClientAuthRemoteSource _remote;
  final SecureStorageService _storage;

  ClientAuthNotifier({
    required ClientAuthRemoteSource remote,
    required SecureStorageService storage,
  })  : _remote = remote,
        _storage = storage,
        super(const ClientAuthState());

  Future<bool> login({
    required String clientName,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final session = await _remote.login(
        clientName: clientName,
        password: password,
      );
      // Deliberately NOT written to the shared secure storage. That storage +
      // the shared auth interceptor belong to the practitioner (Django) flow,
      // which clears tokens on any 401 — a stray practitioner call would wipe
      // the client's Node token and log them out. The client token lives only
      // in this state and is attached by a dedicated client Dio.
      state = ClientAuthState(session: session);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.clearAll();
    state = const ClientAuthState();
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    if (e is ServerException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
