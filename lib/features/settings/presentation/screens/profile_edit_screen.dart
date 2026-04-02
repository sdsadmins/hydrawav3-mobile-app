import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Name', prefixIcon: Icon(Icons.person_outline_rounded, color: ThemeConstants.textTertiary, size: 20))),
            const SizedBox(height: 12),
            TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextFormField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, color: ThemeConstants.textTertiary, size: 20)), keyboardType: TextInputType.phone),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(onPressed: () {}, child: const Text('Save Changes'))),
          ],
        ),
      ),
    );
  }
}
