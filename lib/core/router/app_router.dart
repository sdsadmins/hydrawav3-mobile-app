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
import '../../features/session/presentation/screens/session_screen.dart';
import '../../features/settings/presentation/screens/change_password_screen.dart';
import '../../features/settings/presentation/screens/profile_edit_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/subscription_screen.dart';
import '../../features/presets/presentation/screens/preset_management_screen.dart';
import '../../features/ai_chat/presentation/screens/chat_screen.dart';
import '../constants/theme_constants.dart';
import 'route_names.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.protocols,
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final isAuthRoute = state.matchedLocation == RoutePaths.login ||
          state.matchedLocation == RoutePaths.signup ||
          state.matchedLocation == RoutePaths.forgotPassword;
      if (!isAuth && !isAuthRoute) return RoutePaths.login;
      if (isAuth && isAuthRoute) return RoutePaths.protocols;
      return null;
    },
    routes: [
      GoRoute(path: RoutePaths.login, name: RouteNames.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: RoutePaths.signup, name: RouteNames.signup, builder: (c, s) => const SignupScreen()),
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
        return SessionScreen(protocolId: extra?['protocolId'] as String? ?? '', deviceIds: extra?['deviceIds'] as List<String>? ?? []);
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
    // 2 = session (center button)
    if (location.startsWith(RoutePaths.history)) idx = 3;
    if (location.startsWith(RoutePaths.settings)) idx = 4;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          border: const Border(top: BorderSide(color: ThemeConstants.border, width: 1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', active: idx == 0, onTap: () => context.go(RoutePaths.protocols)),
                    _NavTab(icon: Icons.bluetooth_outlined, activeIcon: Icons.bluetooth_connected_rounded, label: 'Devices', active: idx == 1, onTap: () => context.go(RoutePaths.devices)),
                    const Expanded(child: SizedBox()), // space for center button
                    _NavTab(icon: Icons.history_outlined, activeIcon: Icons.history_rounded, label: 'History', active: idx == 3, onTap: () => context.go(RoutePaths.history)),
                    _NavTab(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings', active: idx == 4, onTap: () => context.go(RoutePaths.settings)),
                  ],
                ),
                // Raised center session button
                Positioned(
                  top: -16,
                  child: GestureDetector(
                    onTap: () => context.go(RoutePaths.history),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [ThemeConstants.accentLight, ThemeConstants.accent]),
                            shape: BoxShape.circle,
                            border: Border.all(color: ThemeConstants.background, width: 4),
                            boxShadow: [
                              BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 2),
                        Text('Session', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ThemeConstants.textSecondary)),
                      ],
                    ),
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
            Icon(active ? activeIcon : icon, size: 24, color: active ? ThemeConstants.accentLight : ThemeConstants.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? ThemeConstants.accentLight : ThemeConstants.textSecondary)),
          ],
        ),
      ),
    );
  }
}
