// [AUTH-21] A client (at-home) session authenticated, practitioner not: the
//           router's redirect sends every practitioner surface back to the
//           client's home (/client-home).
// [AUTH-22] After a client logout (neither practitioner nor client signed in):
//           /client-home is no longer reachable and redirects to /login.
//
// Drives the REAL routerProvider redirect (lib/core/router/app_router.dart).
// The client-home landing screen's data providers are stubbed so the screen
// builds without touching the network.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/constants/theme_constants.dart';
import 'package:hydrawav3/core/router/app_router.dart';
import 'package:hydrawav3/core/router/route_names.dart';
import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/data/client_auth_remote_source.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/providers/client_auth_provider.dart';
import 'package:hydrawav3/features/client_session/presentation/providers/client_session_controller.dart';
import 'package:hydrawav3/features/client_session/presentation/screens/client_session_screen.dart';
import 'package:hydrawav3/features/auth/presentation/screens/login_screen.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/splash/presentation/screens/splash_screen.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

/// A client-auth notifier with a fixed state (authenticated or not).
class _ClientAuth extends StateNotifier<ClientAuthState>
    implements ClientAuthNotifier {
  _ClientAuth(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ClientAuthState _signedInClient() => const ClientAuthState(
      session: ClientSession(
        accessToken: '',
        refreshToken: '',
        clientId: 'c1',
        clientName: 'Pat',
      ),
    );

/// An idle client-session controller so /client-home renders its select state.
class _IdleClientSession extends StateNotifier<ClientSessionState>
    implements ClientSessionController {
  _IdleClientSession() : super(const ClientSessionState());
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<GoRouterProbe> _pumpRouter(
  WidgetTester tester, {
  required AuthState auth,
  required ClientAuthState client,
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  setTestViewSize(tester, QaDevice.phone.size);
  ThemeConstants.useBrightness(Brightness.light);
  addTearDown(() => ThemeConstants.useBrightness(Brightness.light));

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    authStateProvider.overrideWith((ref) => FakeAuth.withState(auth)),
    clientAuthProvider.overrideWith((ref) => _ClientAuth(client)),
    // Keep the splash gate open so redirects run immediately.
    splashHoldProvider.overrideWith((ref) => false),
    // Stub the client-home data so the screen builds without the network.
    clientSessionBodyPartsProvider.overrideWith((ref) async => <String>[]),
    clientSessionProtocolsProvider.overrideWith((ref) async => <Protocol>[]),
    clientSessionControllerProvider.overrideWith((ref) => _IdleClientSession()),
  ]);
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: qaThemeFor(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return GoRouterProbe(router);
}

class GoRouterProbe {
  GoRouterProbe(this.router);
  final dynamic router;
  String get location =>
      router.routerDelegate.currentConfiguration.uri.path as String;
  Future<void> go(WidgetTester tester, String path) async {
    router.go(path);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(loadAppFonts);

  qaTestWidgets(
      '[AUTH-21] a signed-in client is kept on /client-home for every '
      'practitioner surface', (tester) async {
    final probe = await _pumpRouter(
      tester,
      auth: const AuthState(isInitialized: true), // practitioner NOT signed in
      client: _signedInClient(),
    );

    // Splash itself already lands the client on their home.
    expect(probe.location, RoutePaths.clientHome);
    expect(find.byType(ClientSessionScreen), findsOneWidget);

    for (final path in <String>[
      RoutePaths.home,
      RoutePaths.devices,
      RoutePaths.settings,
      RoutePaths.users,
      '/select-organization',
    ]) {
      await probe.go(tester, path);
      expect(probe.location, RoutePaths.clientHome,
          reason: '$path should redirect to /client-home');
      expect(find.byType(ClientSessionScreen), findsOneWidget);
    }
  });

  qaTestWidgets(
      '[AUTH-22] after client logout /client-home redirects to /login',
      (tester) async {
    final probe = await _pumpRouter(
      tester,
      auth: const AuthState(isInitialized: true), // nobody signed in
      client: const ClientAuthState(),
    );

    // Neither session: the splash hands off to login.
    expect(probe.location, RoutePaths.login);
    expect(find.byType(LoginScreen), findsOneWidget);

    await probe.go(tester, RoutePaths.clientHome);
    expect(probe.location, RoutePaths.login);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
