import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/auth/domain/onboarding_models.dart';

/// Sign-up bodies follow the onboarding API: address required, date of birth
/// optional (left out when not given).
void main() {
  const base = PractitionerForm(
    firstName: 'Jane',
    lastName: 'Doe',
    username: 'janedoe',
    password: 'secret123',
    email: 'jane@example.com',
    phone: '5551234567',
    title: 'Physio',
    accountType: '2',
    address: '123 Main St',
    city: 'Flagstaff',
    state: 'AZ',
    zip: '86001',
    country: 'USA',
  );

  test('no date of birth: left out of create and account update', () {
    final create = buildCreatePractitionerJson(base);
    final update = buildAccountUpdateJson(base, 7);
    expect(create.containsKey('dateOfBirth'), isFalse);
    expect(update.containsKey('dateOfBirth'), isFalse);
    expect(create['address'], '123 Main St');
    expect(update['address'], '123 Main St');
  });

  test('date of birth given: sent on both', () {
    final f = base.copyWith(dateOfBirth: '1990-04-12');
    expect(buildCreatePractitionerJson(f)['dateOfBirth'], '1990-04-12');
    expect(buildAccountUpdateJson(f, 7)['dateOfBirth'], '1990-04-12');
  });
}
