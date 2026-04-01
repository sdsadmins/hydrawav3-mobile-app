import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_text_field.dart';
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

  Future<void> _handleBiometricLogin() async {
    final biometricService = ref.read(biometricServiceProvider);
    final authenticated = await biometricService.authenticate();
    if (authenticated) {
      await ref.read(authStateProvider.notifier).checkAuthStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    ref.listen<AuthState>(authStateProvider, (prev, next) {
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ThemeConstants.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo placeholder
                    Icon(
                      Icons.waves,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: ThemeConstants.spacingSm),
                    Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: ThemeConstants.spacingXxl),

                    // Username field
                    HwTextField(
                      controller: _usernameController,
                      label: 'Username',
                      hint: 'Enter your username',
                      prefixIcon: const Icon(Icons.person_outline),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: ThemeConstants.spacingMd),

                    // Password field
                    HwTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Enter your password',
                      obscureText: _obscurePassword,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: ThemeConstants.spacingSm),

                    // Remember me + Forgot password
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                            ),
                            const Text('Remember me'),
                          ],
                        ),
                        TextButton(
                          onPressed: () =>
                              context.pushNamed(RouteNames.forgotPassword),
                          child: const Text('Forgot Password?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: ThemeConstants.spacingLg),

                    // Login button
                    HwButton(
                      label: 'Log In',
                      onPressed: _handleLogin,
                      isLoading: authState.isLoading,
                    ),
                    const SizedBox(height: ThemeConstants.spacingMd),

                    // Biometric login
                    FutureBuilder<bool>(
                      future:
                          ref.read(biometricServiceProvider).isAvailable(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) {
                          return const SizedBox.shrink();
                        }
                        return HwButton(
                          label: 'Login with Biometrics',
                          icon: Icons.fingerprint,
                          isOutlined: true,
                          onPressed: _handleBiometricLogin,
                        );
                      },
                    ),
                    const SizedBox(height: ThemeConstants.spacingLg),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? "),
                        TextButton(
                          onPressed: () =>
                              context.pushNamed(RouteNames.signup),
                          child: const Text('Sign Up'),
                        ),
                      ],
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
