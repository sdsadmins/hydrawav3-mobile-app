import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_text_field.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwTextField(
                controller: _oldPasswordController,
                label: 'Current Password',
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              const SizedBox(height: ThemeConstants.spacingMd),
              HwTextField(
                controller: _newPasswordController,
                label: 'New Password',
                obscureText: true,
                prefixIcon: const Icon(Icons.lock),
                validator: (v) {
                  if (v == null || v.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: ThemeConstants.spacingMd),
              HwTextField(
                controller: _confirmController,
                label: 'Confirm New Password',
                obscureText: true,
                prefixIcon: const Icon(Icons.lock),
                validator: (v) {
                  if (v != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: ThemeConstants.spacingLg),
              HwButton(
                label: 'Update Password',
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    // TODO: Call changePassword API
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
