import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../domain/auth_models.dart';
import '../../services/biometric_service.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _remember = false;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authStateProvider.notifier).login(
          LoginRequest(
            username: _userCtrl.text.trim(),
            password: _passCtrl.text,
            rememberMe: _remember,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);

    /// ✅ ONLY ERROR HANDLING
    ref.listen<AuthState>(authStateProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: ThemeConstants.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E3040),
              ThemeConstants.background,
              ThemeConstants.background
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    /// Logo
                    AnimatedEntrance(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ThemeConstants.accent.withValues(alpha: 0.1),
                            ),
                            child: const Icon(Icons.waves_rounded,
                                size: 36, color: ThemeConstants.accent),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'HYDRAWAV3',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    /// Form
                    AnimatedEntrance(
                      index: 1,
                      child: GradientCard(
                        padding: const EdgeInsets.all(24),
                        borderRadius: 20,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              /// Username
                              TextFormField(
                                controller: _userCtrl,
                                decoration: const InputDecoration(
                                    hintText: 'Username'),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Required'
                                        : null,
                              ),

                              const SizedBox(height: 12),

                              /// Password
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () => setState(
                                        () => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Required'
                                        : null,
                              ),

                              const SizedBox(height: 20),

                              /// ✅ FIXED BUTTON (NO ERROR)
                              SizedBox(
                                width: double.infinity,
                                child: _GradientCTA(
                                  label: 'Sign In',
                                  icon: Icons.arrow_forward_rounded,
                                  isLoading: auth.isLoading,
                                  onTap: _login,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientCTA extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  const _GradientCTA({
    required this.label,
    required this.icon,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ThemeConstants.accent, Color(0xFFE09060)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(width: 8),
                    Icon(icon, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }
}