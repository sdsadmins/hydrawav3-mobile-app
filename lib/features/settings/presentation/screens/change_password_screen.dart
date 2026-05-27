import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../auth/data/auth_repository.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentPasswordController.text.trim(),
            newPassword: _newPasswordController.text.trim(),
            confirmPassword: _confirmPasswordController.text.trim(),
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      Navigator.of(context).pop();
    } on ServerException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update your password right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your current password.';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter a new password.';
    }
    if (trimmed.length < 8) {
      return 'Use at least 8 characters.';
    }
    if (trimmed == _currentPasswordController.text.trim()) {
      return 'New password must be different.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Confirm your new password.';
    }
    if (trimmed != _newPasswordController.text.trim()) {
      return 'Passwords do not match.';
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(
        icon,
        color: ThemeConstants.textTertiary,
        size: 20,
      ),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(
          obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: ThemeConstants.textTertiary,
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('Change Password'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: ThemeConstants.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update your password',
                      style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a strong password you do not use anywhere else.',
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrentPassword,
                      style: TextStyle(color: ThemeConstants.textPrimary),
                      decoration: _fieldDecoration(
                        hintText: 'Current Password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscureCurrentPassword,
                        onToggle: () => setState(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        }),
                      ),
                      validator: _validateCurrentPassword,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      style: TextStyle(color: ThemeConstants.textPrimary),
                      decoration: _fieldDecoration(
                        hintText: 'New Password',
                        icon: Icons.lock_rounded,
                        obscureText: _obscureNewPassword,
                        onToggle: () => setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        }),
                      ),
                      validator: _validateNewPassword,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      style: TextStyle(color: ThemeConstants.textPrimary),
                      decoration: _fieldDecoration(
                        hintText: 'Confirm New Password',
                        icon: Icons.lock_rounded,
                        obscureText: _obscureConfirmPassword,
                        onToggle: () => setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        }),
                      ),
                      validator: _validateConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isSubmitting) {
                          _submit();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
