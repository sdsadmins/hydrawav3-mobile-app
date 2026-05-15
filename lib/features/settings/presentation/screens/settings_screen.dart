import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/network/dio_client.dart'; // ✅ ADD

final organizationProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final dio = ref.read(djangoDioProvider);
    final response = await dio.get('/admin/organizations');

    // Debug: Print response data
    print('ORG RESPONSE: ${response.data}');
    print('ORG RESPONSE TYPE: ${response.data.runtimeType}');

    List<Map<String, dynamic>> orgs = [];

    // Handle different response formats more robustly
    if (response.data is List) {
      // Direct list response
      orgs = List<Map<String, dynamic>>.from(
          response.data.map((item) => Map<String, dynamic>.from(item)));
    } else if (response.data is Map) {
      // Check for common pagination patterns
      final data = response.data as Map<String, dynamic>;
      if (data['results'] is List) {
        orgs = List<Map<String, dynamic>>.from((data['results'] as List)
            .map((item) => Map<String, dynamic>.from(item)));
      } else if (data['data'] is List) {
        orgs = List<Map<String, dynamic>>.from((data['data'] as List)
            .map((item) => Map<String, dynamic>.from(item)));
      } else {
        // Try to convert the entire map to a list with one item
        orgs = [Map<String, dynamic>.from(data)];
      }
    } else {
      throw Exception(
          'Unexpected response format: ${response.data.runtimeType}');
    }

    print('PROCESSED ORGS COUNT: ${orgs.length}');
    print('PROCESSED ORGS: $orgs');

    return orgs;
  } catch (e) {
    // Handle DioException and other errors
    print('ORG ERROR: $e');
    print('ORG ERROR TYPE: ${e.runtimeType}');
    throw Exception('Failed to load organizations: ${e.toString()}');
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showOrganizationBottomSheet(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> orgAsync,
    AuthState auth,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: ThemeConstants.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Organization',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the organization you want to work with',
              style: TextStyle(
                fontSize: 14,
                color: ThemeConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            orgAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: ThemeConstants.error,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load organizations',
                      style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString().contains('DioException')
                          ? 'Network error. Please check your connection.'
                          : 'Please try again later.',
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        // Invalidate and wait for refresh
                        ref.invalidate(organizationProvider);

                        // Wait a bit for provider to refresh, then re-open
                        await Future.delayed(const Duration(milliseconds: 300));

                        if (context.mounted) {
                          _showOrganizationBottomSheet(
                              context,
                              ref,
                              ref.watch(organizationProvider),
                              ref.read(authStateProvider));
                        }
                      },
                      icon: Icon(Icons.refresh_rounded, size: 18),
                      label: Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              data: (orgs) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: orgs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final org = orgs[index];
                    final orgId = org['id'].toString();
                    final isSelected = orgId == auth.selectedOrgId;

                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);

                        // Update organization without redirecting
                        await ref
                            .read(authStateProvider.notifier)
                            .setOrganization(
                              orgId,
                              org['name'] ?? 'Organization',
                            );

                        // Show success message
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Switched to ${org['name']}'),
                              backgroundColor: ThemeConstants.accent,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ThemeConstants.accent.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? ThemeConstants.accent
                                : ThemeConstants.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? ThemeConstants.accent
                                        .withValues(alpha: 0.2)
                                    : ThemeConstants.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.business_rounded,
                                size: 20,
                                color: isSelected
                                    ? ThemeConstants.accent
                                    : ThemeConstants.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    org['name'] ?? 'Organization',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? ThemeConstants.accent
                                          : ThemeConstants.textPrimary,
                                    ),
                                  ),
                                  if (org['description'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      org['description'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: ThemeConstants.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: ThemeConstants.accent,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final auth = ref.watch(authStateProvider); // ✅ ADD
    final orgAsync = ref.watch(organizationProvider); // ✅ ADD
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // Gradient header with profile
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(color: ThemeConstants.background),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Settings',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: ThemeConstants.textPrimary,
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
                                  color: ThemeConstants.accent
                                      .withValues(alpha: 0.14),
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
                                  style: TextStyle(
                                      color: ThemeConstants.textPrimary,
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
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeConstants.textPrimary)),
                                  if (user?.email != null)
                                    Text(user!.email!,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                ThemeConstants.textTertiary)),
                                ],
                              )),
                              Icon(Icons.chevron_right_rounded,
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
                          trailing: _comingSoonBadge()),
                    ])),
                const SizedBox(height: 16),

                // Appearance
                AnimatedEntrance(
                    index: 2,
                    child: _SettingsGroup(title: 'APPEARANCE', items: [
                      _Item(Icons.dark_mode_outlined, 'Dark Mode',
                          trailing: Switch.adaptive(
                              value: isDarkMode,
                              onChanged: (value) => ref
                                  .read(themeModeProvider.notifier)
                                  .toggleDarkMode(value),
                              activeColor: ThemeConstants.accent)),
                    ])),
                const SizedBox(height: 16),

                // Device
                AnimatedEntrance(
                    index: 3,
                    child: _SettingsGroup(title: 'DEVICE', items: [
                      _Item(
                          Icons.app_registration_rounded, 'Device Registration',
                          onTap: () => context.push(RoutePaths.deviceRegister)),
                      _Item(Icons.verified_user_outlined, 'Warranty Status',
                          trailing: _comingSoonBadge()),
                    ])),
                const SizedBox(height: 16),

                // General
                AnimatedEntrance(
                    index: 4,
                    child: _SettingsGroup(title: 'GENERAL', items: [
                      _Item(Icons.notifications_outlined, 'Notifications',
                          trailing: _comingSoonBadge()),
                      _Item(Icons.shield_outlined, 'Privacy & Security'),
                      _Item(Icons.help_outline_rounded, 'Help & Support',
                          onTap: () => launchUrl(
                              Uri.parse('https://hydrawav3.app/help'))),
                      _Item(Icons.payment_outlined, 'Payment Methods',
                          trailing: _comingSoonBadge()),
                    ])),
                const SizedBox(height: 16),

                // Legal
                AnimatedEntrance(
                    index: 5,
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
                  index: 6,
                  child: _SettingsGroup(
                    title: 'ORGANIZATION',
                    items: [
                      _Item(
                        Icons.business_rounded,
                        'Switch Organization',
                        onTap: () => _showOrganizationBottomSheet(context, ref,
                            ref.watch(organizationProvider), auth),
                        trailing: orgAsync.when(
                          loading: () => const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, __) =>
                              Icon(Icons.error, color: Colors.red),
                          data: (orgs) {
                            String orgName = 'None';
                            if (auth.selectedOrgId != null) {
                              try {
                                final currentOrg = orgs.firstWhere(
                                  (org) =>
                                      org['id'].toString() ==
                                      auth.selectedOrgId,
                                );
                                orgName = currentOrg['name'] ?? 'Unknown';
                              } catch (e) {
                                orgName = 'Not Found';
                              }
                            }
                            return Text(
                              orgName,
                              style: TextStyle(
                                fontSize: 13,
                                color: ThemeConstants.textSecondary,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Logout
                AnimatedEntrance(
                    index: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            await ref.read(authStateProvider.notifier).logout();
                            // Clear organization provider cache to fetch fresh data on next login
                            ref.invalidate(organizationProvider);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Log Out',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                    style: TextStyle(
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
      gradientColors: [ThemeConstants.surface],
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const GlowIconBox(icon: Icons.workspace_premium_rounded),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Free Tier',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ThemeConstants.textPrimary)),
              SizedBox(height: 2),
              Text('Upgrade for advanced features',
                  style: TextStyle(
                      fontSize: 13, color: ThemeConstants.textSecondary)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ThemeConstants.accent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: ThemeConstants.accent.withValues(alpha: 0.25),
                    blurRadius: 8)
              ],
            ),
            child: Text('Upgrade',
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
                  style: TextStyle(
                      fontSize: 14, color: ThemeConstants.textPrimary))),
          trailing ??
              (onTap != null
                  ? Icon(Icons.chevron_right_rounded,
                      color: ThemeConstants.textTertiary, size: 18)
                  : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

Widget _comingSoonBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: ThemeConstants.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: ThemeConstants.accent.withValues(alpha: 0.3),
        width: 0.5,
      ),
    ),
    child: Text(
      'Coming Soon',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: ThemeConstants.accent,
      ),
    ),
  );
}
