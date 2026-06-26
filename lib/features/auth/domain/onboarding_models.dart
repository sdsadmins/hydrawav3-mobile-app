// Models for the native practitioner onboarding ("Create account") flow.
// Mirrors the web's 4-step form AND its exact 4-call submit sequence:
//   1) POST  {node}/practitioners/onboarding   — create account (no auth) → userId + token
//   2) POST  {primary}/admin/organizations     — create org (raw token)   → orgId
//   3) POST  {primary-api}/certificates/upload — per cert with a file (raw token, optional)
//   4) PUT   {primary}/admin/user/accounts/{userId} — link org via addOrganisations (raw token)
// See onboarding_remote_source.dart for the calls and onboarding_provider.submit().

/// Step 1 — practitioner personal details.
///
/// NOTE: [username] and [password] ARE sent on the create call (web parity — the
/// onboarding endpoint provisions the account + returns the token used to
/// authorize the org-create and account-link calls).
class PractitionerForm {
  final String firstName;
  final String lastName;
  final String username;
  final String password;
  final String email;
  final String phone;
  final String title; // practitionerType
  final String address;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String dateOfBirth; // yyyy-MM-dd

  const PractitionerForm({
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.password = '',
    this.email = '',
    this.phone = '',
    this.title = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.country = '',
    this.dateOfBirth = '',
  });

  String get fullName => '$firstName $lastName'.trim();

  PractitionerForm copyWith({
    String? firstName,
    String? lastName,
    String? username,
    String? password,
    String? email,
    String? phone,
    String? title,
    String? address,
    String? city,
    String? state,
    String? zip,
    String? country,
    String? dateOfBirth,
  }) {
    return PractitionerForm(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      password: password ?? this.password,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      title: title ?? this.title,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      country: country ?? this.country,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    );
  }
}

/// Step 2 — a single license / certification (optional, repeatable).
class OnboardingCertification {
  final String name;
  final String issuingOrganization;
  final String issueDate; // yyyy-MM-dd
  final String expirationDate; // yyyy-MM-dd
  final String? documentPath; // picked file (pdf/png/jpg)
  final String? documentName;

  const OnboardingCertification({
    required this.name,
    this.issuingOrganization = '',
    this.issueDate = '',
    this.expirationDate = '',
    this.documentPath,
    this.documentName,
  });
}

/// Step 3 — a single business (required, ≥1, repeatable).
class OnboardingBusiness {
  final String name;
  final String businessAge; // one of businessAgeOptions
  final String email;
  final String contactNumber;
  final String address;

  const OnboardingBusiness({
    required this.name,
    this.businessAge = '',
    this.email = '',
    this.contactNumber = '',
    this.address = '',
  });
}

/// Allowed values for the business-age dropdown (parity with web).
const List<String> businessAgeOptions = <String>[
  '0-1 Years',
  '1-3 Years',
  '3-5 Years',
  '5+ Years',
];

/// Call 1 — body for `POST {node}/practitioners/onboarding` (create account).
/// Exact web shape (web `createPractitioner`): username + password + dateOfBirth
/// are sent; `licenses` is empty at create (cert files are uploaded separately in
/// call 3). No `groupIds` / `clinic*` fields — the org is created in call 2.
Map<String, dynamic> buildCreatePractitionerJson(PractitionerForm form) {
  return {
    'fullName': form.fullName,
    'email': form.email,
    'password': form.password,
    'practitionerType': form.title,
    'address': form.address,
    'city': form.city,
    'country': form.country,
    'userName': form.username,
    'phone': form.phone,
    'state': form.state,
    'zip': form.zip,
    'dateOfBirth': form.dateOfBirth,
    'licenses': const <Map<String, dynamic>>[],
    'euaAccepted': true,
  };
}

/// Call 2 — body for `POST {primary}/admin/organizations` (create the business).
/// Web `createOrganization` shape: `{ name, mail, address, age, phone }`.
Map<String, dynamic> buildOrganizationJson(OnboardingBusiness primaryBusiness) {
  return {
    'name': primaryBusiness.name,
    'mail': primaryBusiness.email,
    'address': primaryBusiness.address,
    'age': primaryBusiness.businessAge,
    'phone': primaryBusiness.contactNumber,
  };
}

/// Call 4 — body for `PUT {primary}/admin/user/accounts/{userId}` (link the org
/// to the practitioner). Web `updateUserAccount` shape; [orgId] goes into
/// `addOrganisations` so the new account is attached to its organization.
Map<String, dynamic> buildAccountUpdateJson(
  PractitionerForm form,
  Object orgId,
) {
  return {
    'firstName': form.firstName,
    'lastName': form.lastName,
    'userName': form.username,
    'mail': form.email,
    'phone': form.phone,
    'dateOfBirth': form.dateOfBirth,
    'gender': 'unknown',
    'nationality': 'unknown',
    'maritalStatus': 'unknown',
    'title': form.title,
    'address': form.address,
    'address2': 'unknown',
    'city': form.city,
    'state': form.state,
    'zip': form.zip,
    'country': form.country,
    'isEnabled': true,
    'isAccountNonLocked': true,
    'expirationDateAccount': null,
    'addOrganisations': [orgId],
    'removeOrganisations': const <Object>[],
  };
}
