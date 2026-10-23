// Onboarding ("Create account") validation.
//
// [AUTH-12] step-1 field rules (OnboardingController.validateStep1)
// [AUTH-13] the End User Agreement gate
// [AUTH-14] the Business step's messages (OnboardingScreen step 3)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/data/onboarding_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/onboarding_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/onboarding_provider.dart';
import 'package:hydrawav3/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:hydrawav3/features/auth/presentation/widgets/auth_ui.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

/// Answers the public catalogue calls and records account creation.
class _FakeOnboardingSource implements OnboardingRemoteSource {
  final createCalls = <Map<String, dynamic>>[];

  @override
  Future<List<SportOption>> getSports() async => const [];

  @override
  Future<List<AccountTypeOption>> getAccountTypes() async =>
      const [AccountTypeOption(id: '1', name: 'Clinic')];

  @override
  Future<({String userId, String token})> createPractitioner(
    Map<String, dynamic> data,
  ) async {
    createCalls.add(data);
    return (userId: 'u1', token: 't1');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A step-1 form with every required field filled.
const _complete = PractitionerForm(
  firstName: 'Jane',
  lastName: 'Doe',
  username: 'janedoe',
  password: 'longenough',
  email: 'jane@example.com',
  phone: '5551234567',
  title: 'Physiotherapist',
  accountType: '1',
  address: '123 Main St',
  city: 'Los Angeles',
  state: 'CA',
  zip: '90001',
  country: 'USA',
);

const _business = OnboardingBusiness(
  name: 'Hydrawa Clinic',
  businessAge: '1-3 Years',
  email: 'clinic@example.com',
  contactNumber: '5557654321',
  address: '456 Clinic Ave',
);

({ProviderContainer container, OnboardingController controller, _FakeOnboardingSource remote})
    _harness() {
  final remote = _FakeOnboardingSource();
  final container = ProviderContainer(overrides: [
    onboardingRemoteSourceProvider.overrideWithValue(remote),
  ]);
  addTearDown(container.dispose);
  // autoDispose: keep the controller alive for the test.
  container.listen(onboardingControllerProvider, (_, __) {});
  return (
    container: container,
    controller: container.read(onboardingControllerProvider.notifier),
    remote: remote,
  );
}

void main() {
  group('[AUTH-12] step 1 validation', () {
    test('[AUTH-12] every empty required field reads "Required"', () async {
      final h = _harness();
      final ok = h.controller.validateStep1(const PractitionerForm());
      expect(ok, isFalse);

      final errors = h.container.read(onboardingControllerProvider).step1Errors;
      for (final key in [
        'firstName',
        'lastName',
        'username',
        'email',
        'phone',
        'title',
        'accountType',
        'address',
        'city',
        'state',
        'zip',
        'country',
        'password',
      ]) {
        expect(errors[key], 'Required', reason: key);
      }
      await Future<void>.delayed(Duration.zero);
      expect(h.remote.createCalls, isEmpty);
    });

    test('[AUTH-12] a 7-character password is too short; 8 passes', () {
      final h = _harness();

      expect(
        h.controller.validateStep1(_complete.copyWith(password: 'abcdefg')),
        isFalse,
      );
      expect(
        h.container.read(onboardingControllerProvider).step1Errors['password'],
        'Must be at least 8 characters',
      );

      expect(
        h.controller.validateStep1(_complete.copyWith(password: 'abcdefgh')),
        isTrue,
      );
      expect(
        h.container.read(onboardingControllerProvider).step1Errors,
        isEmpty,
      );
      expect(h.remote.createCalls, isEmpty);
    });

    test('[AUTH-12] a malformed email is rejected; createAccount never runs',
        () async {
      final h = _harness();

      expect(
        h.controller.validateStep1(_complete.copyWith(email: 'jane@nowhere')),
        isFalse,
      );
      expect(
        h.container.read(onboardingControllerProvider).step1Errors['email'],
        'Enter a valid email address',
      );
      expect(h.controller.isValidEmail('jane@nowhere'), isFalse);
      expect(h.controller.isValidEmail('jane@example.com'), isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(h.remote.createCalls, isEmpty);
    });
  });

  group('[AUTH-13] End User Agreement gate', () {
    test(
        '[AUTH-13] unticked EUA blocks submit with the agreement message, '
        'step stays 0, nothing is created', () async {
      final h = _harness();
      h.controller.validateStep1(_complete);
      h.controller.addBusiness(_business);
      expect(h.container.read(onboardingControllerProvider).euaAccepted, isFalse);

      await h.controller.submit();

      final s = h.container.read(onboardingControllerProvider);
      expect(s.error, 'Please accept the End User Agreement.');
      expect(s.currentStep, 0);
      expect(s.hasAccount, isFalse);
      expect(s.submitted, isFalse);
      expect(h.remote.createCalls, isEmpty);
    });
  });

  group('[AUTH-14] Business step messages', () {
    qaTestWidgets(
      '[AUTH-14] Business step: none added, incomplete draft, bad email',
      (tester) async {
        final remote = _FakeOnboardingSource();
        await pumpApp(
          tester,
          const OnboardingScreen(),
          overrides: [
            onboardingRemoteSourceProvider.overrideWithValue(remote),
          ],
        );
        await pumpFrames(tester);

        // Jump to the Business step (index 2) the way the controller does.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingScreen)),
        );
        container.read(onboardingControllerProvider.notifier).goTo(2);
        await tester.pumpAndSettle();
        expect(find.text('Step 3 of 4 · Business'), findsOneWidget);

        // `_snack` hides the current SnackBar (animated) before showing the
        // next, so settle after each tap and let the bar expire before moving
        // on.
        Future<void> expireSnack() async {
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
        }

        // 1) Continue with no business linked.
        final cont = find.widgetWithText(AuthPrimaryButton, 'Continue');
        await tester.tap(cont);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SnackBar, 'Add at least one business to continue.'),
          findsOneWidget,
        );
        expect(container.read(onboardingControllerProvider).currentStep, 2);
        await expireSnack();

        // 2) Save Business with an incomplete draft (only a name).
        final save = find.text('Save Business');
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(4)); // name, email, contact, address
        await tester.enterText(fields.at(0), 'Hydrawa Clinic');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SnackBar, 'Please fill in all business fields.'),
          findsOneWidget,
        );
        await expireSnack();

        // 3) Every field filled, but the email is malformed.
        await tester.enterText(fields.at(1), 'clinic@nowhere');
        await tester.enterText(fields.at(2), '5557654321');
        await tester.enterText(fields.at(3), '456 Clinic Ave');
        final dropdown = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('1-3 Years').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SnackBar, 'Enter a valid business email.'),
          findsOneWidget,
        );
        expect(container.read(onboardingControllerProvider).businesses, isEmpty);
        await expireSnack();

        // Sanity: a valid email saves the business.
        await tester.enterText(fields.at(1), 'clinic@example.com');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          container.read(onboardingControllerProvider).businesses,
          hasLength(1),
        );
        expect(remote.createCalls, isEmpty);
      },
    );
  });
}
