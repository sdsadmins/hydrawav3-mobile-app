// Models for the native practitioner onboarding ("Create account") flow.
// Mirrors the web's 4-step form and its exact submit payload.

/// Step 1 — practitioner personal details.
///
/// NOTE: [username] and [password] are collected for parity with the web form
/// but are intentionally NOT sent in the submit payload — the onboarding
/// endpoint creates a practitioner *application* and does not provision login
/// credentials here. Do not "fix" this by adding them to [buildDataJson].
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

/// Build the exact `data` JSON object the onboarding endpoint expects. Uses the
/// first business as the primary clinic and reuses the practitioner's city /
/// country for the clinic (matches the web).
Map<String, dynamic> buildOnboardingDataJson({
  required PractitionerForm form,
  required OnboardingBusiness primaryBusiness,
  required List<OnboardingCertification> certifications,
}) {
  return {
    'fullName': form.fullName,
    'email': form.email,
    'practitionerType': form.title,
    'address': form.address,
    'city': form.city,
    'country': form.country,
    'phone': form.phone,
    'clinicName': primaryBusiness.name,
    'clinicAge': primaryBusiness.businessAge,
    'clinicAddress': primaryBusiness.address,
    'clinicCity': form.city,
    'clinicCountry': form.country,
    'businessPhone': primaryBusiness.contactNumber,
    'website': '',
    'groupIds': [278],
    'licenses': certifications
        .map((c) => {
              'licenseType': c.name,
              'licenseNumber': '',
              'expirationDate': c.expirationDate,
              'stateIssued': c.issuingOrganization,
            })
        .toList(),
    'euaAccepted': true,
  };
}
