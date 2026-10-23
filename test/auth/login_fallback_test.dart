// [AUTH-07] Unified login fallback: the practitioner (Django) login fails, the
//           client (Node) login succeeds. No error SnackBar is ever shown and
//           the router lands on the client's home (/client-home).
//
// Exercises the real LoginScreen flow and the real routerProvider redirect.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/constants/theme_constants.dart';
import 'package:hydrawav3/core/router/app_router.dart';
import 'package:hydrawav3/core/router/route_names.dart';
import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/data/client_auth_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/providers/client_auth_provider.dart';
import 'package:hydrawav3/features/client_session/presentation/providers/client_session_controller.dart';
import 'package:hydrawav3/features/client_session/presentation/screens/client_session_screen.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/splash/presentation/screens/splash_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

/// Practitioner login always fails (a failed Django login never authenticates;
/// AuthNotifier swallows the backend error, so the screen falls back).
class _FailingAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FailingAuth() : super(const AuthState(isInitialized: true));
  int logins = 0;
  @override
  Future<void> login(LoginRequest request) async {
    logins++;
    state = state.copyWith(
        error: 'Incorrect username or password. Please try again.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Client login succeeds and establishes a session.
class _SucceedingClientAuth extends StateNotifier<ClientAuthState>
    implements ClientAuthNotifier {
  _SucceedingClientAuth() : super(const ClientAuthState());
  int logins = 0;
  @override
  Future<bool> login({
    required String clientName,
    required String password,
  }) async {
    logins++;
    state = const ClientAuthState(
      session: ClientSession(
        accessToken: '',
        refreshToken: '',
        clientId: 'c1',
        clientName: 'Pat',
      ),
    );
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _IdleClientSession extends StateNotifier<ClientSessionState>
    implements ClientSessionController {
  _IdleClientSession() : super(const ClientSessionState());
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadAppFonts);

  qaTestWidgets(
      '[AUTH-07] practitioner fails, client succeeds: no error, lands on '
      '/client-home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    setTestViewSize(tester, QaDevice.phone.size);
    ThemeConstants.useBrightness(Brightness.light);
    addTearDown(() => ThemeConstants.useBrightness(Brightness.light));

    final auth = _FailingAuth();
    final client = _SucceedingClientAuth();

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      authStateProvider.overrideWith((ref) => auth),
      clientAuthProvider.overrideWith((ref) => client),
      splashHoldProvider.overrideWith((ref) => false),
      clientSessionBodyPartsProvider.overrideWith((ref) async => <String>[]),
      clientSessionProtocolsProvider.overrideWith((ref) async => <Protocol>[]),
      clientSessionControllerProvider
          .overrideWith((ref) => _IdleClientSession()),
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

    // Neither session yet -> we start on the login screen.
    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'pat@home');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // Both backends were tried; the client one won.
    expect(auth.logins, 1);
    expect(client.logins, 1);

    // No error SnackBar was ever shown, and the router redirected to the
    // client's home.
    expect(find.byType(SnackBar), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      RoutePaths.clientHome,
    );
    expect(find.byType(ClientSessionScreen), findsOneWidget);
  });
}
