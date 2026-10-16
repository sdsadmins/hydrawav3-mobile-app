import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../domain/auth_models.dart';
import '../providers/auth_provider.dart';
import '../providers/client_auth_provider.dart';
import '../widgets/auth_ui.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final bool _remember = false;
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Unified login (web parity: `Login` in `actions/action.ts`). One form, one
  /// submit: try the practitioner backend first; if that fails, fall back to
  /// the Node client login using the same field as `clientName`. No mode
  /// toggle — the credential shape decides which session is created.
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    setState(() => _submitting = true);
    try {
      // 1) Practitioner (Django) login.
      await ref.read(authStateProvider.notifier).login(
            LoginRequest(
              username: username,
              password: password,
              rememberMe: _remember,
            ),
          );
      if (ref.read(authStateProvider).isAuthenticated) {
        return; // router redirects to home
      }

      // 2) Fallback: at-home client (Node) login.
      final clientOk = await ref.read(clientAuthProvider.notifier).login(
            clientName: username,
            password: password,
          );
      if (clientOk) {
        return; // router redirects to session setup
      }

      // Both failed — surface the most specific message (the client backend
      // returns "Lease is not active" / "Invalid credentials").
      final clientErr = ref.read(clientAuthProvider).error;
      final practErr = ref.read(authStateProvider).error;
      _showError(clientErr ?? practErr ?? 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ThemeConstants.error),
    );
  }

  void _openOnboarding() {
    // Account creation runs in the NATIVE onboarding flow (parity with the web's
    // 4-step practitioner onboarding) — no external/in-app web page.
    context.push(RoutePaths.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = RefPalette.of(context);
    // Errors are surfaced manually in [_login] so a failed practitioner attempt
    // doesn't flash an error before the client-login fallback runs.

    return AuthPage(
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// Logo — same size and BETA badge as before.
              AnimatedEntrance(
                child: Center(
                  child: SizedBox(
                    width: 340,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        isDark
                            ? Image.asset(
                                'assets/images/White_Hydrawav3_Logo.png',
                                height: 62,
                                fit: BoxFit.contain,
                              )
                            : SvgPicture.asset(
                                'assets/images/Hydrawav3_Black_Logo.svg',
                                height: 120,
                                fit: BoxFit.contain,
                              ),
                        Positioned(
                          top: 6,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ThemeConstants.accent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeConstants.accent
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'BETA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                'Practitioner sign in',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.ink3),
              ),
              const SizedBox(height: 22),

              /// `.authwrap .card` — labelled fields.
              AnimatedEntrance(
                index: 1,
                child: AuthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthField(
                        controller: _userCtrl,
                        label: 'Username',
                        hint: 'Your username',
                        action: TextInputAction.next,
                        autofill: const [AutofillHints.username],
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      AuthField(
                        controller: _passCtrl,
                        label: 'Password',
                        hint: 'Your password',
                        obscure: _obscure,
                        action: TextInputAction.done,
                        autofill: const [AutofillHints.password],
                        onSubmitted: (_) => _login(),
                        suffix: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: p.ink3,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedEntrance(
                index: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthPrimaryButton(
                      label: 'Sign in',
                      busy: _submitting,
                      onTap: _login,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AuthOutlineButton(
                            label: 'Create account',
                            onTap: _openOnboarding,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AuthOutlineButton(
                            label: 'Forgot password',
                            onTap: () =>
                                context.push(RoutePaths.forgotPassword),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
