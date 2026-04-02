import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
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
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authStateProvider.notifier).login(
          LoginRequest(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            rememberMe: _rememberMe,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: ThemeConstants.error),
        );
      }
    });

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  // Logo
                  const SizedBox(height: 32),
                  const Icon(Icons.waves_rounded, size: 48, color: ThemeConstants.accent),
                  const SizedBox(height: 16),
                  const Text('HYDRAWAV3', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 3)),
                  const SizedBox(height: 4),
                  const Text('Clinical Recovery Device', style: TextStyle(fontSize: 13, color: ThemeConstants.textTertiary)),
                  const SizedBox(height: 40),

                  // Form card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Welcome back', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                          const SizedBox(height: 4),
                          const Text('Sign in to your account', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: _usernameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Username',
                              prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
                              suffixIcon: GestureDetector(
                                onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                                child: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: ThemeConstants.textTertiary, size: 20),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _rememberMe = !_rememberMe),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18, height: 18,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                        fillColor: WidgetStateProperty.all(_rememberMe ? ThemeConstants.accent : Colors.transparent),
                                        side: const BorderSide(color: ThemeConstants.textTertiary),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Remember me', style: TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => context.pushNamed(RouteNames.forgotPassword),
                                child: const Text('Forgot password?', style: TextStyle(fontSize: 13, color: ThemeConstants.accent, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Sign in
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: authState.isLoading ? null : _handleLogin,
                              child: authState.isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Sign In'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Biometric
                          FutureBuilder<bool>(
                            future: ref.read(biometricServiceProvider).isAvailable(),
                            builder: (ctx, snap) {
                              if (snap.data != true) return const SizedBox.shrink();
                              return SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final ok = await ref.read(biometricServiceProvider).authenticate();
                                    if (ok) ref.read(authStateProvider.notifier).checkAuthStatus();
                                  },
                                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                                  label: const Text('Biometric Login'),
                                ),
                              );
                            },
                          ),

                          // Divider
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              children: [
                                const Expanded(child: Divider(color: ThemeConstants.border)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text('or', style: TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                                ),
                                const Expanded(child: Divider(color: ThemeConstants.border)),
                              ],
                            ),
                          ),

                          // Demo mode
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => ref.read(authStateProvider.notifier).enterDemoMode(),
                              icon: const Icon(Icons.explore_outlined, size: 20),
                              label: const Text('Explore Demo Mode'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ", style: TextStyle(color: ThemeConstants.textSecondary, fontSize: 13)),
                      GestureDetector(
                        onTap: () => context.pushNamed(RouteNames.signup),
                        child: const Text('Create Account', style: TextStyle(color: ThemeConstants.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
