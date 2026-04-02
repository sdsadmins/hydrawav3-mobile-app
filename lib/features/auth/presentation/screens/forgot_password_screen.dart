import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Reset Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: ThemeConstants.border)),
              child: _submitted ? Column(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 56, color: ThemeConstants.success),
                  const SizedBox(height: 16),
                  const Text('Check your email', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('We sent a reset link to ${_emailCtrl.text}', style: const TextStyle(fontSize: 14, color: ThemeConstants.textSecondary), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(height: 48, width: double.infinity, child: ElevatedButton(onPressed: () => context.pop(), child: const Text('Back to Login'))),
                ],
              ) : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Forgot your password?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Enter your email and we\'ll send you a reset link.', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                  const SizedBox(height: 24),
                  TextFormField(controller: _emailCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Email address', prefixIcon: Icon(Icons.email_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 20),
                  SizedBox(height: 48, child: ElevatedButton(onPressed: () => setState(() => _submitted = true), child: const Text('Send Reset Link'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
