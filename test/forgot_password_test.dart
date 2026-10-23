import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/error/exceptions.dart';
import 'package:hydrawav3/features/auth/data/auth_repository.dart';
import 'package:hydrawav3/features/auth/presentation/screens/forgot_password_screen.dart';

class _FakeRepo implements AuthRepository {
  final sent = <String>[];
  bool fail = false;

  @override
  Future<void> requestPasswordReset(String email) async {
    if (fail) throw ServerException('No account with that email');
    sent.add(email);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// "Forgot password?" sends the web's `auth/forgot-password` request with the
/// typed email, and only shows "Check your email" once it went through.
void main() {
  Future<_FakeRepo> pump(WidgetTester tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ForgotPasswordScreen()),
    ));
    await tester.pump(const Duration(seconds: 1));
    return repo;
  }

  testWidgets('[AUTH-16] checks the email before sending', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets('[AUTH-17] sends the reset request and confirms', (tester) async {
    final repo = await pump(tester);
    await tester.enterText(find.byType(TextFormField), ' jane@clinic.com ');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.sent, ['jane@clinic.com']);
    expect(find.text('CHECK YOUR EMAIL'), findsOneWidget);
  });

  testWidgets('shows the server message when it fails', (tester) async {
    final repo = await pump(tester)..fail = true;
    await tester.enterText(find.byType(TextFormField), 'jane@clinic.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No account with that email'), findsOneWidget);
    expect(find.text('CHECK YOUR EMAIL'), findsNothing);
    expect(repo.sent, isEmpty);
  });

  testWidgets('lays out on a tablet', (tester) async {
    tester.view.physicalSize = const Size(834, 1112) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'jane@clinic.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.sent, ['jane@clinic.com']);
    expect(find.text('CHECK YOUR EMAIL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
