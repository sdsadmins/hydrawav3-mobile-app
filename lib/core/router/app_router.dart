import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/devices/presentation/screens/device_detail_screen.dart';
import '../../features/devices/presentation/screens/device_list_screen.dart';
import '../../features/devices/presentation/screens/device_register_screen.dart';
import '../../features/history/presentation/screens/history_list_screen.dart';
import '../../features/history/presentation/screens/session_detail_screen.dart';
import '../../features/protocols/presentation/screens/protocol_detail_screen.dart';
import '../../features/protocols/presentation/screens/protocol_list_screen.dart';
import '../../features/protocols/domain/protocol_model.dart';
import '../../features/advanced_settings/domain/advanced_settings_model.dart';
import '../../features/session/domain/active_session_model.dart';
import '../../features/session/presentation/providers/active_sessions_provider.dart';
import '../../features/session/presentation/screens/session_screen.dart';
import '../../features/session/presentation/screens/session_setup_screen.dart';
import '../../features/settings/presentation/screens/change_password_screen.dart';
import '../../features/settings/presentation/screens/profile_edit_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/subscription_screen.dart';
import '../../features/presets/presentation/screens/preset_management_screen.dart';
import '../../features/ai_chat/presentation/screens/chat_screen.dart';
import '../constants/theme_constants.dart';
import 'route_names.dart';
import '../../features/auth/presentation/screens/select_organization_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.login,
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;

      final isAuthRoute = state.matchedLocation == RoutePaths.login ||
          state.matchedLocation == RoutePaths.signup ||
          state.matchedLocation == RoutePaths.forgotPassword;

      final isSelectingOrg = state.matchedLocation == '/select-organization';

      /// ✅ ONLY use local selection
      final hasSelectedOrg = authState.selectedOrgId != null;

      // ❌ Not logged in
      if (!isAuth && !isAuthRoute) {
        return RoutePaths.login;
      }

      // ✅ Logged in but NO org
      if (isAuth && !hasSelectedOrg && !isSelectingOrg) {
        return '/select-organization';
      }

      // ✅ Logged in + org selected
      if (isAuth && hasSelectedOrg && isAuthRoute) {
        // Redirect authenticated users to the device list first.
        return RoutePaths.devices;
      }

      return null;
    },
    routes: [
      GoRoute(
          path: RoutePaths.login,
          name: RouteNames.login,
          builder: (c, s) => const LoginScreen()),
      GoRoute(
          path: RoutePaths.signup,
          name: RouteNames.signup,
          builder: (c, s) => const SignupScreen()),
      GoRoute(
        path: '/select-organization',
        name: RouteNames.selectOrganization,
        builder: (c, s) => const SelectOrganizationPage(),
      ),
      GoRoute(
          path: RoutePaths.forgotPassword,
          name: RouteNames.forgotPassword,
          builder: (c, s) => const ForgotPasswordScreen()),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (c, s, child) => _AppShell(child: child),
        routes: [
          GoRoute(
              path: RoutePaths.protocols,
              name: RouteNames.protocols,
              builder: (c, s) => const ProtocolListScreen()),
          GoRoute(
              path: RoutePaths.devices,
              name: RouteNames.devices,
              builder: (c, s) => const DeviceListScreen()),
          GoRoute(
              path: RoutePaths.history,
              name: RouteNames.history,
              builder: (c, s) => const HistoryListScreen()),
          GoRoute(
              path: RoutePaths.settings,
              name: RouteNames.settings,
              builder: (c, s) => const SettingsScreen()),
        ],
      ),
      GoRoute(
          path: RoutePaths.protocolDetail,
          name: RouteNames.protocolDetail,
          builder: (c, s) =>
              ProtocolDetailScreen(protocolId: s.pathParameters['id']!)),
      GoRoute(
        path: RoutePaths.sessionSetup,
        name: RouteNames.sessionSetup,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final deviceIds =
              extra?['deviceIds'] as List<String>? ?? const <String>[];
          final transport = extra?['transport'] as String? ?? 'ble';
          final goalTagId = extra?['goalTagId'] as String?;
          return SessionSetupScreen(
            deviceIds: deviceIds,
            transport: transport,
            goalTagId: goalTagId,
          );
        },
      ),
      GoRoute(
          path: RoutePaths.session,
          name: RouteNames.session,
          builder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            final anchorRaw = extra?['sessionClockAnchorMs'];
            final sessionClockAnchorMs = anchorRaw is int
                ? anchorRaw
                : (anchorRaw is num ? anchorRaw.toInt() : null);
            final advancedSettingsRaw = extra?['advancedSettings'];
            final advancedSettings = advancedSettingsRaw is AdvancedSettings
                ? advancedSettingsRaw
                : advancedSettingsRaw is Map<String, dynamic>
                    ? AdvancedSettings.fromJson(advancedSettingsRaw)
                    : const AdvancedSettings();
            final advancedSettingsByDeviceRaw =
                extra?['advancedSettingsByDevice'] as Map?;
            final advancedSettingsByDevice = <String, AdvancedSettings>{};
            if (advancedSettingsByDeviceRaw != null) {
              for (final entry in advancedSettingsByDeviceRaw.entries) {
                final key = entry.key?.toString();
                final value = entry.value;
                if (key == null) continue;
                if (value is AdvancedSettings) {
                  advancedSettingsByDevice[key] = value;
                } else if (value is Map<String, dynamic>) {
                  advancedSettingsByDevice[key] =
                      AdvancedSettings.fromJson(value);
                }
              }
            }
            final delayedDeviceId = extra?['delayedDeviceId'] as String?;
            final skipEngineBootstrap =
                extra?['skipEngineBootstrap'] as bool? ?? false;
            final wifiConfigAlreadyPublished =
                extra?['wifiConfigAlreadyPublished'] as bool? ?? false;
            final protocolByDeviceIdRaw = extra?['protocolByDeviceId'] as Map?;
            final protocolByDeviceId = <String, String>{};
            if (protocolByDeviceIdRaw != null) {
              for (final entry in protocolByDeviceIdRaw.entries) {
                final key = entry.key.toString();
                final value = entry.value;
                if (value == null) continue;
                final pid = value.toString();
                if (key.isEmpty || pid.isEmpty) continue;
                protocolByDeviceId[key] = pid;
              }
            }
            return SessionScreen(
              sessionId: extra?['sessionId'] as String?,
              protocolId: extra?['protocolId'] as String? ?? '',
              protocol: extra?['protocol'] as Protocol?,
              deviceIds: extra?['deviceIds'] as List<String>? ?? [],
              transport: extra?['transport'] as String? ?? 'ble',
              sessionClockAnchorMs: sessionClockAnchorMs,
              advancedSettings: advancedSettings,
              advancedSettingsByDevice: advancedSettingsByDevice,
              protocolByDeviceId: protocolByDeviceId,
              delayedDeviceId: delayedDeviceId,
              skipEngineBootstrap: skipEngineBootstrap,
              wifiConfigAlreadyPublished: wifiConfigAlreadyPublished,
            );
          }),
      GoRoute(
          path: RoutePaths.deviceRegister,
          name: RouteNames.deviceRegister,
          builder: (c, s) => const DeviceRegisterScreen()),
      GoRoute(
          path: RoutePaths.deviceDetail,
          name: RouteNames.deviceDetail,
          builder: (c, s) =>
              DeviceDetailScreen(deviceId: s.pathParameters['id']!)),
      GoRoute(
          path: RoutePaths.sessionDetail,
          name: RouteNames.sessionDetail,
          builder: (c, s) =>
              SessionDetailScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(
          path: RoutePaths.profileEdit,
          name: RouteNames.profileEdit,
          builder: (c, s) => const ProfileEditScreen()),
      GoRoute(
          path: RoutePaths.changePassword,
          name: RouteNames.changePassword,
          builder: (c, s) => const ChangePasswordScreen()),
      GoRoute(
          path: RoutePaths.subscription,
          name: RouteNames.subscription,
          builder: (c, s) => const SubscriptionScreen()),
      GoRoute(
          path: RoutePaths.presets,
          name: RouteNames.presets,
          builder: (c, s) => const PresetManagementScreen()),
      GoRoute(
          path: RoutePaths.chat,
          name: RouteNames.chat,
          builder: (c, s) => const ChatScreen()),
    ],
  );
});

