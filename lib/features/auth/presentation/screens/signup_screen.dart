import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/theme_constants.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Create Account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: ThemeConstants.border)),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Join Hydrawav3', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 4),
                    const Text('Create your account to get started', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                    const SizedBox(height: 24),
                    TextFormField(controller: _nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Full Name', prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20)), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                    const SizedBox(height: 12),
                    TextFormField(controller: _emailCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.emailAddress, validator: (v) { if (v == null || !v.contains('@')) return 'Invalid email'; return null; }),
                    const SizedBox(height: 12),
                    TextFormField(controller: _passCtrl, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded, color: ThemeConstants.textTertiary, size: 20)), validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null),
                    const SizedBox(height: 12),
                    TextFormField(controller: _confirmCtrl, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Confirm Password', prefixIcon: Icon(Icons.lock_outline_rounded, color: ThemeConstants.textTertiary, size: 20)), validator: (v) => v != _passCtrl.text ? 'Passwords do not match' : null),
                    const SizedBox(height: 24),
                    SizedBox(height: 48, child: ElevatedButton(onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      final uri = Uri.parse('https://hydrawav3.app/signup');
                      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }, child: const Text('Create Account'))),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Already have an account? ', style: TextStyle(color: ThemeConstants.textSecondary, fontSize: 13)),
                      GestureDetector(onTap: () => context.pop(), child: const Text('Sign In', style: TextStyle(color: ThemeConstants.accent, fontWeight: FontWeight.w600, fontSize: 13))),
                    ]),
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
