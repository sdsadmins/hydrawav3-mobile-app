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

      if (!isAuthenticated && !isAuthRoute) {
        return RoutePaths.login;
      }
      if (isAuthenticated && isAuthRoute) {
        return RoutePaths.protocols;
      }
      return null;
    },
    routes: [
      // Auth routes (no bottom nav)
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

      // Main app with bottom navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) =>
            _ScaffoldWithNavBar(child: child),
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

      // Full-screen routes (no bottom nav)
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

class _ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;

  const _ScaffoldWithNavBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (index) => _onItemTapped(index, context),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Protocols',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(RoutePaths.protocols)) return 0;
    if (location.startsWith(RoutePaths.devices)) return 1;
    if (location.startsWith(RoutePaths.history)) return 2;
    if (location.startsWith(RoutePaths.settings)) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go(RoutePaths.protocols);
      case 1:
        context.go(RoutePaths.devices);
      case 2:
        context.go(RoutePaths.history);
      case 3:
        context.go(RoutePaths.settings);
    }
  }
}
