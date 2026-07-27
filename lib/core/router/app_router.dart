import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/hw_tokens.dart';
import '../theme/widgets/hw_icon.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/providers/client_auth_provider.dart';
import '../../features/assistant/presentation/screens/assistant_screen.dart';
import '../../features/performance_protocols/presentation/screens/performance_protocols_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/devices/presentation/screens/device_detail_screen.dart';
import '../../features/devices/presentation/screens/device_list_screen.dart';
import '../../features/devices/presentation/screens/device_register_screen.dart';
import '../../features/home/presentation/screens/hub_screen.dart';
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
import '../../features/ai_hub/presentation/screens/ai_hub_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/settings/presentation/screens/legal_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/subscription_screen.dart';
import '../../features/presets/presentation/screens/preset_management_screen.dart';
import '../../features/ai_chat/presentation/screens/chat_screen.dart';
import '../../features/ai_report/presentation/screens/ai_report_screen.dart';
import '../../features/ai_report/presentation/screens/ai_reports_list_screen.dart';
import '../../features/ai_report/presentation/screens/kinetic_chain_3d_screen.dart';
import '../../features/clients/presentation/screens/clients_list_screen.dart';
import '../../features/clients/presentation/screens/users_screen.dart';
import '../../features/clients/presentation/screens/client_detail_screen.dart';
import '../../features/clients/presentation/screens/client_lease_screen.dart';
import '../../features/client_session/presentation/screens/client_session_screen.dart';
import 'route_names.dart';
import '../../features/auth/presentation/screens/select_organization_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Bridges auth changes into something GoRouter can refresh on.
///
/// The router must NOT be rebuilt when auth state changes. `HydrawavApp`
/// watches [routerProvider] and hands the result to `MaterialApp.router`, so a
/// new GoRouter means a new `routerConfig` — and the replacement Router claims
/// the same `_rootNavigatorKey` / `_shellNavigatorKey` while the outgoing one
/// is still mounted. That duplicate-GlobalKey collision blanks the screen until
/// the next navigation, which is exactly what switching organization used to
/// do. Refreshing a stable router re-runs `redirect` without rebuilding it.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(clientAuthProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = _AuthRefreshNotifier(ref);
  ref.onDispose(authRefresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.login,
    refreshListenable: authRefresh,
    redirect: (context, state) {
      // Read (never watch) inside redirect — the refreshListenable above is
      // what re-runs this, and watching here would rebuild the router.
      final authState = ref.read(authStateProvider);
      // Client (at-home) sessions authenticate separately from practitioners;
      // the router must treat an authenticated client as logged-in too, and
      // skip the practitioner-only org-selection gate.
      final isClientAuth = ref.read(clientAuthProvider).isAuthenticated;
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
          path: RoutePaths.onboarding,
          name: RouteNames.onboarding,
          builder: (c, s) => const OnboardingScreen()),
      GoRoute(
        path: '/select-organization',
        name: RouteNames.selectOrganization,
        builder: (c, s) => SelectOrganizationPage(
          startInCreateMode: s.uri.queryParameters['create'] == '1',
        ),
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
              path: RoutePaths.home,
              name: RouteNames.home,
              builder: (c, s) => const HubScreen()),
          // The protocol catalogue keeps its route; the spec reaches it from
          // More → Protocol Library rather than from a nav tab.
          GoRoute(
              path: RoutePaths.protocols,
              name: RouteNames.protocols,
              builder: (c, s) => const ProtocolListScreen()),
          GoRoute(
              path: RoutePaths.devices,
              name: RouteNames.devices,
              builder: (c, s) => const DeviceListScreen()),
          GoRoute(
              path: RoutePaths.assistant,
              name: RouteNames.assistant,
              builder: (c, s) =>
                  AssistantScreen(intent: s.uri.queryParameters['intent'])),
          // The pad_protocols catalogue as dropdowns — the browsing counterpart
          // to the Assistant's chip flow. Both end on the same pad map.
          GoRoute(
              path: RoutePaths.performanceProtocols,
              name: RouteNames.performanceProtocols,
              builder: (c, s) => const PerformanceProtocolsScreen()),
          GoRoute(
              path: RoutePaths.ai,
              name: RouteNames.ai,
              builder: (c, s) => const AiHubScreen()),
          GoRoute(
              path: RoutePaths.users,
              name: RouteNames.users,
              builder: (c, s) => const UsersScreen()),
          // Still routable on its own (deep links, "see all history" pushes);
          // the nav tab now opens the Users screen, whose History segment
          // renders this same list.
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
      // Edit profile and Change password are bottom sheets now (the UI spec's
      // `profileSheet()` / `passwordSheet()`), so they have no routes.
      GoRoute(
          path: RoutePaths.subscription,
          name: RouteNames.subscription,
          builder: (c, s) => const SubscriptionScreen()),
      GoRoute(
          path: RoutePaths.notifications,
          name: RouteNames.notifications,
          builder: (c, s) => const NotificationsScreen()),
      GoRoute(
          path: RoutePaths.legal,
          name: RouteNames.legal,
          builder: (c, s) => const LegalScreen()),
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
        path: RoutePaths.kineticChain3d,
        name: RouteNames.kineticChain3d,
        builder: (c, s) {
          final m = s.extra is Map<String, dynamic>
              ? s.extra as Map<String, dynamic>
              : const <String, dynamic>{};
          return KineticChain3DScreen(
            patternLabel: (m['patternLabel'] as String?) ?? '3D Kinetic Chain',
            payload: (m['payload'] as Map<String, dynamic>?) ??
                const <String, dynamic>{},
          );
        },
      ),
      GoRoute(
        path: RoutePaths.clientHome,
        name: RouteNames.clientHome,
        builder: (c, s) => const ClientSessionScreen(),
      ),
      GoRoute(
        path: RoutePaths.clientDetail,
        name: RouteNames.clientDetail,
        builder: (c, s) {
          final extra = s.extra;
          final m = extra is Map<String, dynamic> ? extra : const {};
          return ClientDetailScreen(
            clientId: (m['clientId'] as String?) ?? '',
            title: m['title'] as String?,
          );
        },
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
    final idx = _tabIndexFor(location);

    // Backend-driven live feed (same source as the History → Live tab) so the
    // badge stays consistent and clears when a session stops/finishes.
    final activeSessions = ref.watch(liveSessionsProvider);
    final activeBackgroundCount =
        activeSessions.where(_isVisibleActiveSession).length;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          // styles.css:297 — brand navy, hard-coded identical in light and
          // dark, and deliberately opaque (the nav has no blur).
          color: _navBg,
          border: Border(
            top: BorderSide(color: Color.fromRGBO(255, 255, 255, .07)),
          ),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(16, 20, 24, .28),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
            child: Row(
              children: [
                _NavTab(
                    asset: HwIcons.home,
                    label: 'Hub',
                    active: idx == 0,
                    onTap: () => context.go(RoutePaths.home)),
                const SizedBox(width: 4),
                _NavTab(
                    asset: HwIcons.bolt,
                    label: 'Session',
                    active: idx == 1,
                    // Live runs surface on the Session Plan screen (above
                    // Select User), so the running-session badge points here.
                    badgeCount: activeBackgroundCount,
                    onTap: () => context.go(RoutePaths.devices)),
                const SizedBox(width: 4),
                _NavTab(
                    asset: HwIcons.assistant,
                    label: 'Assistant',
                    active: idx == 2,
                    onTap: () => context.go(RoutePaths.assistant)),
                const SizedBox(width: 4),
                _NavTab(
                    asset: HwIcons.users,
                    label: 'Users',
                    active: idx == 3,
                    onTap: () => context.go(RoutePaths.users)),
                const SizedBox(width: 4),
                _NavTab(
                    asset: HwIcons.more,
                    label: 'More',
                    active: idx == 4,
                    onTap: () => context.go(RoutePaths.settings)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `#1B2830` — styles.css:297. Not a theme token: the spec fixes the nav to
/// brand navy in both light and dark for a high-contrast footer.
const Color _navBg = Color(0xFF1B2830);
const Color _navOn = Color(0xFFFFFFFF);
const Color _navOff = Color.fromRGBO(244, 239, 234, .55);

/// Which tab lights up for a given location.
///
/// Mirrors the spec's `NAV_ALIAS` (app.js:362): screens reached *from* a tab
/// keep that tab lit rather than dropping the highlight. History belongs to
/// Users; the protocol catalogue, presets, AI and settings sub-screens are all
/// entered from More.
int _tabIndexFor(String location) {
  if (location.startsWith(RoutePaths.devices)) return 1;
  if (location.startsWith(RoutePaths.assistant)) return 2;
  if (location.startsWith(RoutePaths.users) ||
      location.startsWith(RoutePaths.history)) {
    return 3;
  }
  if (location.startsWith(RoutePaths.settings) ||
      location.startsWith(RoutePaths.protocols) ||
      location.startsWith(RoutePaths.protocolPlus) ||
      location.startsWith(RoutePaths.presets) ||
      location.startsWith(RoutePaths.chat) ||
      location.startsWith(RoutePaths.notifications) ||
      location.startsWith(RoutePaths.legal) ||
      location.startsWith('/ai-')) {
    return 4;
  }
  return 0;
}

class _NavTab extends StatelessWidget {
  final String asset;
  final String label;
  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavTab(
      {required this.asset,
      required this.label,
      required this.active,
      this.badgeCount = 0,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? _navOn : _navOff;

    return Expanded(
      child: _NavPress(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Active icon rides 2px up on the spring curve (styles.css:305).
              AnimatedSlide(
                offset: active ? const Offset(0, -0.09) : Offset.zero,
                duration: HwMotion.t3,
                curve: HwMotion.spring,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    HwIcon(asset, size: 22, color: color),
                    if (badgeCount > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: RefPalette.light.low,
                            borderRadius:
                                BorderRadius.circular(HwRadius.pill),
                            border: Border.all(color: _navBg, width: 2),
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
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              // The only active indicator the spec has — a 4px copper dot.
              // No pill, no underline.
              AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RefPalette.light.copper,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `#bottomnav button:active{transform:scale(.9)}` + the selection haptic that
/// Principles §7 requires on every tap.
class _NavPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _NavPress({required this.child, required this.onTap});

  @override
  State<_NavPress> createState() => _NavPressState();
}

class _NavPressState extends State<_NavPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _down = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: HwMotion.t1,
        curve: HwMotion.spring,
        child: widget.child,
      ),
    );
  }
}
