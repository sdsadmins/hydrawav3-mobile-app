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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Profile section
          if (authState.user != null)
            _ProfileHeader(user: authState.user!),

          const _SectionHeader('Account'),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Edit Profile',
            onTap: () => context.push(RoutePaths.profileEdit),
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            onTap: () => context.push(RoutePaths.changePassword),
          ),
          _SettingsTile(
            icon: Icons.fingerprint,
            title: 'Biometric Login',
            trailing: Switch(
              value: false, // TODO: Read from biometric service
              onChanged: (v) {
                // TODO: Toggle biometric
              },
            ),
          ),

          const _SectionHeader('Subscription'),
          _SettingsTile(
            icon: Icons.star_outline,
            title: 'Subscription Status',
            subtitle: 'Free Plan',
            onTap: () => context.push(RoutePaths.subscription),
          ),

          const _SectionHeader('Support'),
          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Help & Tutorials',
            onTap: () => launchUrl(Uri.parse('https://hydrawav3.app/help')),
          ),
          _SettingsTile(
            icon: Icons.contact_support_outlined,
            title: 'Contact Support',
            subtitle: AppConstants.supportEmail,
            onTap: () => launchUrl(
                Uri.parse('mailto:${AppConstants.supportEmail}')),
          ),

          const _SectionHeader('Legal'),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () =>
                launchUrl(Uri.parse(AppConstants.privacyPolicyUrl)),
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            onTap: () => launchUrl(Uri.parse(AppConstants.termsUrl)),
          ),

          const _SectionHeader('App'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              return _SettingsTile(
                icon: Icons.info_outline,
                title: 'App Version',
                subtitle: snapshot.data != null
                    ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : 'Loading...',
              );
            },
          ),

          const SizedBox(height: ThemeConstants.spacingLg),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacingMd),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authStateProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout, color: ThemeConstants.error),
              label: const Text('Log Out',
                  style: TextStyle(color: ThemeConstants.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: ThemeConstants.error),
              ),
            ),
          ),
          const SizedBox(height: ThemeConstants.spacingXl),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final dynamic user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeConstants.spacingLg),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: ThemeConstants.primaryColor,
            child: Text(
              (user.displayName as String?)?.isNotEmpty == true
                  ? (user.displayName as String)[0].toUpperCase()
                  : 'U',
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: ThemeConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? 'User',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (user.email != null)
                  Text(
                    user.email!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacingMd,
        ThemeConstants.spacingLg,
        ThemeConstants.spacingMd,
        ThemeConstants.spacingSm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: ThemeConstants.textTertiary,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }
}
