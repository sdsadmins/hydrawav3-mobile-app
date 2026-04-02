import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card — matching reference: orange avatar, name, email
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: ThemeConstants.accent, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(
                    user?.displayName.isNotEmpty == true ? user!.displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  )),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.displayName ?? 'User', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      if (user?.email != null) Text(user!.email!, style: const TextStyle(fontSize: 13, color: ThemeConstants.textTertiary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: ThemeConstants.textTertiary, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Subscription — matching reference: Free Tier + Upgrade button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SUBSCRIPTION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Free Tier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        SizedBox(height: 2),
                        Text('Basic features', style: TextStyle(fontSize: 13, color: ThemeConstants.textTertiary)),
                      ],
                    ),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () => context.push(RoutePaths.subscription),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Upgrade to Pro'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Account section
          _Section(label: 'ACCOUNT', items: [
            _Tile(icon: Icons.person_outline_rounded, title: 'Edit Profile', onTap: () => context.push(RoutePaths.profileEdit)),
            _Tile(icon: Icons.lock_outline_rounded, title: 'Change Password', onTap: () => context.push(RoutePaths.changePassword)),
            _Tile(icon: Icons.fingerprint_rounded, title: 'Biometric Login', trailing: Switch.adaptive(value: false, onChanged: (_) {}, activeColor: ThemeConstants.accent)),
          ]),
          const SizedBox(height: 20),

          // Device section
          _Section(label: 'DEVICE', items: [
            _Tile(icon: Icons.app_registration_rounded, title: 'Device Registration', onTap: () => context.push(RoutePaths.deviceRegister)),
            _Tile(icon: Icons.verified_user_outlined, title: 'Warranty Status'),
          ]),
          const SizedBox(height: 20),

          // General section
          _Section(label: 'GENERAL', items: [
            _Tile(icon: Icons.notifications_outlined, title: 'Notifications'),
            _Tile(icon: Icons.shield_outlined, title: 'Privacy & Security'),
            _Tile(icon: Icons.help_outline_rounded, title: 'Help & Support', onTap: () => launchUrl(Uri.parse('https://hydrawav3.app/help'))),
            _Tile(icon: Icons.payment_outlined, title: 'Payment Methods'),
          ]),
          const SizedBox(height: 20),

          // Legal
          _Section(label: 'LEGAL', items: [
            _Tile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () => launchUrl(Uri.parse(AppConstants.privacyPolicyUrl))),
            _Tile(icon: Icons.description_outlined, title: 'Terms & Conditions', onTap: () => launchUrl(Uri.parse(AppConstants.termsUrl))),
          ]),
          const SizedBox(height: 20),

          // Logout
          Material(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => ref.read(authStateProvider.notifier).logout(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: ThemeConstants.error, size: 18),
                    SizedBox(width: 8),
                    Text('Log Out', style: TextStyle(color: ThemeConstants.error, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Version
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (ctx, snap) => Center(
              child: Text(
                snap.data != null ? 'Version ${snap.data!.version} (Build ${snap.data!.buildNumber})' : '',
                style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<_Tile> items;
  const _Section({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
        ),
        Container(
          decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final isLast = entry.key == items.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast) const Divider(height: 1, indent: 52, color: ThemeConstants.border),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _Tile({required this.icon, required this.title, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.white))),
            trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: ThemeConstants.textTertiary, size: 18) : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
