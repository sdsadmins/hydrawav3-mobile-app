import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/glass_container.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: false,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ThemeConstants.darkTeal, ThemeConstants.teal],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⚙️ Settings',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 16),
                        // Profile card
                        GlassContainer(
                          opacity: 0.08,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      ThemeConstants.copper,
                                      ThemeConstants.tanLight
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    authState.user?.displayName.isNotEmpty ==
                                            true
                                        ? authState.user!.displayName[0]
                                            .toUpperCase()
                                        : '👤',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      authState.user?.displayName ?? 'User',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    if (authState.user?.email != null)
                                      Text(
                                        authState.user!.email!,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                            fontSize: 13),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white54),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMd),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionLabel('👤 Account'),
                _SettingsTile(
                  emoji: '✏️',
                  icon: Icons.person_outline_rounded,
                  title: 'Edit Profile',
                  onTap: () => context.push(RoutePaths.profileEdit),
                ),
                _SettingsTile(
                  emoji: '🔑',
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  onTap: () => context.push(RoutePaths.changePassword),
                ),
                _SettingsTile(
                  emoji: '🔐',
                  icon: Icons.fingerprint_rounded,
                  title: 'Biometric Login',
                  trailing: Switch.adaptive(
                    value: false,
                    onChanged: (v) {},
                    activeColor: ThemeConstants.darkTeal,
                  ),
                ),
                const SizedBox(height: 8),
                _SectionLabel('💎 Subscription'),
                _SettingsTile(
                  emoji: '⭐',
                  icon: Icons.workspace_premium_rounded,
                  title: 'Subscription Status',
                  subtitle: 'Free Plan',
                  onTap: () => context.push(RoutePaths.subscription),
                ),
                const SizedBox(height: 8),
                _SectionLabel('💡 Support'),
                _SettingsTile(
                  emoji: '📚',
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Tutorials',
                  onTap: () =>
                      launchUrl(Uri.parse('https://hydrawav3.app/help')),
                ),
                _SettingsTile(
                  emoji: '📧',
                  icon: Icons.contact_support_outlined,
                  title: 'Contact Support',
                  subtitle: AppConstants.supportEmail,
                  onTap: () => launchUrl(
                      Uri.parse('mailto:${AppConstants.supportEmail}')),
                ),
                const SizedBox(height: 8),
                _SectionLabel('📋 Legal'),
                _SettingsTile(
                  emoji: '🔏',
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () =>
                      launchUrl(Uri.parse(AppConstants.privacyPolicyUrl)),
                ),
                _SettingsTile(
                  emoji: '📄',
                  icon: Icons.description_outlined,
                  title: 'Terms & Conditions',
                  onTap: () => launchUrl(Uri.parse(AppConstants.termsUrl)),
                ),
                const SizedBox(height: 8),
                _SectionLabel('ℹ️ App'),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    return _SettingsTile(
                      emoji: '📱',
                      icon: Icons.info_outline_rounded,
                      title: 'App Version',
                      subtitle: snapshot.data != null
                          ? 'v${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                          : '...',
                    );
                  },
                ),
                const SizedBox(height: 24),
                // Logout
                GlassCard(
                  onTap: () async {
                    await ref.read(authStateProvider.notifier).logout();
                  },
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded,
                          color: ThemeConstants.error, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '🚪 Log Out',
                        style: TextStyle(
                          color: ThemeConstants.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String emoji;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.emoji,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ThemeConstants.darkTeal.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: ThemeConstants.darkTeal, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$emoji $title',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            trailing ??
                (onTap != null
                    ? const Icon(Icons.chevron_right_rounded,
                        color: ThemeConstants.textTertiary, size: 20)
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
