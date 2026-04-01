import 'dart:ui';

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
      final isAuthenticated = authState.isAuthenticated;
      final isAuthRoute = state.matchedLocation == RoutePaths.login ||
          state.matchedLocation == RoutePaths.signup ||
          state.matchedLocation == RoutePaths.forgotPassword;

      if (!isAuthenticated && !isAuthRoute) return RoutePaths.login;
      if (isAuthenticated && isAuthRoute) return RoutePaths.protocols;
      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        name: RouteNames.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) =>
            _PremiumNavBar(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.protocols,
            name: RouteNames.protocols,
            builder: (context, state) => const ProtocolListScreen(),
          ),
          GoRoute(
            path: RoutePaths.devices,
            name: RouteNames.devices,
            builder: (context, state) => const DeviceListScreen(),
          ),
          GoRoute(
            path: RoutePaths.history,
            name: RouteNames.history,
            builder: (context, state) => const HistoryListScreen(),
          ),
          GoRoute(
            path: RoutePaths.settings,
            name: RouteNames.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.protocolDetail,
        name: RouteNames.protocolDetail,
        builder: (context, state) => ProtocolDetailScreen(
          protocolId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.session,
        name: RouteNames.session,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SessionScreen(
            protocolId: extra?['protocolId'] as String? ?? '',
            deviceIds: extra?['deviceIds'] as List<String>? ?? [],
          );
        },
      ),
      GoRoute(
        path: RoutePaths.deviceRegister,
        name: RouteNames.deviceRegister,
        builder: (context, state) => const DeviceRegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.deviceDetail,
        name: RouteNames.deviceDetail,
        builder: (context, state) => DeviceDetailScreen(
          deviceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.sessionDetail,
        name: RouteNames.sessionDetail,
        builder: (context, state) => SessionDetailScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.profileEdit,
        name: RouteNames.profileEdit,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: RoutePaths.changePassword,
        name: RouteNames.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.subscription,
        name: RouteNames.subscription,
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: RoutePaths.presets,
        name: RouteNames.presets,
        builder: (context, state) => const PresetManagementScreen(),
      ),
      GoRoute(
        path: RoutePaths.chat,
        name: RouteNames.chat,
        builder: (context, state) => const ChatScreen(),
      ),
    ],
  );
});

/// ✨ Premium frosted-glass bottom navigation bar
class _PremiumNavBar extends StatelessWidget {
  final Widget child;

  const _PremiumNavBar({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int selectedIndex = 0;
    if (location.startsWith(RoutePaths.protocols)) selectedIndex = 0;
    if (location.startsWith(RoutePaths.devices)) selectedIndex = 1;
    if (location.startsWith(RoutePaths.history)) selectedIndex = 2;
    if (location.startsWith(RoutePaths.settings)) selectedIndex = 3;

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(
                  color: ThemeConstants.divider.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.science_outlined,
                      activeIcon: Icons.science_rounded,
                      label: '⚗️ Protocols',
                      isActive: selectedIndex == 0,
                      onTap: () => context.go(RoutePaths.protocols),
                    ),
                    _NavItem(
                      icon: Icons.bluetooth_outlined,
                      activeIcon: Icons.bluetooth_connected_rounded,
                      label: '📡 Devices',
                      isActive: selectedIndex == 1,
                      onTap: () => context.go(RoutePaths.devices),
                    ),
                    _NavItem(
                      icon: Icons.history_outlined,
                      activeIcon: Icons.history_rounded,
                      label: '📊 History',
                      isActive: selectedIndex == 2,
                      onTap: () => context.go(RoutePaths.history),
                    ),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_rounded,
                      label: '⚙️ Settings',
                      isActive: selectedIndex == 3,
                      onTap: () => context.go(RoutePaths.settings),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? ThemeConstants.darkTeal.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusFull),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: isActive
                    ? ThemeConstants.darkTeal
                    : ThemeConstants.textTertiary,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? ThemeConstants.darkTeal
                    : ThemeConstants.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
