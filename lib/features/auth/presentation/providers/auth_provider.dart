import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../splash/presentation/providers/app_bootstrap_provider.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';
import '../../services/biometric_service.dart';

// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;

  /// True once the initial stored-token check (checkAuthStatus) has completed.
  /// The splash screen waits on this before routing to login vs home.
  final bool isInitialized;

  final UserProfile? user;
  final String? error;

  final String? selectedOrgId;
  final String? selectedOrgName; // ✅ ADD THIS

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.isInitialized = false,
    this.user,
    this.error,
    this.selectedOrgId,
    this.selectedOrgName, // ✅
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    bool? isInitialized,
    UserProfile? user,
    String? error,
    String? selectedOrgId,
    String? selectedOrgName, // ✅
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      user: user ?? this.user,
      error: error,
      selectedOrgId: selectedOrgId != null ? selectedOrgId : this.selectedOrgId,
      selectedOrgName:
          selectedOrgName != null ? selectedOrgName : this.selectedOrgName,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final BiometricService _biometricService;
  final Ref _ref;

  AuthNotifier(this._repository, this._biometricService, this._ref)
      : super(const AuthState());

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    try {
      final isLoggedIn = await _repository.isLoggedIn();

      if (isLoggedIn) {
        try {
          final biometricEnabled = await _biometricService.isEnabled();

          if (biometricEnabled) {
            final authenticated = await _biometricService.authenticate();

            if (!authenticated) {
              state = state.copyWith(
                isAuthenticated: false,
                isLoading: false,
                isInitialized: true,
              );
              return;
            }
          }
        } catch (_) {}

        try {
          final profile = await _repository.getProfile();

          // Restore selected organization from storage
          final selectedOrgId = await _repository.getSelectedOrgId();
          final selectedOrgName = await _repository.getSelectedOrgName();

          state = state.copyWith(
            isAuthenticated: true,
            isLoading: false,
            isInitialized: true,
            user: profile,
            selectedOrgId: selectedOrgId,
            selectedOrgName: selectedOrgName,
          );
        } catch (_) {
          // Restore selected organization even if profile fetch fails
          final selectedOrgId = await _repository.getSelectedOrgId();
          final selectedOrgName = await _repository.getSelectedOrgName();

          state = state.copyWith(
            isAuthenticated: true,
            isLoading: false,
            isInitialized: true,
            selectedOrgId: selectedOrgId,
            selectedOrgName: selectedOrgName,
          );
        }
      } else {
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
          isInitialized: true,
        );
      }
    } catch (_) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        isInitialized: true,
      );
    }
  }

  Future<void> login(LoginRequest request) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final profile = await _repository.login(request);

      state = state.copyWith(
        isAuthenticated: true,
        user: profile,
        selectedOrgId: null, // ✅ FIXED
      );
    } catch (e) {
      state = state.copyWith(
        error: _friendlyAuthError(e),
      );
    } finally {
      // Always clear loading to avoid infinite spinners on some devices.
      state = state.copyWith(isLoading: false);
    }
  }

  /// Map an auth/login error into a clean, user-facing message.
  String _friendlyAuthError(Object error) {
    if (error is AuthException) return error.message;
    if (error is ServerException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  Future<void> logout() async {
    await _repository.logout();
    await _repository.clearSelectedOrganization();
    // Reset the splash warm-up flag so the next login re-loads core data.
    _ref.read(appWarmedUpProvider.notifier).state = false;
    // Keep isInitialized true so the router goes straight to login, not splash.
    state = const AuthState(isInitialized: true);
  }

  /// ✅ ADD THIS (IMPORTANT 🔥)
  Future<void> setOrganization(String orgId, String orgName) async {
    // Persist the organization selection
    await _repository.saveSelectedOrganization(orgId, orgName);

    state = state.copyWith(
      selectedOrgId: orgId,
      selectedOrgName: orgName,
    );
  }

  /// 🎮 Demo mode
  void enterDemoMode() {
    state = AuthState(
      isAuthenticated: true,
      isLoading: false,
      isInitialized: true,
      user: const UserProfile(
        id: 'demo-user',
        username: 'demo',
        email: 'demo@hydrawav3.com',
        firstName: 'Demo',
        lastName: 'User',
        roles: ['PRACTITIONER'],
      ),
      selectedOrgId: null, // ✅ ensure org selection required
    );
  }

  Future<void> refreshProfile() async {
    try {
      final profile = await _repository.getProfile();
      state = state.copyWith(user: profile);
    } catch (_) {}
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authRepositoryProvider),
    ref.read(biometricServiceProvider),
    ref,
  );
});

final profileProvider = FutureProvider<UserProfile>((ref) async {
  final repository = ref.read(authRepositoryProvider);
  return repository.getProfile();
});
