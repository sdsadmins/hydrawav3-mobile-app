import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/providers/client_auth_provider.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/devices/presentation/screens/device_detail_screen.dart';
import '../../features/devices/presentation/screens/device_list_screen.dart';
import '../../features/devices/presentation/screens/device_register_screen.dart';
import '../../features/history/presentation/screens/history_list_screen.dart';
import '../../features/history/presentation/screens/session_detail_screen.dart';
import '../../features/history/domain/session_history_model.dart';
import '../../features/protocols/presentation/screens/protocol_detail_screen.dart';
import '../../features/protocols/presentation/screens/protocol_list_screen.dart';
import '../../features/protocols/presentation/screens/protocol_plus_list_screen.dart';
import '../../features/protocols/domain/protocol_model.dart';
import '../../features/session/services/protocol_plus_controller.dart';
import '../../features/advanced_settings/domain/advanced_settings_model.dart';
import '../../features/session/domain/active_session_model.dart';
import '../../features/session/presentation/providers/live_sessions_provider.dart';
import '../../features/session/presentation/screens/session_screen.dart';
import '../../features/session/presentation/screens/session_setup_screen.dart';
import '../../features/settings/presentation/screens/change_password_screen.dart';
import '../../features/settings/presentation/screens/profile_edit_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/subscription_screen.dart';
import '../../features/presets/presentation/screens/preset_management_screen.dart';
import '../../features/ai_chat/presentation/screens/chat_screen.dart';
import '../../features/ai_report/presentation/screens/ai_report_screen.dart';
import '../../features/ai_report/presentation/screens/ai_reports_list_screen.dart';
import '../../features/clients/presentation/screens/clients_list_screen.dart';
import '../../features/clients/presentation/screens/client_lease_screen.dart';
import '../../features/client_session/presentation/screens/client_session_screen.dart';
import '../constants/theme_constants.dart';
import 'route_names.dart';
import '../../features/auth/presentation/screens/select_organization_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  // Client (at-home) sessions authenticate separately from practitioners; the
  // router must treat an authenticated client as logged-in too, and skip the
  // practitioner-only org-selection gate.
  final isClientAuth = ref.watch(clientAuthProvider).isAuthenticated;

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.login,
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;

      final isAuthRoute = state.matchedLocation == RoutePaths.login ||
          state.matchedLocation == RoutePaths.signup ||
          state.matchedLocation == RoutePaths.onboarding ||
          state.matchedLocation == RoutePaths.forgotPassword;

      final isSelectingOrg = state.matchedLocation == '/select-organization';

      /// ✅ ONLY use local selection
      final hasSelectedOrg = authState.selectedOrgId != null;

      // ⏳ Still checking the stored token → don't redirect yet. The user waits
      // on the login screen (the initial route) until the check completes; an
      // already-authenticated user is then sent straight to home below.
      if (!authState.isInitialized) {
        return null;
      }

      // ❌ Not logged in (neither practitioner nor client)
      if (!isAuth && !isClientAuth && !isAuthRoute) {
        return RoutePaths.login;
      }

      // ✅ Client logged in → their at-home session screen (no org gate and
      // no practitioner shell; the client's org comes from their lease session).
      if (isClientAuth && !isAuth) {
        if (state.matchedLocation != RoutePaths.clientHome) {
          return RoutePaths.clientHome;
        }
        return null;
      }

      // ✅ Practitioner logged in but NO org
      if (isAuth && !hasSelectedOrg && !isSelectingOrg) {
        return '/select-organization';
      }

      // ✅ Practitioner logged in + org selected
      if (isAuth && hasSelectedOrg && isAuthRoute) {
        // Redirect authenticated users to the device list first.
        return RoutePaths.devices;
      }

      return null;
    },
    routes: 
    [
      GoRoute(
          path: RoutePaths.login,
          name: RouteNames.login,
          builder: (c, s) => const LoginScreen()),
      GoRoute(
          path: RoutePaths.signup,
          name: RouteNames.signup,
          builder: (c, s) => const SignupScreen()),
      GoRoute(
          path: RoutePaths.onboarding,
          name: RouteNames.onboarding,
          builder: (c, s) => const OnboardingScreen()),
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
        path: RoutePaths.protocolPlus,
        name: RouteNames.protocolPlus,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final deviceIds =
              extra?['deviceIds'] as List<String>? ?? const <String>[];
          final transport = extra?['transport'] as String? ?? 'ble';
          return ProtocolPlusListScreen(
            deviceIds: deviceIds,
            transport: transport,
          );
        },
      ),
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
            final protocolPlusBindingsRaw =
                extra?['protocolPlusBindings'] as List?;
            final protocolPlusBindings = <ProtocolPlusBinding>[];
            if (protocolPlusBindingsRaw != null) {
              for (final raw in protocolPlusBindingsRaw) {
                if (raw is ProtocolPlusBinding) {
                  protocolPlusBindings.add(raw);
                } else if (raw is Map) {
                  final b = ProtocolPlusBinding.fromMap(raw);
                  if (b != null) protocolPlusBindings.add(b);
                }
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
              protocolPlusId: extra?['protocolPlusId'] as String?,
              protocolPlusServerSessionId:
                  extra?['protocolPlusServerSessionId'] as String?,
              protocolPlusMac: extra?['protocolPlusMac'] as String?,
              protocolPlusBindings: protocolPlusBindings,
              protocolPlusPending:
                  extra?['protocolPlusPending'] as bool? ?? false,
              remoteView: extra?['remoteView'] as bool? ?? false,
              backendSessionId: extra?['backendSessionId'] as String?,
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
          builder: (c, s) => SessionDetailScreen(
                sessionId: s.pathParameters['id']!,
                item: s.extra is SessionHistoryItem
                    ? s.extra as SessionHistoryItem
                    : null,
              )),
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
      GoRoute(
        path: RoutePaths.aiReport,
        name: RouteNames.aiReport,
        builder: (c, s) {
          final extra = s.extra;
          final report = extra is Map<String, dynamic> ? extra : null;
          return AiReportScreen(report: report);
        },
      ),
      GoRoute(
        path: RoutePaths.aiReports,
        name: RouteNames.aiReports,
        builder: (c, s) {
          final extra = s.extra;
          final m = extra is Map<String, dynamic> ? extra : const {};
          return AiReportsListScreen(
            clientId: m['clientId'] as String?,
            title: m['title'] as String?,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.aiReportClients,
        name: RouteNames.aiReportClients,
        builder: (c, s) => const ClientsListScreen(),
      ),
      GoRoute(
        path: RoutePaths.clientHome,
        name: RouteNames.clientHome,
        builder: (c, s) => const ClientSessionScreen(),
      ),
      GoRoute(
        path: RoutePaths.clientLease,
        name: RouteNames.clientLease,
        builder: (c, s) {
          final extra = s.extra;
          final m = extra is Map<String, dynamic> ? extra : const {};
          return ClientLeaseScreen(
            clientId: (m['clientId'] as String?) ?? '',
            title: m['title'] as String?,
          );
        },
      ),
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

    // Backend-driven live feed (same source as the History → Live tab) so the
    // badge stays consistent and clears when a session stops/finishes.
    final activeSessions = ref.watch(liveSessionsProvider);
    final activeBackgroundCount =
        activeSessions.where(_isVisibleActiveSession).length;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          // Web-parity: dark slate nav chrome (both modes).
          color: ThemeConstants.navBackground,
          border: Border(
            top: BorderSide(
              color: ThemeConstants.onNav.withValues(alpha: 0.10),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.12),
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
    // Nav chrome is the dark slate background in both modes, so inactive
    // items are cream (onNav) dimmed; active items use the tan accent.
    final inactiveColor = ThemeConstants.onNav.withValues(alpha: 0.60);

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
                              color: ThemeConstants.navBackground,
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
