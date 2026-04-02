import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  void dispose() { _userCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authStateProvider.notifier).login(LoginRequest(
      username: _userCtrl.text.trim(), password: _passCtrl.text, rememberMe: _remember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);

    ref.listen<AuthState>(authStateProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!), backgroundColor: ThemeConstants.error));
      }
    });

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E3040), ThemeConstants.background, ThemeConstants.background],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    // Logo
                    AnimatedEntrance(
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ThemeConstants.accent.withValues(alpha: 0.1),
                            border: Border.all(color: ThemeConstants.accent.withValues(alpha: 0.15)),
                            boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.waves_rounded, size: 36, color: ThemeConstants.accent),
                        ),
                        const SizedBox(height: 20),
                        const Text('HYDRAWAV3', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 4)),
                        const SizedBox(height: 4),
                        const Text('Clinical Recovery Device', style: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary, letterSpacing: 1)),
                      ]),
                    ),
                    const SizedBox(height: 36),

                    // Form
                    AnimatedEntrance(
                      index: 1,
                      child: GradientCard(
                        padding: const EdgeInsets.all(24),
                        borderRadius: 20,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Welcome back', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                              const SizedBox(height: 4),
                              const Text('Sign in to continue your therapy journey', style: TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
                              const SizedBox(height: 24),

                              TextFormField(
                                controller: _userCtrl,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20)),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: _obscure,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
                                  suffixIcon: GestureDetector(
                                    onTap: () => setState(() => _obscure = !_obscure),
                                    child: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: ThemeConstants.textTertiary, size: 20),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 14),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _remember = !_remember),
                                    child: Row(children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 18, height: 18,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(5),
                                          color: _remember ? ThemeConstants.accent : Colors.transparent,
                                          border: Border.all(color: _remember ? ThemeConstants.accent : ThemeConstants.textTertiary, width: 1.5),
                                        ),
                                        child: _remember ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Remember me', style: TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
                                    ]),
                                  ),
                                  GestureDetector(
                                    onTap: () => context.pushNamed(RouteNames.forgotPassword),
                                    child: const Text('Forgot password?', style: TextStyle(fontSize: 13, color: ThemeConstants.accent, fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Gradient sign in button
                              _GradientCTA(
                                label: 'Sign In',
                                icon: Icons.arrow_forward_rounded,
                                isLoading: auth.isLoading,
                                onTap: _login,
                              ),
                              const SizedBox(height: 12),

                              // Biometric
                              FutureBuilder<bool>(
                                future: ref.read(biometricServiceProvider).isAvailable(),
                                builder: (c, s) {
                                  if (s.data != true) return const SizedBox.shrink();
                                  return SizedBox(height: 48, child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final ok = await ref.read(biometricServiceProvider).authenticate();
                                      if (ok) ref.read(authStateProvider.notifier).checkAuthStatus();
                                    },
                                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                                    label: const Text('Biometric Login'),
                                  ));
                                },
                              ),

                              // Divider
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Row(children: [
                                  const Expanded(child: Divider(color: ThemeConstants.border)),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('or', style: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary))),
                                  const Expanded(child: Divider(color: ThemeConstants.border)),
                                ]),
                              ),

                              // Demo
                              SizedBox(height: 48, child: OutlinedButton.icon(
                                onPressed: () => ref.read(authStateProvider.notifier).enterDemoMode(),
                                icon: const Icon(Icons.explore_outlined, size: 20),
                                label: const Text('Explore Demo Mode'),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    AnimatedEntrance(
                      index: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? ", style: TextStyle(color: ThemeConstants.textSecondary, fontSize: 13)),
                          GestureDetector(
                            onTap: () => context.pushNamed(RouteNames.signup),
                            child: const Text('Create Account', style: TextStyle(color: ThemeConstants.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ],
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
  const _GradientCTA({required this.label, required this.icon, this.isLoading = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [ThemeConstants.accent, Color(0xFFE09060)]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Icon(icon, color: Colors.white, size: 18),
                ]),
        ),
      ),
    );
  }
}
