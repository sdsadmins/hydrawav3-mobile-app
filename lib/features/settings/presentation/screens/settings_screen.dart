import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final initial = user?.displayName.isNotEmpty == true
        ? user!.displayName[0].toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Header ───
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
                        const Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ─── Profile Card ───
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ThemeConstants.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: ThemeConstants.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // 64px gradient avatar
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      ThemeConstants.accentLight,
                                      ThemeConstants.accentDark,
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4A2C17)
                                          .withValues(alpha: 0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Name + email
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user?.displayName ?? 'User',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: ThemeConstants.textPrimary,
                                      ),
                                    ),
                                    if (user?.email != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          user!.email!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: ThemeConstants.textSecondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Edit button
                              GestureDetector(
                                onTap: () =>
                                    context.push(RoutePaths.profileEdit),
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: ThemeConstants.accentDark,
                                  ),
                                ),
                              ),
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

          // ─── Body sections ───
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── Subscription ───
                const AnimatedEntrance(
                  index: 0,
                  child: _SubscriptionCard(),
                ),
                const SizedBox(height: 24),

                // ─── Appearance ───
                const AnimatedEntrance(
                  index: 1,
                  child: _AppearanceSection(),
                ),
                const SizedBox(height: 24),

                // ─── Device Registration & Warranty ───
                const AnimatedEntrance(
                  index: 2,
                  child: _DeviceWarrantySection(),
                ),
                const SizedBox(height: 24),

                // ─── General ───
                AnimatedEntrance(
                  index: 3,
                  child: _SettingsGroup(
                    title: 'GENERAL',
                    items: [
                      _Item(
                        Icons.notifications_outlined,
                        'Notifications',
                        onTap: () {},
                      ),
                      _Item(
                        Icons.shield_outlined,
                        'Privacy & Security',
                        onTap: () {},
                      ),
                      _Item(
                        Icons.help_outline_rounded,
                        'Help & Support',
                        onTap: () => launchUrl(
                            Uri.parse('https://hydrawav3.app/help')),
                      ),
                      _Item(
                        Icons.payment_outlined,
                        'Payment Methods',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ─── Logout ───
                AnimatedEntrance(
                  index: 4,
                  child: Consumer(
                    builder: (context, ref, _) => Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () =>
                            ref.read(authStateProvider.notifier).logout(),
                        borderRadius: BorderRadius.circular(16),
                        hoverColor: const Color(0xFFFEF2F2).withValues(alpha: 0.05),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: ThemeConstants.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: ThemeConstants.border,
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded,
                                  color: ThemeConstants.error, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Log Out',
                                style: TextStyle(
                                  color: ThemeConstants.error,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ─── Version ───
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (c, s) => Center(
                    child: Text(
                      s.data != null
                          ? 'Version ${s.data!.version} (Build ${s.data!.buildNumber})'
                          : '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription Card
// ─────────────────────────────────────────────────────────────────────────────

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard();

  @override
  Widget build(BuildContext context) {
    // TODO: Wire to real subscription state
    final bool isPro = false;
    final String planName = 'Free Tier';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('SUBSCRIPTION'),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ThemeConstants.surface, ThemeConstants.background],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ThemeConstants.border),
            ),
            child: Stack(
              children: [
                // Decorative blur circle - top right (copper)
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              ThemeConstants.accent.withValues(alpha: 0.15),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                // Decorative blur circle - bottom left (navy)
                Positioned(
                  bottom: -30,
                  left: -30,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ThemeConstants.surfaceVariant
                              .withValues(alpha: 0.3),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                // Content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Plan',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.metallic400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          planName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                        if (isPro) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ThemeConstants.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // CTA button
                    GestureDetector(
                      onTap: () => context.push(RoutePaths.subscription),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: ThemeConstants.background
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ThemeConstants.accent
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isPro ? 'Manage Subscription' : 'Upgrade to Pro',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ThemeConstants.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appearance Section
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  int _selected = 2; // 0=Light, 1=Dark, 2=System

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('APPEARANCE'),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ThemeConstants.border),
          ),
          child: Row(
            children: [
              _AppearanceButton(
                icon: Icons.wb_sunny_outlined,
                label: 'Light',
                isActive: _selected == 0,
                onTap: () => setState(() => _selected = 0),
              ),
              _AppearanceButton(
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
                isActive: _selected == 1,
                onTap: () => setState(() => _selected = 1),
              ),
              _AppearanceButton(
                icon: Icons.desktop_windows_outlined,
                label: 'System',
                isActive: _selected == 2,
                onTap: () => setState(() => _selected = 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _AppearanceButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? ThemeConstants.surfaceVariant
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? ThemeConstants.textPrimary
                    : ThemeConstants.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? ThemeConstants.textPrimary
                      : ThemeConstants.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device Registration & Warranty Section
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceWarrantySection extends StatelessWidget {
  const _DeviceWarrantySection();

  @override
  Widget build(BuildContext context) {
    // TODO: Wire to real device list
    final bool hasDevices = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('DEVICE REGISTRATION & WARRANTY'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ThemeConstants.border),
          ),
          child: hasDevices
              ? const _DeviceWarrantyCards()
              : const _DeviceEmptyState(),
        ),
      ],
    );
  }
}

class _DeviceEmptyState extends StatelessWidget {
  const _DeviceEmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: ThemeConstants.surfaceVariant.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.smartphone_rounded,
            color: ThemeConstants.textSecondary,
            size: 28,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'No devices registered',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ThemeConstants.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Register your Hydrawav3 device to activate warranty',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: ThemeConstants.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => context.push(RoutePaths.deviceRegister),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: ThemeConstants.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ThemeConstants.accent.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'Register Device',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DeviceWarrantyCards extends StatelessWidget {
  const _DeviceWarrantyCards();

  @override
  Widget build(BuildContext context) {
    // Placeholder for when devices exist
    return Column(
      children: [
        _DeviceWarrantyCard(
          name: 'Hydrawav3 Pro',
          serial: 'HW3-2024-00001',
          registeredDate: 'Jan 15, 2026',
          warrantyDuration: '2 Years',
        ),
      ],
    );
  }
}

class _DeviceWarrantyCard extends StatelessWidget {
  final String name;
  final String serial;
  final String registeredDate;
  final String warrantyDuration;

  const _DeviceWarrantyCard({
    required this.name,
    required this.serial,
    required this.registeredDate,
    required this.warrantyDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: ThemeConstants.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                    Text(
                      serial,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 2-col grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Registered',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      registeredDate,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.accent,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Warranty',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      warrantyDuration,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Extended warranty button
          GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: ThemeConstants.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ThemeConstants.accent.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      color: ThemeConstants.accent, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Purchase Extended Warranty',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeConstants.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Group + Item
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _SettingsGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title),
        Container(
          decoration: BoxDecoration(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ThemeConstants.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              return Column(
                children: [
                  e.value,
                  if (e.key < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 52,
                      color: ThemeConstants.border.withValues(alpha: 0.5),
                    ),
                ],
              );
            }).toList(),
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
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: ThemeConstants.textPrimary,
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Section Title
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
