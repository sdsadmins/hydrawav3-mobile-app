// [AUTH-09] Create-organization form validation on the Select organization
// page: the errors surface one at a time, in field order, and nothing is sent
// until the form is complete.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/network/dio_client.dart';
import 'package:hydrawav3/features/auth/data/organization_repository.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart';
import 'package:hydrawav3/features/auth/presentation/widgets/auth_ui.dart';
import 'package:hydrawav3/features/payments/data/payment_repository.dart';

import '../helpers/fake_http.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

/// Records create attempts instead of talking to the backend.
class _RecordingOrgRepo implements OrganizationRepository {
  final calls = <Map<String, dynamic>>[];

  @override
  Future<String> createAndLinkOrganization({
    required String userId,
    required Map<String, dynamic> orgBody,
  }) async {
    calls.add(orgBody);
    return '42';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePayments implements PaymentRepository {
  @override
  Future<bool> ensureFreePlan(String orgId) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadAppFonts);

  qaTestWidgets(
    '[AUTH-09] create-org form reports one error at a time, in order, and '
    'never calls create',
    (tester) async {
      // No organizations yet → the page shows the create form; the list fetch
      // goes through the (interceptor-free) fake Django Dio.
      final server = FakeHttp()..onJson('GET', '/admin/organizations', []);
      final repo = _RecordingOrgRepo();

      await pumpApp(
        tester,
        const SelectOrganizationPage(startInCreateMode: true),
        overrides: [
          djangoDioProvider.overrideWith((ref) => server.dio()),
          authStateProvider.overrideWith((ref) => FakeAuth()),
          organizationRepositoryProvider.overrideWithValue(repo),
          paymentRepositoryProvider.overrideWithValue(_FakePayments()),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('CREATE YOUR ORGANIZATION'), findsOneWidget);
      final submit = find.widgetWithText(AuthPrimaryButton, 'Create organization');
      expect(submit, findsOneWidget);

      // Fields in the order the form lays them out: name, email, address,
      // age (optional), phone.
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(5));
      final name = fields.at(0);
      final email = fields.at(1);
      final address = fields.at(2);
      final phone = fields.at(4);

      Future<void> submitAndExpect(String error) async {
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(find.widgetWithText(AuthError, error), findsOneWidget,
            reason: 'expected "$error" to be the only error shown');
        expect(find.byType(AuthError), findsOneWidget);
      }

      // 1) Everything empty → name first.
      await submitAndExpect('Organization name is required.');

      // 2) Name filled → email required.
      await tester.enterText(name, 'Acme Wellness');
      await submitAndExpect('Email is required.');

      // 3) Email present but invalid → format error.
      await tester.enterText(email, 'not-an-email');
      await submitAndExpect('Enter a valid email address.');

      // 4) Valid email → address required.
      await tester.enterText(email, 'org@example.com');
      await submitAndExpect('Address is required.');

      // 5) Address filled → phone required (age is optional and stays empty).
      await tester.enterText(address, '123 Main St');
      await submitAndExpect('Phone number is required.');

      // Nothing was ever sent while the form was incomplete.
      expect(repo.calls, isEmpty);
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);

      // Sanity: once the form is complete the create call is made exactly
      // once with the typed values. (The success tail then selects the org
      // and calls context.go(); there is no router under test, so the page
      // reports a generic error afterwards — not what this case is about.)
      await tester.enterText(phone, '+1 555 000 0000');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['name'], 'Acme Wellness');
      expect(repo.calls.single['mail'], 'org@example.com');
      expect(repo.calls.single['address'], '123 Main St');
      expect(repo.calls.single['phone'], '+1 555 000 0000');
      expect(repo.calls.single['age'], '');
    },
  );
}
