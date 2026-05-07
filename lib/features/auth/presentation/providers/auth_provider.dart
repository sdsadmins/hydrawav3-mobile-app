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

  final String? selectedOrgId;
  final String? selectedOrgName; // ✅ ADD THIS

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
    this.selectedOrgId,
    this.selectedOrgName, // ✅
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? user,
    String? error,
    String? selectedOrgId,
    String? selectedOrgName, // ✅
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
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

  AuthNotifier(this._repository, this._biometricService)
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
            selectedOrgId: selectedOrgId,
            selectedOrgName: selectedOrgName,
          );
        }
      } else {
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
        );
      }
    } catch (_) {
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
        selectedOrgId: null, // ✅ FIXED
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
    await _repository.clearSelectedOrganization();
    state = const AuthState();
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
  );
});

final profileProvider = FutureProvider<UserProfile>((ref) async {
  final repository = ref.read(authRepositoryProvider);
  return repository.getProfile();
});
