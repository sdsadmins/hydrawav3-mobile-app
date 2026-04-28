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
import '../../features/session/presentation/screens/session_screen.dart';
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

  final isAuthRoute =
      state.matchedLocation == RoutePaths.login ||
      state.matchedLocation == RoutePaths.signup ||
      state.matchedLocation == RoutePaths.forgotPassword;

  final isSelectingOrg =
      state.matchedLocation == '/select-organization';

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
    return RoutePaths.protocols;
  }

  return null;


},
    routes: [
      GoRoute(path: RoutePaths.login, name: RouteNames.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: RoutePaths.signup, name: RouteNames.signup, builder: (c, s) => const SignupScreen()),
      GoRoute(
    path: '/select-organization',
    name: RouteNames.selectOrganization,
    builder: (c, s) => const SelectOrganizationPage(),
  ),
      GoRoute(path: RoutePaths.forgotPassword, name: RouteNames.forgotPassword, builder: (c, s) => const ForgotPasswordScreen()),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (c, s, child) => _AppShell(child: child),
        routes: [
          GoRoute(path: RoutePaths.protocols, name: RouteNames.protocols, builder: (c, s) => const ProtocolListScreen()),
          GoRoute(path: RoutePaths.devices, name: RouteNames.devices, builder: (c, s) => const DeviceListScreen()),
          GoRoute(path: RoutePaths.history, name: RouteNames.history, builder: (c, s) => const HistoryListScreen()),
          GoRoute(path: RoutePaths.settings, name: RouteNames.settings, builder: (c, s) => const SettingsScreen()),
          
        ],
      ),
      GoRoute(path: RoutePaths.protocolDetail, name: RouteNames.protocolDetail, builder: (c, s) => ProtocolDetailScreen(protocolId: s.pathParameters['id']!)),
      GoRoute(path: RoutePaths.session, name: RouteNames.session, builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        final anchorRaw = extra?['sessionClockAnchorMs'];
        final sessionClockAnchorMs = anchorRaw is int
            ? anchorRaw
            : (anchorRaw is num ? anchorRaw.toInt() : null);
        final advancedSettings =
            extra?['advancedSettings'] as AdvancedSettings? ?? const AdvancedSettings();
        final delayedDeviceId = extra?['delayedDeviceId'] as String?;
        return SessionScreen(
          protocolId: extra?['protocolId'] as String? ?? '',
          protocol: extra?['protocol'] as Protocol?,
          deviceIds: extra?['deviceIds'] as List<String>? ?? [],
          transport: extra?['transport'] as String? ?? 'ble',
          sessionClockAnchorMs: sessionClockAnchorMs,
          advancedSettings: advancedSettings,
          delayedDeviceId: delayedDeviceId,
        );
      }),
      GoRoute(path: RoutePaths.deviceRegister, name: RouteNames.deviceRegister, builder: (c, s) => const DeviceRegisterScreen()),
      GoRoute(path: RoutePaths.deviceDetail, name: RouteNames.deviceDetail, builder: (c, s) => DeviceDetailScreen(deviceId: s.pathParameters['id']!)),
      GoRoute(path: RoutePaths.sessionDetail, name: RouteNames.sessionDetail, builder: (c, s) => SessionDetailScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(path: RoutePaths.profileEdit, name: RouteNames.profileEdit, builder: (c, s) => const ProfileEditScreen()),
      GoRoute(path: RoutePaths.changePassword, name: RouteNames.changePassword, builder: (c, s) => const ChangePasswordScreen()),
      GoRoute(path: RoutePaths.subscription, name: RouteNames.subscription, builder: (c, s) => const SubscriptionScreen()),
      GoRoute(path: RoutePaths.presets, name: RouteNames.presets, builder: (c, s) => const PresetManagementScreen()),
      GoRoute(path: RoutePaths.chat, name: RouteNames.chat, builder: (c, s) => const ChatScreen()),
    ],
  );
});

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int idx = 0;
    if (location.startsWith(RoutePaths.devices)) idx = 1;
    if (location.startsWith(RoutePaths.history)) idx = 2;
    if (location.startsWith(RoutePaths.settings)) idx = 3;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: ThemeConstants.surface,
          border: Border(top: BorderSide(color: ThemeConstants.border, width: 1)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', active: idx == 0, onTap: () => context.go(RoutePaths.protocols)),
                _NavTab(icon: Icons.bluetooth_outlined, activeIcon: Icons.bluetooth_connected_rounded, label: 'Devices', active: idx == 1, onTap: () => context.go(RoutePaths.devices)),
                _NavTab(icon: Icons.history_outlined, activeIcon: Icons.history_rounded, label: 'History', active: idx == 2, onTap: () => context.go(RoutePaths.history)),
                _NavTab(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings', active: idx == 3, onTap: () => context.go(RoutePaths.settings)),
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
  final VoidCallback onTap;

  const _NavTab({required this.icon, required this.activeIcon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, size: 22, color: active ? ThemeConstants.accent : ThemeConstants.textTertiary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? ThemeConstants.accent : ThemeConstants.textTertiary)),
          ],
        ),
      ),
    );
  }
}
