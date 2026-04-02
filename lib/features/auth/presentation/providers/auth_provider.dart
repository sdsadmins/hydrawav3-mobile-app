import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';
import '../../services/biometric_service.dart';

// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserProfile? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? user,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final BiometricService _biometricService;

  AuthNotifier(this._repository, this._biometricService)
      : super(const AuthState());

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final isLoggedIn = await _repository.isLoggedIn();
      if (isLoggedIn) {
        try {
          // Try biometric auth if enabled (skip on web)
          final biometricEnabled = await _biometricService.isEnabled();
          if (biometricEnabled) {
            final authenticated = await _biometricService.authenticate();
            if (!authenticated) {
              state = state.copyWith(
                isAuthenticated: false,
                isLoading: false,
              );
              return;
            }
          }
        } catch (_) {
          // Biometric not available (e.g. web) — skip
        }

        try {
          final profile = await _repository.getProfile();
          state = state.copyWith(
            isAuthenticated: true,
            isLoading: false,
            user: profile,
          );
        } catch (_) {
          // Offline but has tokens - allow through
          state = state.copyWith(
            isAuthenticated: true,
            isLoading: false,
          );
        }
      } else {
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
        );
      }
    } catch (e) {
      // Any crash (web platform, etc.) — just show login
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
      );
    }
  }

  Future<void> login(LoginRequest request) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repository.login(request);
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        user: profile,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState();
  }

  /// 🎮 Demo mode - bypass auth for UI exploration
  void enterDemoMode() {
    state = AuthState(
      isAuthenticated: true,
      isLoading: false,
      user: const UserProfile(
        id: 'demo-user',
        username: 'demo',
        email: 'demo@hydrawav3.com',
        firstName: 'Demo',
        lastName: 'User',
        roles: ['PRACTITIONER'],
      ),
    );
  }

  Future<void> refreshProfile() async {
    try {
      final profile = await _repository.getProfile();
      state = state.copyWith(user: profile);
    } catch (_) {
      // Silently fail - keep existing profile
    }
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authRepositoryProvider),
    ref.read(biometricServiceProvider),
  );
});

final profileProvider = FutureProvider<UserProfile>((ref) async {
  final repository = ref.read(authRepositoryProvider);
  return repository.getProfile();
});
