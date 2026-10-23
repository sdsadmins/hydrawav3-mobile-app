// [AUTH-02] both backends fail -> red SnackBar, stays on login, busy resets.
// [AUTH-03] empty submit shows "Required" under each field and calls neither
//           backend; username-only leaves "Required" on Password only.
// [AUTH-04] a 3-space username must be rejected as "Required" with no backend
//           call. KNOWN BUG: the username validator uses `isEmpty` without a
//           trim (login_screen.dart:185), so blank-but-spaces slips through and
//           both backends are called. Tagged qa-known-bug: it fails honestly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/constants/theme_constants.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/providers/client_auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/login_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

/// A practitioner notifier that records login attempts and never authenticates;
/// [error] becomes the surfaced auth error (as a real failed Django login does).
class _RecordingAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _RecordingAuth({this.error}) : super(const AuthState(isInitialized: true));
  final String? error;
  int logins = 0;

  @override
  Future<void> login(LoginRequest request) async {
    logins++;
    state = state.copyWith(error: error);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A client notifier that records login attempts; returns [succeed] and, when
/// failing, exposes [error] (as a real failed Node client login does).
class _RecordingClientAuth extends StateNotifier<ClientAuthState>
    implements ClientAuthNotifier {
  _RecordingClientAuth({this.succeed = false, this.error})
      : super(const ClientAuthState());
  final bool succeed;
  final String? error;
  int logins = 0;

  @override
  Future<bool> login({
    required String clientName,
    required String password,
  }) async {
    logins++;
    if (!succeed) state = state.copyWith(error: error);
    return succeed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadAppFonts);

  Future<(_RecordingAuth, _RecordingClientAuth)> pumpLogin(
    WidgetTester tester, {
    String? practError,
    String? clientError,
    bool clientSucceeds = false,
  }) async {
    final auth = _RecordingAuth(error: practError);
    final client =
        _RecordingClientAuth(succeed: clientSucceeds, error: clientError);
    await pumpApp(
      tester,
      const LoginScreen(),
      overrides: [
        authStateProvider.overrideWith((ref) => auth),
        clientAuthProvider.overrideWith((ref) => client),
      ],
    );
    return (auth, client);
  }

  qaTestWidgets('[AUTH-02] both backends fail shows a red error and stays put',
      (tester) async {
    final (auth, client) = await pumpLogin(
      tester,
      practError: 'Incorrect username or password. Please try again.',
      clientError: 'Invalid credentials or the lease is not active.',
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'marcus');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass');
    await tester.tap(find.text('Sign in'));
    await tester.pump(); // submit -> busy
    await tester.pump(const Duration(milliseconds: 400)); // SnackBar in

    // Both backends were tried, and the most specific (client) error shows.
    expect(auth.logins, 1);
    expect(client.logins, 1);
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, ThemeConstants.error);
    expect(
      find.widgetWithText(
          SnackBar, 'Invalid credentials or the lease is not active.'),
      findsOneWidget,
    );

    // Route stays on the login screen; the Sign in button is no longer busy.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(seconds: 5)); // drain SnackBar timer
  });

  qaTestWidgets('[AUTH-03] empty submit shows Required and calls no backend',
      (tester) async {
    final (auth, client) = await pumpLogin(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    // One "Required" under Username and one under Password.
    expect(find.text('Required'), findsNWidgets(2));
    expect(auth.logins, 0);
    expect(client.logins, 0);

    // Fill only the username -> only Password still says Required.
    await tester.enterText(find.byType(TextFormField).at(0), 'marcus');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
    expect(auth.logins, 0);
    expect(client.logins, 0);
  });

  qaTestWidgets(
    '[AUTH-04] a 3-space username is Required and calls no backend',
    (tester) async {
      final (auth, client) = await pumpLogin(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '   ');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Correct behaviour: a whitespace-only username is empty, so validation
      // blocks the submit and no backend is called.
      expect(find.text('Required'), findsOneWidget);
      expect(auth.logins, 0);
      expect(client.logins, 0);

      await tester.pump(const Duration(seconds: 5));
    },
    tags: ['qa-known-bug'],
  );
}
