// [R4-15] Onboarding step 1 (Practitioner Information) no longer asks for an
// address or a date of birth, and validateStep1 passes without an address.
//
// KNOWN BUG (qa-known-bug): the Address field is still rendered and
// `OnboardingController.validateStep1` still requires `address`
// (lib/features/auth/presentation/providers/onboarding_provider.dart:145,
// lib/features/auth/presentation/screens/onboarding_screen.dart:353), so
// these tests fail against today's code. Date of Birth is already hidden.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/data/onboarding_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/onboarding_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/onboarding_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/onboarding_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

class _FakeOnboardingSource implements OnboardingRemoteSource {
  @override
  Future<List<SportOption>> getSports() async => const [];

  @override
  Future<List<AccountTypeOption>> getAccountTypes() async =>
      const [AccountTypeOption(id: '1', name: 'Clinic')];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Every step-1 field EXCEPT the address.
const _withoutAddress = PractitionerForm(
  firstName: 'Jane',
  lastName: 'Doe',
  username: 'janedoe',
  password: 'longenough',
  email: 'jane@example.com',
  phone: '5551234567',
  title: 'Physiotherapist',
  accountType: '1',
  city: 'Los Angeles',
  state: 'CA',
  zip: '90001',
  country: 'USA',
);

void main() {
  qaTestWidgets(
    '[R4-15] onboarding step 1 shows no Address and no Date of Birth field',
    (tester) async {
      await pumpApp(
        tester,
        const OnboardingScreen(),
        overrides: [
          onboardingRemoteSourceProvider
              .overrideWithValue(_FakeOnboardingSource()),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Step 1 of 4 · Practitioner'), findsOneWidget);
      // The other step-1 fields are still there...
      expect(find.textContaining(RegExp(r'^First Name')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^City')), findsOneWidget);
      // ...but neither of these is asked for any more. Labels render as
      // "Address *" when required, hence the prefix match.
      expect(find.textContaining('Date of Birth'), findsNothing);
      expect(find.textContaining(RegExp(r'^Address')), findsNothing);
    },
    tags: ['qa-known-bug'],
  );

  test('[R4-15] validateStep1 passes without an address', () {
    final container = ProviderContainer(overrides: [
      onboardingRemoteSourceProvider.overrideWithValue(_FakeOnboardingSource()),
    ]);
    addTearDown(container.dispose);
    container.listen(onboardingControllerProvider, (_, __) {});
    final controller = container.read(onboardingControllerProvider.notifier);

    final ok = controller.validateStep1(_withoutAddress);
    final errors = container.read(onboardingControllerProvider).step1Errors;

    expect(errors, isNot(contains('address')),
        reason: 'address must not be a required step-1 field');
    expect(ok, isTrue);
  }, tags: ['qa-known-bug']);
}
