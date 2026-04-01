import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_text_field.dart';

class DeviceRegisterScreen extends ConsumerStatefulWidget {
  const DeviceRegisterScreen({super.key});

  @override
  ConsumerState<DeviceRegisterScreen> createState() =>
      _DeviceRegisterScreenState();
}

class _DeviceRegisterScreenState extends ConsumerState<DeviceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _serialController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    // TODO: POST to /admin/sensors + add to paired devices DB
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isSubmitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device registered successfully')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.bluetooth_connected,
                  size: 64, color: ThemeConstants.primaryColor),
              const SizedBox(height: ThemeConstants.spacingMd),
              Text(
                'Register a new device',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ThemeConstants.spacingXl),
              HwTextField(
                controller: _serialController,
                label: 'Serial Number / MAC Address',
                hint: 'e.g., AA:BB:CC:DD:EE:FF',
                prefixIcon: const Icon(Icons.qr_code),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: ThemeConstants.spacingMd),
              HwTextField(
                controller: _nameController,
                label: 'Device Name',
                hint: 'e.g., My Hydrawav3',
                prefixIcon: const Icon(Icons.label_outline),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: ThemeConstants.spacingLg),
              HwButton(
                label: 'Register Device',
                onPressed: _handleRegister,
                isLoading: _isSubmitting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
