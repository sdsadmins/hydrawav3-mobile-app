import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';

class DeviceRegisterScreen extends ConsumerStatefulWidget {
  const DeviceRegisterScreen({super.key});
  @override
  ConsumerState<DeviceRegisterScreen> createState() => _State();
}

class _State extends ConsumerState<DeviceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() { _serialCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Register Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: ThemeConstants.border)),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.bluetooth_connected_rounded, size: 40, color: ThemeConstants.accent),
                const SizedBox(height: 16),
                const Text('Register a new device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(controller: _serialCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Serial Number / MAC Address', prefixIcon: Icon(Icons.qr_code_rounded, color: ThemeConstants.textTertiary, size: 20)), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Device Name', prefixIcon: Icon(Icons.label_outline_rounded, color: ThemeConstants.textTertiary, size: 20)), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 24),
                SizedBox(height: 48, child: ElevatedButton(
                  onPressed: _submitting ? null : () async {
                    if (!_formKey.currentState!.validate()) return;
                    setState(() => _submitting = true);
                    await Future.delayed(const Duration(seconds: 1));
                    setState(() => _submitting = false);
                    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device registered'))); context.pop(); }
                  },
                  child: _submitting ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Register Device'),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
