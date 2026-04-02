import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class ChangePasswordScreen extends ConsumerWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Change Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Current Password', prefixIcon: Icon(Icons.lock_outline_rounded, color: ThemeConstants.textTertiary, size: 20))),
            const SizedBox(height: 12),
            TextFormField(obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'New Password', prefixIcon: Icon(Icons.lock_rounded, color: ThemeConstants.textTertiary, size: 20))),
            const SizedBox(height: 12),
            TextFormField(obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Confirm New Password', prefixIcon: Icon(Icons.lock_rounded, color: ThemeConstants.textTertiary, size: 20))),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(onPressed: () {}, child: const Text('Update Password'))),
          ],
        ),
      ),
    );
  }
}