class _AppShell extends ConsumerWidget {
  final Widget child;
  const _AppShell({required this.child});

  bool _isLiveStatus(SessionStatus status) {
    return status == SessionStatus.running || status == SessionStatus.paused;
  }

  bool _isVisibleActiveSession(ActiveSession session) {
    if (_isLiveStatus(session.status)) {
      return true;
    }
    for (final deviceId in session.deviceIds) {
      final deviceStatus =
          session.deviceStatuses[deviceId] ?? SessionStatus.idle;
      if (_isLiveStatus(deviceStatus)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int idx = 0;
    if (location.startsWith(RoutePaths.devices)) idx = 1;
    if (location.startsWith(RoutePaths.history)) idx = 2;
    if (location.startsWith(RoutePaths.settings)) idx = 3;

    final activeSessions = ref.watch(activeSessionsProvider);
    final activeBackgroundCount =
        activeSessions.where(_isVisibleActiveSession).length;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? ThemeConstants.background : ThemeConstants.surface,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? ThemeConstants.border.withValues(alpha: 0.55)
                  : ThemeConstants.border,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                _NavTab(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    active: idx == 0,
                    onTap: () => context.go(RoutePaths.protocols)),
                _NavTab(
                    icon: Icons.bluetooth_outlined,
                    activeIcon: Icons.bluetooth_connected_rounded,
                    label: 'Devices',
                    active: idx == 1,
                    onTap: () => context.go(RoutePaths.devices)),
                _NavTab(
                    icon: Icons.history_outlined,
                    activeIcon: Icons.history_rounded,
                    label: 'History',
                    active: idx == 2,
                    badgeCount: activeBackgroundCount,
                    onTap: () => context.go(RoutePaths.history)),
                _NavTab(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    active: idx == 3,
                    onTap: () => context.go(RoutePaths.settings)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavTab(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.active,
      this.badgeCount = 0,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? ThemeConstants.textSecondary : ThemeConstants.textTertiary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      active ? activeIcon : icon,
                      size: 22,
                      color: active ? ThemeConstants.accent : inactiveColor,
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ThemeConstants.accent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 1.5,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? ThemeConstants.accent : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
