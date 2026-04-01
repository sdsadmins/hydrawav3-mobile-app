import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_text_field.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwTextField(
                controller: _nameController,
                label: 'Name',
                prefixIcon: const Icon(Icons.person_outline),
              ),
              const SizedBox(height: ThemeConstants.spacingMd),
              HwTextField(
                controller: _emailController,
                label: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: ThemeConstants.spacingMd),
              HwTextField(
                controller: _phoneController,
                label: 'Phone',
                prefixIcon: const Icon(Icons.phone_outlined),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: ThemeConstants.spacingLg),
              HwButton(
                label: 'Save Changes',
                onPressed: () {
                  // TODO: Update profile via API
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
