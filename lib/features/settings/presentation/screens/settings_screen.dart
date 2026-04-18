import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/network/dio_client.dart'; // ✅ ADD
import '../../../protocols/data/protocol_repository.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';

final organizationProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(djangoDioProvider);
  final response = await dio.get('/admin/organizations');
  return List<Map<String, dynamic>>.from(response.data);
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final auth = ref.watch(authStateProvider); // ✅ ADD
    final orgAsync = ref.watch(organizationProvider); // ✅ ADD
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // Gradient header with profile
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3040), ThemeConstants.background],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Settings',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 16),
                        // Profile card
                        GradientCard(
                          showGlow: true,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    ThemeConstants.accent,
                                    Color(0xFFE09060)
                                  ]),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                        color: ThemeConstants.accent
                                            .withValues(alpha: 0.25),
                                        blurRadius: 10)
                                  ],
                                ),
                                child: Center(
                                    child: Text(
                                  user?.displayName.isNotEmpty == true
                                      ? user!.displayName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700),
                                )),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user?.displayName ?? 'User',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                  if (user?.email != null)
                                    Text(user!.email!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color:
                                                ThemeConstants.textTertiary)),
                                ],
                              )),
                              const Icon(Icons.chevron_right_rounded,
                                  color: ThemeConstants.textTertiary, size: 20),
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

          // Settings sections
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Subscription
                AnimatedEntrance(index: 0, child: _SubscriptionCard()),
                const SizedBox(height: 20),

                // Account
                AnimatedEntrance(
                    index: 1,
                    child: _SettingsGroup(title: 'ACCOUNT', items: [
                      _Item(Icons.person_outline_rounded, 'Edit Profile',
                          onTap: () => context.push(RoutePaths.profileEdit)),
                      _Item(Icons.lock_outline_rounded, 'Change Password',
                          onTap: () => context.push(RoutePaths.changePassword)),
                      _Item(Icons.fingerprint_rounded, 'Biometric Login',
                          trailing: Switch.adaptive(
                              value: false,
                              onChanged: (_) {},
                              activeColor: ThemeConstants.accent)),
                    ])),
                const SizedBox(height: 16),

                // Device
                AnimatedEntrance(
                    index: 2,
                    child: _SettingsGroup(title: 'DEVICE', items: [
                      _Item(
                          Icons.app_registration_rounded, 'Device Registration',
                          onTap: () => context.push(RoutePaths.deviceRegister)),
                      _Item(Icons.verified_user_outlined, 'Warranty Status'),
                    ])),
                const SizedBox(height: 16),

                // General
                AnimatedEntrance(
                    index: 3,
                    child: _SettingsGroup(title: 'GENERAL', items: [
                      _Item(Icons.notifications_outlined, 'Notifications'),
                      _Item(Icons.shield_outlined, 'Privacy & Security'),
                      _Item(Icons.help_outline_rounded, 'Help & Support',
                          onTap: () => launchUrl(
                              Uri.parse('https://hydrawav3.app/help'))),
                      _Item(Icons.payment_outlined, 'Payment Methods'),
                    ])),
                const SizedBox(height: 16),

                // Legal
                AnimatedEntrance(
                    index: 4,
                    child: _SettingsGroup(title: 'LEGAL', items: [
                      _Item(Icons.privacy_tip_outlined, 'Privacy Policy',
                          onTap: () => launchUrl(
                              Uri.parse(AppConstants.privacyPolicyUrl))),
                      _Item(Icons.description_outlined, 'Terms & Conditions',
                          onTap: () =>
                              launchUrl(Uri.parse(AppConstants.termsUrl))),
                    ])),
                const SizedBox(height: 20),
                const SizedBox(height: 16),

                /// ✅ SWITCH ORGANIZATION (NEW SECTION)
                AnimatedEntrance(
                  index: 5,
                  child: _SettingsGroup(
                    title: 'ORGANIZATION',
                    items: [
                      _Item(
                        Icons.business_rounded,
                        'Switch Organization',
                        trailing: orgAsync.when(
                          loading: () => const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, __) =>
                              const Icon(Icons.error, color: Colors.red),
                          data: (orgs) {
                            final validOrgId = orgs.any(
                              (org) =>
                                  org['id'].toString() == auth.selectedOrgId,
                            )
                                ? auth.selectedOrgId
                                : null;

                            return DropdownButton<String>(
                              value: validOrgId,
                              dropdownColor: ThemeConstants.surface,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white),
                              items: orgs.map((org) {
                                return DropdownMenuItem<String>(
                                  value: org['id'].toString(),
                                  child: Text(
                                    org['name'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;

                                final selectedOrg = orgs.firstWhere(
                                  (org) => org['id'].toString() == value,
                                );

                                ref
                                    .read(authStateProvider.notifier)
                                    .setOrganization(
                                      value,
                                      selectedOrg['name'],
                                    );

                                ref.invalidate(protocolRepositoryProvider);
                                ref.invalidate(protocolListProvider);

                                context.go(RoutePaths.protocols);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Logout
                AnimatedEntrance(
                    index: 6,
                    child: GradientCard(
                      onTap: () =>
                          ref.read(authStateProvider.notifier).logout(),
                      gradientColors: [
                        ThemeConstants.error.withValues(alpha: 0.08),
                        ThemeConstants.error.withValues(alpha: 0.04)
                      ],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded,
                              color: ThemeConstants.error, size: 18),
                          SizedBox(width: 8),
                          Text('Log Out',
                              style: TextStyle(
                                  color: ThemeConstants.error,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),

                // Version
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (c, s) => Center(
                      child: Text(
                    s.data != null
                        ? 'Version ${s.data!.version} (Build ${s.data!.buildNumber})'
                        : '',
                    style: const TextStyle(
                        fontSize: 12, color: ThemeConstants.textTertiary),
                  )),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GradientCard(
      showGlow: true,
      gradientColors: [
        ThemeConstants.accent.withValues(alpha: 0.08),
        ThemeConstants.surface
      ],
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const GlowIconBox(icon: Icons.workspace_premium_rounded),
          const SizedBox(width: 14),
          const Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Free Tier',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              SizedBox(height: 2),
              Text('Upgrade for advanced features',
                  style: TextStyle(
                      fontSize: 13, color: ThemeConstants.textSecondary)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [ThemeConstants.accent, Color(0xFFE09060)]),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: ThemeConstants.accent.withValues(alpha: 0.25),
                    blurRadius: 8)
              ],
            ),
            child: const Text('Upgrade',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _SettingsGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        Container(
          decoration: BoxDecoration(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ThemeConstants.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            children: items
                .asMap()
                .entries
                .map((e) => Column(children: [
                      e.value,
                      if (e.key < items.length - 1)
                        Divider(
                            height: 1,
                            indent: 52,
                            color:
                                ThemeConstants.border.withValues(alpha: 0.5)),
                    ]))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _Item(this.icon, this.title, {this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Icon(icon, color: ThemeConstants.accent, size: 20),
          const SizedBox(width: 14),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 14, color: Colors.white))),
          trailing ??
              (onTap != null
                  ? const Icon(Icons.chevron_right_rounded,
                      color: ThemeConstants.textTertiary, size: 18)
                  : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}
