import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_text_field.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    // TODO: Implement forgot password API call
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _isSubmitting = false;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Forgot Password'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ThemeConstants.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _submitted ? _buildSuccess() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset, size: 64, color: ThemeConstants.primaryColor),
          const SizedBox(height: ThemeConstants.spacingMd),
          Text(
            'Reset your password',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ThemeConstants.spacingSm),
          Text(
            'Enter your email address and we\'ll send you a link to reset your password.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ThemeConstants.spacingXl),
          HwTextField(
            controller: _emailController,
            label: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Invalid email';
              return null;
            },
          ),
          const SizedBox(height: ThemeConstants.spacingLg),
          HwButton(
            label: 'Send Reset Link',
            onPressed: _handleSubmit,
            isLoading: _isSubmitting,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const Icon(Icons.check_circle, size: 80, color: ThemeConstants.success),
        const SizedBox(height: ThemeConstants.spacingMd),
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ThemeConstants.spacingSm),
        Text(
          'We\'ve sent a password reset link to ${_emailController.text}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ThemeConstants.spacingLg),
        HwButton(
          label: 'Back to Login',
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
