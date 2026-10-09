import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/theme/text_scale_provider.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../../core/utils/log_export.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import '../../../ble/domain/ble_device_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../../home/presentation/widgets/hub_modules.dart' show HubGameReadyCard;
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../history/domain/session_history_model.dart';
import '../../../home/presentation/providers/hub_prefs_provider.dart';
import '../../../home/presentation/providers/hub_stats_provider.dart';
import '../../../musics/presentation/providers/music_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../practitioners/data/practitioner_repository.dart';
import '../../../practitioners/presentation/org_team_sheet.dart';
import '../../../presets/presentation/providers/preset_provider.dart';
import '../../../splash/presentation/screens/splash_screen.dart';
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
                // Tablet: one centred reading column (`97-tablet`).
                padding: EdgeInsets.fromLTRB(
                  HwTablet.sidePadding(context,
                      column: HwTablet.read, phone: 18),
                  8,
                  HwTablet.sidePadding(context,
                      column: HwTablet.read, phone: 18),
                  108,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pageTitle(context),
                    const _AccountCard(),
                    const SizedBox(height: HwSpace.s3),
                    const _RoleCard(),
                    const SizedBox(height: HwSpace.s5),
                    const _OrganizationsSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _AppearanceSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _PlanSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _LibrarySection(),
                    const SizedBox(height: HwSpace.s5),
                    const _ResourcesSection(),
                    const SizedBox(height: HwSpace.s5),
                    const _LabsSection(),
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
                        // v6 `signOutPreview`: sign out through the splash.
                        // Grab what we need first — this screen goes away
                        // as soon as the splash is pushed.
                        final container =
                            ProviderScope.containerOf(context, listen: false);
                        final auth = container.read(authStateProvider.notifier);
                        container.read(splashHoldProvider.notifier).state =
                            true;
                        context.go(RoutePaths.splash);
                        await auth.logout();
                        container.invalidate(organizationProvider);
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

/// The signed-in role (v6 "Main admin · Full control across every
/// organization"), read from the login's roles — the web app's `rbac.ts`
/// mapping. Read-only: there's no API to switch role.
class _RoleCard extends ConsumerWidget {
  const _RoleCard();

  static ({String title, String line})? describe(
      String? role, List<String>? roles) {
    final all = [...?roles, if (role != null) role]
        .map((r) => r.toUpperCase().trim())
        .where((r) => r.isNotEmpty)
        .toList();
    if (all.isEmpty) return null;
    if (all.contains('PRIMARY ACCOUNT - ADMIN')) {
      return (
        title: 'Main admin',
        line: 'Full control across every organization',
      );
    }
    if (all.any((r) => r.contains('ADMIN'))) {
      return (title: 'Admin', line: 'Manages organizations and users');
    }
    if (all.any((r) => r.contains('PRACTITIONER'))) {
      return (
        title: 'Practitioner',
        line: 'Runs sessions in your organization',
      );
    }
    if (all.contains('CLIENT')) {
      return (title: 'Client', line: 'At-home sessions on a leased unit');
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final roles = ref.watch(sessionRolesProvider).valueOrNull;
    final d = describe(null, roles);
    if (d == null) return const SizedBox.shrink();
    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.tanSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shield_outlined, size: 20, color: p.copperInk),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d.line,
                  style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                ),
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
    final orgId = org['id'].toString();
    // Credits are only known for the organization in use — the balance and
    // plan endpoints are per selected org.
    final plan = active ? ref.watch(currentPlanProvider).valueOrNull : null;
    final tokens = active ? ref.watch(tokenBalanceProvider) : null;
    // v5 `50-admin`: the account owner manages each organization's team.
    final admin = ref.watch(isPrimaryAdminProvider);
    final team =
        admin ? ref.watch(practitionersByOrgProvider(orgId)).valueOrNull : null;

    final subtitle = [
      if (org['description'] != null) org['description'].toString(),
      if (team != null)
        '${team.length} practitioner${team.length == 1 ? '' : 's'}',
    ].join(' · ');

    Future<void> switchTo() async {
      await ref.read(authStateProvider.notifier).setOrganization(orgId, name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to $name')),
      );
      // Picking an organization is the start of working in it, so land on the
      // Session tab rather than leaving the practitioner parked on More.
      context.go(RoutePaths.devices);
    }

    return HwCard(
      accented: active,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `.v5a-orghd` — tap to switch.
          HwPress(
            onTap: active ? () {} : switchTo,
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
                        style: TextStyle(
                          fontSize: HwType.md,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: HwType.eyebrow, color: p.ink3),
                        ),
                      ],
                    ],
                  ),
                ),
                if (active) const HwPill('Active', tone: HwPillTone.copper),
              ],
            ),
          ),
          // `.v5a-credits` — "Plan · organization credits · N left".
          if (active && tokens != null) ...[
            const SizedBox(height: HwSpace.s3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: p.bg2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${plan != null ? '${plan.name} · ' : ''}organization credits',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_fmtCredits(tokens)} left',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w800,
                      color: p.copperInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // `.v5a-ax` — only what an API backs: Manage users.
          if (admin) ...[
            const SizedBox(height: HwSpace.s3),
            Row(
              children: [
                HwPress(
                  onTap: () => showOrgTeamSheet(
                    context,
                    orgId: orgId,
                    orgName: name,
                    creditsLeft:
                        active && tokens != null ? _fmtCredits(tokens) : null,
                    planName: plan?.name,
                  ),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.cardline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_outlined, size: 16, color: p.ink2),
                        const SizedBox(width: 6),
                        Text(
                          'Manage users',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: p.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtCredits(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
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
                  color: p.bg2,
                  borderRadius: BorderRadius.circular(999),
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
    final fg = selected ? const Color(0xFF2B1D12) : p.ink3;

    return HwPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HwMotion.t2,
        curve: HwMotion.ease,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: selected ? p.sunGrad : null,
          borderRadius: BorderRadius.circular(999),
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

  static String _currencySymbol(String? c) {
    switch ((c ?? 'usd').toLowerCase()) {
      case 'usd':
        return r'$';
      case 'eur':
        return '€';
      case 'gbp':
        return '£';
      case 'inr':
        return '₹';
      default:
        return '${c!.toUpperCase()} ';
    }
  }

  static String _perCycle(String? cycle) {
    final c = (cycle ?? '').toLowerCase();
    if (c.startsWith('month')) return '/month';
    if (c.startsWith('year') || c.startsWith('annual')) return '/year';
    if (c.startsWith('week')) return '/week';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final plan = ref.watch(currentPlanProvider).valueOrNull;
    final tokens = ref.watch(tokenBalanceProvider);

    // "Sports plan · $99/month" — the price when the plan carries one,
    // otherwise the credits left.
    final price = plan?.amount == null
        ? null
        : '${_currencySymbol(plan!.currency)}'
            '${plan.amount! == plan.amount!.roundToDouble() ? plan.amount!.round() : plan.amount!.toStringAsFixed(2)}'
            '${_perCycle(plan.billingCycle)}';
    final parts = <String>[
      if (plan != null) plan.name,
      if (price != null)
        price
      else if (tokens != null)
        '${tokens.round()} session credits left',
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

class _LibrarySection extends ConsumerWidget {
  const _LibrarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetListProvider).valueOrNull;
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
            subtitle: presets == null
                ? 'Saved one-tap setups'
                : '${presets.length} saved one-tap setup'
                    '${presets.length == 1 ? '' : 's'}',
            onTap: () => context.push(RoutePaths.presets),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5b · Resources & business
// ---------------------------------------------------------------------------

Future<void> _openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open the link right now.')),
    );
  }
}

class _ResourcesSection extends ConsumerWidget {
  const _ResourcesSection();

  static const _helpCenter = 'https://www.hydrawav3.com/help-center';
  static const _buy = 'https://www.hydrawav3.com/buy';
  static const _economics = 'https://www.hydrawav3.com/economics';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final clients = ref.watch(clientListProvider).valueOrNull;
    final leases = clients?.where((c) => c.isLeaseActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Resources & business'),
        HwRowGroup(children: [
          // No support number yet — opens the help center's contact options.
          _MoreRow(
            icon: HwIcons.phone,
            title: 'Call Customer Support',
            subtitle: 'Tap for contact options',
            onTap: () => _openLink(context, _helpCenter),
          ),
          // `.v5-start` — the highlighted "START HERE" row.
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: p.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: p.copper, width: 3)),
            ),
            child: _MoreRow(
              icon: HwIcons.briefcase,
              title: 'Business & Educational Resources',
              subtitle: 'hydrawav3.com/help-center',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.copper,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'START HERE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  HwIcon(HwIcons.chev, size: 18, color: p.ink3),
                ],
              ),
              onTap: () => _openLink(context, _helpCenter),
            ),
          ),
          _MoreRow(
            icon: HwIcons.bag,
            title: 'Buy More Products',
            subtitle: 'hydrawav3.com/buy',
            onTap: () => _openLink(context, _buy),
          ),
          _MoreRow(
            icon: HwIcons.chart,
            title: 'Rental Economics',
            subtitle: 'Payback, margins & ROI of renting units',
            onTap: () => _openLink(context, _economics),
          ),
          _MoreRow(
            icon: HwIcons.chart,
            material: Icons.attach_money_rounded,
            title: 'Rent & Earn',
            subtitle: leases == null
                ? 'Lease units to clients'
                : '$leases active lease${leases == 1 ? '' : 's'} · '
                    'lease units to clients',
            onTap: () => context.go(RoutePaths.users),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5c · Labs & insights
// ---------------------------------------------------------------------------

class _LabsSection extends ConsumerWidget {
  const _LabsSection();

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    return '${d.inDays} days ago';
  }

  static String _label(SessionHistoryItem s) {
    final names = s.protocols
        .map((p) => p.protocol?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    return names.isEmpty ? 'Session' : names.first;
  }

  static String _lastLine(SessionHistoryItem s) => [
        _label(s),
        if (s.createdAt != null) _ago(s.createdAt!.toLocal()),
      ].join(' · ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final stats = ref.watch(hubStatsProvider).valueOrNull;
    final gamePrep =
        ref.watch(hubLayoutProvider).visible.contains(HubModule.gameprep);
    final gameDay = ref.watch(gameDayActiveProvider);
    final last = stats?.lastSession;

    // Every row opens a sheet, as in v6 (`openSheet(hub…HTML())`).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HwEyebrow('Labs & insights'),
        HwRowGroup(children: [
          _MoreRow(
            icon: HwIcons.flask,
            title: 'Labs · Measure Breath',
            subtitle: 'Experimental 60-second breath readiness read',
            onTap: () => _showBreathSheet(context),
          ),
          _MoreRow(
            icon: HwIcons.star,
            material: Icons.auto_awesome_outlined,
            title: 'AI Mobility Report',
            subtitle: 'Map your whole kinetic chain · 3–5 min',
            onTap: () => _showMobilitySheet(context),
          ),
          if (gamePrep)
            _MoreRow(
              icon: HwIcons.target,
              title: 'Game Day',
              subtitle: gameDay
                  ? 'On · track who has been prepped'
                  : "Track who's had their performance protocol",
              trailing: gameDay
                  ? const HwPill('On', tone: HwPillTone.good)
                  : null,
              onTap: () => _showGameDaySheet(context),
            ),
          _MoreRow(
            icon: HwIcons.chart,
            title: 'This Week',
            subtitle: 'Sessions today · improvement score · active days',
            onTap: () => _showWeekSheet(context),
          ),
          _MoreRow(
            icon: HwIcons.clock,
            title: 'Last Session',
            subtitle: last == null ? 'No sessions yet' : _lastLine(last),
            trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            onTap: last == null
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No sessions yet')))
                : () => _showLastSessionSheet(context, last),
          ),
        ]),
      ],
    );
  }

  /// The experimental breath-readiness tool (prototype link).
  static const _breathTool = 'https://shivahydrawav3.github.io/cowork-os/'
      'parasympathetic-tracker-v5.html?v=55';

  // ── Labs · Measure Breath (`hubLabsHTML`) ───────────────────────────────
  void _showBreathSheet(BuildContext context) {
    showPlanSheet<void>(
      context,
      title: 'Labs · Measure Breath',
      builder: (ctx) {
        final p = RefPalette.of(ctx);
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              gradient: p.heroGrad,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LABS · A FIRST, FOR MOST PEOPLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: p.copper,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Ever measured your readiness from your own breath?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: Color(0xFFF2E9E2),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '60 seconds, lying down, phone resting on your belly. Your '
                  'exhale, inhale and the pauses in between become a Readiness '
                  'score — no wearable, nothing strapped on.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: Color(0xD9F2E9E2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 10,
                      child: HwPress(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showBreathHowSheet(context);
                        },
                        child: Container(
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color.fromRGBO(221, 202, 191, .4),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'How it works',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDDCABF),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 13,
                      child: PlanPrimaryButton(
                        label: '▶  Try the experiment',
                        onTap: () => _openLink(ctx, _breathTool),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                const Text(
                  'Experimental — breath-derived score under validation. Your '
                  'body already knows; this just listens.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: Color(0xFFDDCABF),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── "Readiness from breath — how it works" (`breathHowSheet`) ───────────
  void _showBreathHowSheet(BuildContext context) {
    const steps = [
      (
        'Lie down, phone on your belly',
        'Anywhere quiet. The screen guides you — just breathe normally for '
            'about 60 seconds.'
      ),
      (
        'Your breath becomes numbers',
        'Exhale length, inhale length, and the natural pauses between '
            'breaths. Longer exhales and pauses = a more recovered, '
            'rest-ready state.'
      ),
      (
        'See your Readiness score',
        'A single score with a live view of every breath. Run it before and '
            'after a Hydrawav3 session and watch what changes — '
            'involuntarily.'
      ),
    ];
    showPlanSheet<void>(
      context,
      title: 'Readiness from breath — how it works',
      builder: (ctx) {
        final p = RefPalette.of(ctx);
        final micro = TextStyle(fontSize: 12.5, height: 1.5, color: p.ink3);
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Your phone's motion sensors can feel your belly rise and "
                "fall. That's enough to read your breathing — and your "
                'breathing tells the story of your nervous system.',
                style: micro,
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.tanSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: p.copperInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].$1,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(steps[i].$2, style: micro),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Most people have never seen their own breath measured. It '
                'takes one minute to change that.',
                style: micro,
              ),
              const SizedBox(height: 14),
              PlanPrimaryButton(
                label: '▶  Try the experiment · ~1 min',
                onTap: () => _openLink(ctx, _breathTool),
              ),
              const SizedBox(height: 8),
              Text(
                'Experimental — under validation. Wellness insight, not a '
                'medical measurement.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: p.ink3),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── AI Mobility Report (`hubMobilityCard`) ──────────────────────────────
  void _showMobilitySheet(BuildContext context) {
    showPlanSheet<void>(
      context,
      title: 'AI Mobility Report',
      builder: (ctx) {
        final p = RefPalette.of(ctx);
        final body = TextStyle(fontSize: 14, height: 1.55, color: p.ink2);
        final bold = TextStyle(fontWeight: FontWeight.w700, color: p.ink);
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.copper,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '✦ AI MOBILITY REPORT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Color(0xFF2B1D12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Uncover your full mobility picture',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(style: body, children: [
                  const TextSpan(
                      text: 'A first-of-its-kind AI assessment maps your '),
                  TextSpan(text: 'whole kinetic chain', style: bold),
                  const TextSpan(
                      text: ', links every area you flagged, and reveals '
                          'mobility patterns you\'ve '),
                  TextSpan(
                      text: 'never been able to see or understand before',
                      style: bold),
                  const TextSpan(text: ' — with '),
                  TextSpan(
                      text: 'personalized at-home exercises', style: bold),
                  const TextSpan(text: ' and advisor insights.'),
                ]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              PlanPrimaryButton(
                label: '▶  Generate my AI report',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push(RoutePaths.guidedAssessment);
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Takes ~3–5 minutes · goes far beyond the instant report',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.ink3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Game day (`hubGamedayHTML`) ─────────────────────────────────────────
  void _showGameDaySheet(BuildContext context) {
    showPlanSheet<void>(
      context,
      title: 'Game day',
      builder: (_) => Consumer(builder: (ctx, ref, _) {
        final p = RefPalette.of(ctx);
        final on = ref.watch(gameDayActiveProvider);
        final n = ref.read(gameDayActiveProvider.notifier);
        if (on) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HubGameReadyCard(),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: n.end,
                    child: Text(
                      'End game day',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.ink3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: HwCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Game day',
                        style: TextStyle(
                          fontSize: HwType.md,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 118,
                      child: PlanPrimaryButton(
                        label: 'Activate',
                        onTap: n.activate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "On the day it counts, track who's had their performance "
                  "protocol — and who's still to go.",
                  style: TextStyle(fontSize: 13, height: 1.45, color: p.ink3),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── This week (`hubWeekHTML`) ────────────────────────────────────────────
  void _showWeekSheet(BuildContext context) {
    showPlanSheet<void>(
      context,
      title: 'This week',
      subtitle: 'measured, not estimated',
      builder: (_) => Consumer(builder: (ctx, ref, _) {
        final p = RefPalette.of(ctx);
        final stats = ref.watch(hubStatsProvider).valueOrNull;
        final roster = ref.watch(clientListProvider).valueOrNull?.length ?? 0;
        final today = stats?.sessionsToday ?? 0;
        final pulse = stats?.pulsePct;
        final days = stats?.activeDays7d ?? 0;
        const cSess = Color(0xFFA87B5C);
        const cPulse = Color(0xFF3F8F6B);
        const cDays = Color(0xFF4E7A8A);

        Widget legend(Color c, String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(fontSize: 13, color: p.ink3)),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            );

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: HwCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: CustomPaint(
                    painter: _WeekRings(
                      track: p.bg2,
                      rings: [
                        (today / math.max(roster, 8), cSess),
                        ((pulse ?? 0) / 100, cPulse),
                        (days / 7, cDays),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      legend(cSess, 'Sessions today', '$today'),
                      legend(cPulse, 'Outcome Pulse',
                          pulse == null ? '—' : '$pulse%'),
                      legend(cDays, 'Active days · 7d', '$days'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Last session (`hubLastSessionHTML`) ─────────────────────────────────
  void _showLastSessionSheet(BuildContext context, SessionHistoryItem last) {
    showPlanSheet<void>(
      context,
      title: 'Last session',
      subtitle: last.createdAt == null ? null : _ago(last.createdAt!.toLocal()),
      builder: (_) => Consumer(builder: (ctx, ref, _) {
        final p = RefPalette.of(ctx);
        final clients = ref.watch(clientListProvider).valueOrNull;
        final match = last.isGuest || last.clientId == null
            ? null
            : clients?.where((c) => c.id == last.clientId).firstOrNull;
        final name = match?.clientName ?? 'Guest';
        final initials = name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join();
        // The post-session check: rank 4–5 is a YES, 1–3 a NO.
        final ranks = [
          for (final pr in last.protocols)
            for (final qa in pr.questionAnswers)
              if (qa.rank > 0) qa.rank,
        ];
        final Widget pill = ranks.isEmpty
            ? const HwPill('no check', tone: HwPillTone.ghost)
            : ranks.any((r) => r >= 4)
                ? const HwPill('YES ✓', tone: HwPillTone.good)
                : const HwPill('NO', tone: HwPillTone.low);

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: HwCard(
            padding: const EdgeInsets.all(14),
            onTap: last.id == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    context.push(
                      RoutePaths.sessionDetail.replaceFirst(':id', last.id!),
                      extra: last,
                    );
                  },
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.sunGrad,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    initials.isEmpty ? 'G' : initials,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _label(last),
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                pill,
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// `ring3SVG` — three concentric progress rings over a soft track.
class _WeekRings extends CustomPainter {
  final Color track;
  final List<(double, Color)> rings;
  const _WeekRings({required this.track, required this.rings});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const stroke = 11.0, gap = 3.0;
    var r = size.shortestSide / 2 - stroke / 2;
    for (final (v, color) in rings) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = track);
      final f = v.clamp(0.0, 1.0);
      if (f > 0) {
        canvas.drawArc(
            rect,
            -math.pi / 2,
            2 * math.pi * f,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeCap = StrokeCap.round
              ..color = color);
      }
      r -= stroke + gap;
    }
  }

  @override
  bool shouldRepaint(_WeekRings old) =>
      old.track != track || old.rings.toString() != rings.toString();
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
                          // .totalDurationSeconds (not the raw
                          // apiTotalDurationSeconds field) — the list API
                          // doesn't send a per-protocol duration, so every
                          // row read 0 here; the computed getter derives it
                          // from cycles the same way the rest of the app
                          // does.
                          subtitle:
                              '~${(proto.totalDurationSeconds / 60).round()} min',
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

  /// A Material glyph in place of [icon], for marks the HW set lacks.
  final IconData? material;

  const _MoreRow({
    required this.icon,
    this.material,
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
      leading: material != null
          ? Icon(material, size: 20, color: p.copperInk)
          : HwIcon(icon, size: 19, color: tintIcon ? p.copperInk : null),
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
