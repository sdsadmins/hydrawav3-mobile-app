import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/theme/text_scale_provider.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../../core/utils/log_export.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../home/presentation/providers/hub_prefs_provider.dart';
import '../../../musics/presentation/providers/music_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../widgets/account_sheets.dart';
import '../widgets/org_sheets.dart';

/// The **More** tab — account, organizations, library, devices, session
/// defaults and settings, ported from the UI handoff spec's `renderMore`.
///
/// The class name stays `SettingsScreen` because the router, deep links and
/// `/settings/*` sub-routes all reference it; only the surface is new.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // -------------------------------------------------------------------------
  // Account deletion (unchanged behaviour)
  // -------------------------------------------------------------------------

  /// Normalize an account/profile response into a single mutable map.
  Map<String, dynamic> _accountMap(dynamic data) {
    if (data is List && data.isNotEmpty) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    if (data is Map) {
      final inner = data['data'];
      return Map<String, dynamic>.from(inner is Map ? inner : data);
    }
    throw Exception('Unexpected account response shape: ${data.runtimeType}');
  }

  /// Soft-delete the signed-in user's account. Pulls the full profile from the
  /// account endpoint (which carries firstName/lastName/dateOfBirth/country/
  /// state/city/address/address2/zip/phone/mail/companyId/userName/…), resends
  /// it unchanged except for `deleted: true`, then the caller logs the user out.
  Future<void> _deleteAccount(WidgetRef ref, String userId) async {
    final dio = ref.read(djangoDioProvider);
    final endpoint = ApiEndpoints.userAccountById(userId);

    appLogger.i('DeleteAccount: ▶ start (userId=$userId)');

    // /profile/me only returns a thin subset (and uses `email`, not `mail`).
    // The account endpoint returns the FULL object, so fetch it and resend it
    // complete with deleted=true.
    final res = await dio.get(endpoint);
    appLogger.i('DeleteAccount: ⇐ GET $endpoint → ${res.statusCode}');
    final account = _accountMap(res.data);
    account['deleted'] = true;

    try {
      final putRes = await dio.put(endpoint, data: account);
      appLogger.i('DeleteAccount: ⇐ PUT $endpoint → ${putRes.statusCode}');
    } on DioException catch (e) {
      appLogger.e('DeleteAccount: ❌ PUT $endpoint '
          'status=${e.response?.statusCode}\n'
          'SERVER BODY: ${e.response?.data}');
      rethrow;
    }
  }

  Future<void> _confirmAndDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final p = RefPalette.of(context);
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your account.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Delete account', style: TextStyle(color: p.ink)),
        content: Text(
          'This permanently deletes your account and logs you out. '
          'This action cannot be undone.',
          style: TextStyle(color: p.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: p.low),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _deleteAccount(ref, userId);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close loader
      }
      appLogger.i('DeleteAccount: logging out after deletion');
      await ref.read(authStateProvider.notifier).logout();
      ref.invalidate(organizationProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
      }
    } catch (e, st) {
      appLogger.e('DeleteAccount: ❌ failed for userId=$userId: $e\n$st');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);

    return Scaffold(
      backgroundColor: p.bg,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 108),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pageTitle(context),
                    const _AccountCard(),
                    const SizedBox(height: HwSpace.s5),
                    const _OrganizationsSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _AppearanceSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _PlanSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _LibrarySection(),
                    const SizedBox(height: HwSpace.s5),
                    const _DevicesSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _SessionDefaultsSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _SupportSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _ComingOnlineSection(),
                    const SizedBox(height: HwSpace.s5),
                    _BrandFooter(
                        onVersionTap: () => _showReleaseNotes(context)),
                    const SizedBox(height: HwSpace.s4),
                    _DangerButton(
                      icon: null,
                      // The spec's label is "Sign out — preview onboarding
                      // flow"; the trailing clause is demo-harness wording.
                      label: 'Sign out',
                      onTap: () async {
                        await ref.read(authStateProvider.notifier).logout();
                        ref.invalidate(organizationProvider);
                      },
                    ),
                    const SizedBox(height: HwSpace.s3),
                    _DangerButton(
                      icon: HwIcons.trash,
                      label: 'Delete account',
                      onTap: () => _confirmAndDeleteAccount(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageTitle(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, HwSpace.s4),
        child: Text(
          'More',
          style: TextStyle(
            fontSize: HwType.xxl,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.48,
            color: RefPalette.of(context).ink,
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // Sheets
  // -------------------------------------------------------------------------

  void _showReleaseNotes(BuildContext context) {
    final p = RefPalette.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Release notes',
                      style: TextStyle(
                        fontSize: HwType.xl,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Version ${AppConstants.appVersion}',
                      style: TextStyle(fontSize: HwType.base, color: p.ink2),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    AppConstants.releaseNotes,
                    style: TextStyle(
                        fontSize: HwType.sm, height: 1.6, color: p.ink2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: _SheetCloseButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Account
// ---------------------------------------------------------------------------

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final user = ref.watch(authStateProvider).user;
    final name = (user?.displayName ?? '').trim();
    final initials = name.isEmpty
        ? 'U'
        : name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join();

    // Non-interactive, per the spec — editing lives in Settings & support.
    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: p.sunGrad,
              borderRadius: BorderRadius.circular(HwRadius.md),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: HwType.md,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Your account' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                if (user?.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${user!.email} · one login',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2 · Your organizations
// ---------------------------------------------------------------------------

class _OrganizationsSection extends ConsumerWidget {
  const _OrganizationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final auth = ref.watch(authStateProvider);
    final orgs = ref.watch(organizationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: HwEyebrow('Your organizations')),
            orgs.maybeWhen(
              data: (list) => Text(
                '${list.length} org${list.length == 1 ? '' : 's'} · tap to switch',
                style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        orgs.when(
          loading: () => HwCard(
            child: Text(
              'Loading organizations…',
              style: TextStyle(fontSize: HwType.cap, color: p.ink3),
            ),
          ),
          error: (e, _) => HwCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Couldn\'t load your organizations.',
                    style: TextStyle(fontSize: HwType.cap, color: p.ink2),
                  ),
                ),
                HwPress(
                  onTap: () => ref.invalidate(organizationProvider),
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          data: (list) => Column(
            children: [
              for (final org in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: HwSpace.s2),
                  child: _OrgCard(
                    org: org,
                    active: org['id'].toString() == auth.selectedOrgId,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s1),
        // Opens the spec's sheet in place rather than pushing
        // `/select-organization?create=1`. That page is the LOGIN GATE — landing
        // on it just to add a second business reads as being signed out, and it
        // navigates away from More on success instead of returning here.
        AddOrganizationButton(
          onTap: () async {
            final created = await showAddOrganizationSheet(context);
            if (created == true) ref.invalidate(organizationProvider);
          },
        ),
      ],
    );
  }
}

class _OrgCard extends ConsumerWidget {
  final Map<String, dynamic> org;
  final bool active;
  const _OrgCard({required this.org, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final name = (org['name'] ?? 'Organization').toString();

    return HwCard(
      accented: active,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: active
          ? null
          : () async {
              await ref
                  .read(authStateProvider.notifier)
                  .setOrganization(org['id'].toString(), name);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Switched to $name')),
              );
              // Picking an organization is the start of working in it, so land
              // on the Session tab rather than leaving the practitioner parked
              // on More.
              context.go(RoutePaths.devices);
            },
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? p.tanSoft : p.bg2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: HwIcon(
                HwIcons.building,
                size: 20,
                color: active ? p.copperInk : p.ink3,
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                if (org['description'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    org['description'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
          if (active) const HwPill('Active', tone: HwPillTone.copper),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Appearance
// ---------------------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textScale = ref.watch(textScaleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Appearance'),
        HwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwCardHeader(
                'Theme',
                trailing: Text(
                  'light is the default',
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
              ),
              const SizedBox(height: HwSpace.s3),
              // Segmented control — the selected segment takes the navy hero
              // fill, never a grey (Principles §5).
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.cardline, width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Segment(
                        icon: HwIcons.sun,
                        label: 'Light',
                        selected: !dark,
                        onTap: () => ref
                            .read(themeModeProvider.notifier)
                            .toggleDarkMode(false),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _Segment(
                        icon: HwIcons.moon,
                        label: 'Dark',
                        selected: dark,
                        onTap: () => ref
                            .read(themeModeProvider.notifier)
                            .toggleDarkMode(true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        HwCard(
          onTap: () => _showTextSizeSheet(context, ref),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.cardline, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text('A',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    )),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Text Size',
                      style: TextStyle(
                        fontSize: HwType.md,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(textScale * 100).round()}%, tap to adjust',
                      style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                    ),
                  ],
                ),
              ),
              HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Text Size card opens this sheet — the shared `#sheet` scaffold
/// ([showHwSheet]) already draws the grab handle, so the slider is the only
/// content this needs to provide.
void _showTextSizeSheet(BuildContext context, WidgetRef ref) {
  showHwSheet(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final p = RefPalette.of(context);
        final textScale = sheetRef.watch(textScaleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Text Size',
                  style: TextStyle(
                    fontSize: HwType.lg,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                Text(
                  '${(textScale * 100).round()}%',
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HwSpace.s3),
            Row(
              children: [
                Text('A', style: TextStyle(fontSize: 14, color: p.ink3)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: p.ink,
                      inactiveTrackColor: p.cardline,
                      thumbColor: p.ink,
                      overlayColor: p.ink.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: textScale,
                      min: kMinTextScale,
                      max: kMaxTextScale,
                      divisions: 11,
                      label: '${(textScale * 100).round()}%',
                      onChanged: (v) =>
                          sheetRef.read(textScaleProvider.notifier).setScale(v),
                    ),
                  ),
                ),
                Text('A', style: TextStyle(fontSize: 26, color: p.ink3)),
              ],
            ),
            const SizedBox(height: HwSpace.s2),
            Text(
              'The quick brown fox jumps over the lazy dog.',
              style: TextStyle(fontSize: HwType.md, color: p.ink2),
            ),
            const SizedBox(height: HwSpace.s3),
          ],
        );
      },
    ),
  );
}

class _Segment extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final fg = selected ? const Color(0xFFF2E9E2) : p.ink3;

    return HwPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HwMotion.t2,
        curve: HwMotion.ease,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? p.heroGrad : null,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? p.shadow : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HwIcon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 · Plan
// ---------------------------------------------------------------------------

class _PlanSection extends ConsumerWidget {
  const _PlanSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final plan = ref.watch(currentPlanProvider).valueOrNull;
    final tokens = ref.watch(tokenBalanceProvider);

    final parts = <String>[
      if (plan != null) plan.name,
      if (tokens != null) '${tokens.round()} session credits left',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Plan'),
        HwCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: HwRow(
            title: 'Plan & usage',
            subtitle: parts.isEmpty ? 'View your plan' : parts.join(' · '),
            trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            onTap: () => context.push(RoutePaths.subscription),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5 · Library & intelligence
// ---------------------------------------------------------------------------

class _LibrarySection extends StatelessWidget {
  const _LibrarySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Library & intelligence'),
        HwRowGroup(children: [
          _MoreRow(
            icon: HwIcons.book,
            title: 'Protocol Library',
            subtitle: 'Stacks & protocols by session goal',
            onTap: () => context.go(RoutePaths.protocols),
          ),
          _MoreRow(
            icon: HwIcons.bot,
            title: 'AI Hub',
            subtitle: 'Chat, reports & guided assessment',
            onTap: () => context.push(RoutePaths.ai),
          ),
          _MoreRow(
            icon: HwIcons.clock,
            title: 'History',
            subtitle: 'Every session, every delta',
            onTap: () => context.go(RoutePaths.history),
          ),
          _MoreRow(
            icon: HwIcons.star,
            title: 'Quick Presets',
            subtitle: '3 saved one-tap setups',
            onTap: () => context.push(RoutePaths.presets),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6 · Devices
// ---------------------------------------------------------------------------

class _DevicesSection extends ConsumerWidget {
  const _DevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);

    final wifi = ref.watch(wifiDevicesByOrgProvider).valueOrNull ?? const [];
    final ble = ref.watch(bleConnectionStatesProvider).valueOrNull ?? const {};
    final connected =
        ble.values.where((s) => s == BleConnectionStatus.connected).length;
    final total = wifi.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Devices'),
        HwCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: HwRow(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: p.sunGrad,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(
                child: Text('〰',
                    style: TextStyle(fontSize: HwType.md, color: Colors.white)),
              ),
            ),
            title: 'Device Center',
            subtitle: total == 0
                ? 'Scan, register, rename & Wi-Fi setup'
                : '$connected of $total units connected · scan, rename, '
                    'Wi-Fi setup',
            trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            onTap: () => context.go(RoutePaths.devices),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 7 · Session defaults
// ---------------------------------------------------------------------------

class _SessionDefaultsSection extends ConsumerWidget {
  const _SessionDefaultsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultId = ref.watch(defaultProtocolIdProvider);
    final labs = ref.watch(labsEnabledProvider);

    final protocolName = defaultId == null
        ? 'Not set'
        : ref.watch(protocolDetailProvider(defaultId)).maybeWhen(
              data: (d) => d.templateName,
              orElse: () => '…',
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Session defaults'),
        HwRowGroup(children: [
          _MoreRow(
            icon: HwIcons.bolt,
            title: 'Default protocol',
            subtitle: 'Auto-selected on Quick Start & body-part pick, '
                'yours to change',
            belowSubtitle: HwPill(protocolName, tone: HwPillTone.copper),
            onTap: () => _showDefaultProtocolSheet(context, ref),
          ),
          _MoreRow(
            icon: HwIcons.note,
            title: 'Default session music',
            subtitle: 'Pre-selected on every session, change or turn off '
                'per session anytime',
            onTap: () => _showMusicSheet(context, ref),
          ),
          _MoreRow(
            icon: HwIcons.flask,
            title: 'Labs · Readiness Score',
            // The spec's exact wording — the honesty caveat is the point.
            subtitle: 'Experimental: breath-derived score under validation. '
                'Numbers may change as the model improves.',
            trailing: HwPill(labs ? 'On' : 'Off',
                tone: labs ? HwPillTone.good : HwPillTone.ghost),
            onTap: () => ref.read(labsEnabledProvider.notifier).toggle(),
          ),
        ]),
      ],
    );
  }

  void _showDefaultProtocolSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: 'Default protocol',
        subtitle: 'Used by Quick Start on the Hub.',
        child: Consumer(
          builder: (ctx, ref2, _) => ref2.watch(protocolListProvider).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const _SheetMessage(
                    'Couldn\'t load protocols. Check your connection and '
                    'try again.'),
                data: (list) {
                  if (list.isEmpty) {
                    return const _SheetMessage(
                        'No protocols available for this organization yet.');
                  }
                  final selected = ref2.watch(defaultProtocolIdProvider);
                  return Column(
                    children: [
                      for (final proto in list)
                        _MoreRow(
                          icon: HwIcons.bolt,
                          title: proto.templateName,
                          subtitle:
                              '~${(proto.apiTotalDurationSeconds / 60).round()} min',
                          trailing: proto.id == selected
                              ? const HwPill('Default', tone: HwPillTone.copper)
                              : null,
                          onTap: () {
                            ref2
                                .read(defaultProtocolIdProvider.notifier)
                                .set(proto.id);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }

  void _showMusicSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: 'Session music',
        subtitle: 'Pick a track per session from the live session screen.',
        child: Consumer(
          builder: (ctx, ref2, _) => ref2.watch(musicListProvider).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const _SheetMessage(
                    'Couldn\'t load the music library right now.'),
                data: (list) => list.isEmpty
                    ? const _SheetMessage('No tracks published yet.')
                    : Column(
                        children: [
                          for (final track in list)
                            _MoreRow(
                              icon: HwIcons.note,
                              title: track.name,
                            ),
                        ],
                      ),
              ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8 · Settings & support
// ---------------------------------------------------------------------------

Future<void> _shareDiagnosticLogs(BuildContext context) async {
  try {
    final shared = await shareLogFile();
    if (!context.mounted) return;
    if (!shared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No log file is available yet.'),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not share logs: $e')),
    );
  }
}

class _SupportSection extends ConsumerWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final unread = ref.watch(unreadNotificationCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Settings & support'),
        HwRowGroup(children: [
          _MoreRow(
            icon: HwIcons.guest,
            tintIcon: false,
            title: 'Edit profile',
            subtitle: 'Name, contact, date of birth, title',
            onTap: () => showProfileSheet(context),
          ),
          _MoreRow(
            icon: HwIcons.key,
            title: 'Change password',
            subtitle: 'Update your sign-in',
            onTap: () => showPasswordSheet(context),
          ),
          _MoreRow(
            icon: HwIcons.bell,
            title: 'Notifications',
            subtitle: 'Session, lease & report alerts',
            trailing: unread > 0
                ? HwPill('$unread new', tone: HwPillTone.low)
                : HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            onTap: () => context.push(RoutePaths.notifications),
          ),
          _MoreRow(
            icon: HwIcons.doc,
            title: 'Warranty',
            subtitle: 'Coverage status for your devices',
            onTap: () => context.push(RoutePaths.warranty),
          ),
          // The spec keeps privacy, help centre and credits behind one row —
          // now its own screen, since the wellness statement and the
          // Z-Anatomy attribution are obligations, not a menu.
          _MoreRow(
            icon: HwIcons.scale,
            title: 'Legal & licenses',
            subtitle: 'Privacy, help center, credits',
            onTap: () => context.push(RoutePaths.legal),
          ),
          _MoreRow(
            icon: HwIcons.note,
            title: 'Export diagnostic logs',
            subtitle: 'Share the on-device log file',
            onTap: () => _shareDiagnosticLogs(context),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 9 · Coming online
// ---------------------------------------------------------------------------

class _ComingOnlineSection extends StatelessWidget {
  const _ComingOnlineSection();

  @override
  Widget build(BuildContext context) {
    // The spec carries a 20px emoji in the leading slot (app.js:1970) — it is
    // what makes this group read like the others rather than a bare list.
    const items = [
      (
        '🫁',
        'Breath Sync + Endurance Breathing',
        'Breathing-led protocols: the pacer becomes primary in live sessions.'
      ),
      (
        '⇄',
        'Mirror Placements',
        'Live now as suggestion chips when a side is unavailable.'
      ),
      (
        '🥗',
        'Calming Recipes',
        'Food-as-medicine recovery nutrition. Under review.'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Coming online'),
        HwRowGroup(
          children: [
            for (final item in items)
              // Non-interactive by design — these are a roadmap, not rows.
              HwRow(
                leading: Text(item.$1, style: const TextStyle(fontSize: 20)),
                title: item.$2,
                subtitle: item.$3,
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 10 · Brand footer
// ---------------------------------------------------------------------------

class _BrandFooter extends StatelessWidget {
  final VoidCallback onVersionTap;
  const _BrandFooter({required this.onVersionTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return HwCard(
      onTap: onVersionTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        children: [
          SizedBox(
            height: 24,
            child: SvgPicture.asset(
              dark
                  ? 'assets/images/Hydrawav3_White_Logo.svg'
                  : 'assets/images/Hydrawav3_Black_Logo.svg',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: HwSpace.s3),
          Text(
            'Performance-First. Recovery-Next.',
            style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
          ),
          const SizedBox(height: 4),
          Text(
            'Reminding people the body has the power to heal itself.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: HwSpace.s3),
            child: Divider(height: 1, color: p.divider),
          ),
          Text(
            'Wellness & performance platform, not a medical device. Sessions '
            'support readiness, recovery, and mobility; they do not treat, '
            'cure, or diagnose.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: HwType.eyebrow, height: 1.5, color: p.ink3),
          ),
          const SizedBox(height: HwSpace.s3),
          Text(
            '${AppConstants.appVersion} · BUILD ${AppConstants.buildNumber}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: p.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// A hairline-separated stack of [_MoreRow]s inside one card.

class _MoreRow extends StatelessWidget {
  final String icon;
  final String title;
  final String? subtitle;
  final Widget? belowSubtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// False for icons whose colour is baked in (the copper Guest mark).
  final bool tintIcon;

  const _MoreRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.belowSubtitle,
    this.trailing,
    this.onTap,
    this.tintIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwRow(
      leading: HwIcon(icon, size: 19, color: tintIcon ? p.copperInk : null),
      title: title,
      subtitle: subtitle,
      belowSubtitle: belowSubtitle,
      trailing: trailing ??
          (onTap == null
              ? null
              : HwIcon(HwIcons.chev, size: 18, color: p.ink3)),
      onTap: onTap,
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String? icon;
  final String label;
  final VoidCallback onTap;
  const _DangerButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HwRadius.sm),
          border: Border.all(color: p.low, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              HwIcon(icon!, size: 16, color: p.low),
              const SizedBox(width: HwSpace.s2),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w700,
                color: p.low,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: RefPalette.of(context).line,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: p.sunGrad,
          borderRadius: BorderRadius.circular(HwRadius.sm),
        ),
        child: const Center(
          child: Text(
            'Close',
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet that holds a scrollable list of choices.
class _PickerSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PickerSheet({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
        ),
        child: Column(
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: HwType.xl,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: HwType.base, color: p.ink2),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: child,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _SheetCloseButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  final String text;
  const _SheetMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: HwType.sm,
          height: 1.5,
          color: RefPalette.of(context).ink2,
        ),
      ),
    );
  }
}
