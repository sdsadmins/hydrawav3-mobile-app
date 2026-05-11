import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  Future<void> _openOnboarding() async {
    final uri = Uri.parse('https://hydrawav3.app/onboarding.html');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open onboarding page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        decoration: BoxDecoration(color: ThemeConstants.background),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    /// Logo
                    AnimatedEntrance(
                      child: Column(
                        children: [
                          SizedBox(
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
                                    child: Text(
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
                                decoration:
                                    InputDecoration(hintText: 'Username'),
                                validator: (v) => (v == null || v.isEmpty)
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
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Required'
                                    : null,
                              ),

                              const SizedBox(height: 20),

                              /// ✅ FIXED BUTTON (NO ERROR)
                              SizedBox(
                                width: double.infinity,
                                child: _GradientCTA(
                                  label: 'Login',
                                  isLoading: auth.isLoading,
                                  onTap: _login,
                                ),
                              ),
                              const SizedBox(height: 14),
                              GestureDetector(
                                onTap: _openOnboarding,
                                child: Text.rich(
                                  TextSpan(
                                    text: "Don't have an account? ",
                                    style: TextStyle(
                                      color: ThemeConstants.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Create New Account',
                                        style: TextStyle(
                                          color: ThemeConstants.accent,
                                          decoration: TextDecoration.underline,
                                          decorationColor:
                                              ThemeConstants.accent,
                                          decorationThickness: 2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
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

  final bool isLoading;
  final VoidCallback onTap;

  const _GradientCTA({
    required this.label,
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
          color: ThemeConstants.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: TextStyle(color: Colors.white)),
                    const SizedBox(width: 8),
                  ],
                ),
        ),
      ),
    );
  }
}
