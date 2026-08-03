// Models for the native practitioner onboarding ("Create account") flow.
// Mirrors the web's 4-step form AND its exact 4-call submit sequence:
//   1) POST  {node}/practitioners/onboarding   — create account (no auth) → userId + token
//   2) POST  {primary}/admin/organizations     — create org (raw token)   → orgId
//   3) POST  {primary-api}/certificates/upload — per cert with a file (raw token, optional)
//   4) PUT   {primary}/admin/user/accounts/{userId} — link org via addOrganisations (raw token)
// See onboarding_remote_source.dart for the calls and onboarding_provider.submit().

/// One option of the Account Type select on step 1, from
/// `GET {node}user/account-types`. [id] is what gets sent as `account_type_id`;
/// [name] is what the user sees.
class AccountTypeOption {
  final String id;
  final String name;

  const AccountTypeOption({required this.id, required this.name});

  /// Falls back to the id so an option with no name is still selectable.
  String get label => name.isEmpty ? id : name;
}

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
  /// Selected account-type id (an [AccountTypeOption.id]) — sent as
  /// `account_type_id` on the final account-update call.
  final String accountType;
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
    this.accountType = '',
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
    String? accountType,
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
      accountType: accountType ?? this.accountType,
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

/// A sport the org can offer, from `GET {node}performance-protocols/disciplines`
/// — the performance catalogue IS the sports list now.
///
/// [name] is the human label (`display_name`) and is what gets sent in `sport`
/// on org create: the backend assigns sports BY NAME. [discipline] is the
/// catalogue's retrieval key (e.g. `ice_hockey`), kept so a saved sport can be
/// matched back to its protocols later.
class SportOption {
  final String discipline;
  final String name;

  const SportOption({required this.discipline, required this.name});
}

/// Step 3 — a single business (required, ≥1, repeatable).
class OnboardingBusiness {
  final String name;
  final String businessAge; // one of businessAgeOptions
  final String email;
  final String contactNumber;
  final String address;

  /// Sports offered, as [SportOption.name]s — university accounts only. Sent as
  /// `sport` on org create, and omitted entirely when empty.
  final List<String> sports;

  const OnboardingBusiness({
    required this.name,
    this.businessAge = '',
    this.email = '',
    this.contactNumber = '',
    this.address = '',
    this.sports = const [],
  });
}

/// Allowed values for the business-age dropdown (parity with web).
const List<String> businessAgeOptions = <String>[
  '0-1 Years',
  '1-3 Years',
  '3-5 Years',
  '5+ Years',
];

/// `account_type_id` in the shape the backend validates for: an INTEGER.
/// `user/account-types` returns ids as strings ("1"), so parse them. A
/// non-numeric id is passed through unchanged, so the server reports a real
/// error instead of us silently sending something wrong.
Object _accountTypeId(String raw) => int.tryParse(raw.trim()) ?? raw.trim();

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
    // Required by the Node DTO as an integer. The web reference omits it here
    // (it only sends it on the account-update call), which makes its create
    // request fail validation — so this deliberately diverges from the web.
    'account_type_id': _accountTypeId(form.accountType),
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
    // Sport NAMES, e.g. ["Ice Hockey"] — the backend assigns the org's sports
    // by name (CreateOrganizationDto.sport). Omitted entirely when nothing is
    // selected, since the DTO rejects unknown/empty extras.
    if (primaryBusiness.sports.isNotEmpty) 'sport': primaryBusiness.sports,
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
    'account_type_id': _accountTypeId(form.accountType),
    'isEnabled': true,
    'isAccountNonLocked': true,
    'expirationDateAccount': null,
    'addOrganisations': [orgId],
    'removeOrganisations': const <Object>[],
  };
}
