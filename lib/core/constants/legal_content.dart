import 'app_constants.dart';

class InfoSheetSection {
  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;

  const InfoSheetSection({
    required this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class LegalContent {
  LegalContent._();

  static const String effectiveDate = 'May 26, 2026';
  static const String lastUpdated = 'May 26, 2026';
  static const String supportUrl = 'https://www.hydrawav3.com/help-center';

  static const List<InfoSheetSection> privacyPolicySections = [
    InfoSheetSection(
      heading: 'Overview',
      paragraphs: [
        '${AppConstants.appName} provides the ${AppConstants.appName} mobile application ("App"). This Privacy Policy explains how we collect, use, store, and share information when you use the App.',
        'Effective date: $effectiveDate',
        'Last updated: $lastUpdated',
      ],
    ),
    InfoSheetSection(
      heading: '1. Information We Collect',
      paragraphs: [
        'We may collect the following categories of information:',
      ],
      bullets: [
        'Account and profile information such as your name, username, email address, phone number, organization, country, state, date of birth, and other profile details you choose to provide.',
        'Device and connection information such as device identifiers, device names, Bluetooth connection information, MAC addresses, pairing details, and device status information.',
        'Session and treatment information such as selected protocols, device assignments, session duration, session history, discomfort ratings, notes, presets, intake-related records, and similar usage data needed to provide app functionality.',
        'Permissions-related information for Bluetooth and nearby devices to discover, connect to, and communicate with compatible therapy devices. Location permission may be requested on certain devices or operating systems solely to support Bluetooth scanning and device connectivity. We do not use location for advertising or location tracking.',
      ],
    ),
    InfoSheetSection(
      heading: '2. How We Use Information',
      bullets: [
        'Authenticate users and manage accounts.',
        'Connect to, register, and control compatible devices.',
        'Save session progress, history, presets, and settings.',
        'Improve app reliability, security, and support.',
      ],
    ),
    InfoSheetSection(
      heading: '3. How We Share Information',
      bullets: [
        'Service providers that host or support our backend systems.',
        'Platform services when you intentionally use sharing features.',
        'We do not sell your personal information.',
      ],
    ),
    InfoSheetSection(
      heading: '4. Local Storage and Security',
      paragraphs: [
        'Some information is stored locally on your device, including session history, paired devices, preferences, and saved settings. Authentication tokens and certain sensitive settings may be stored using secure device storage where available.',
        'We use reasonable administrative, technical, and organizational safeguards to protect information.',
      ],
    ),
    InfoSheetSection(
      heading: '5. Data Retention',
      paragraphs: [
        'We retain information for as long as needed to provide the App, maintain security, comply with legal obligations, resolve disputes, and enforce our agreements.',
        'Information stored locally on your device may remain until you delete it, log out, uninstall the App, or clear app data. You may contact us to request deletion of account-related data, subject to legal or operational retention requirements.',
      ],
    ),
    InfoSheetSection(
      heading: '6. Your Choices',
      bullets: [
        'Update certain account or profile information.',
        'Disable optional permissions through your device settings.',
        'Contact us to request access, correction, or deletion of your account data.',
      ],
    ),
    InfoSheetSection(
      heading: '7. Children\'s Privacy',
      paragraphs: [
        'The App is not intended for children under 13 years of age, or the minimum age required by applicable law in your region. We do not knowingly collect personal information from children in violation of applicable law.',
      ],
    ),
    InfoSheetSection(
      heading: '8. Changes to This Privacy Policy',
      paragraphs: [
        'We may update this Privacy Policy from time to time. The updated version may also be posted at ${AppConstants.privacyPolicyUrl}.',
      ],
    ),
    InfoSheetSection(
      heading: '9. Contact Us',
      bullets: [
        AppConstants.appName,
        AppConstants.supportEmail,
        supportUrl,
      ],
    ),
  ];

  static const List<InfoSheetSection> termsAndConditionsSections = [
    InfoSheetSection(
      heading: 'Overview',
      paragraphs: [
        'These Terms & Conditions govern your use of the ${AppConstants.appName} mobile application and related services.',
        'Effective date: $effectiveDate',
        'Last updated: $lastUpdated',
      ],
    ),
    InfoSheetSection(
      heading: '1. Acceptance of Terms',
      paragraphs: [
        'By creating an account, accessing the App, or using a compatible device with the App, you agree to these Terms & Conditions.',
      ],
    ),
    InfoSheetSection(
      heading: '2. Eligibility and Account Responsibility',
      bullets: [
        'You are responsible for maintaining the confidentiality of your login credentials.',
        'You must provide accurate information and keep your profile details reasonably up to date.',
        'You are responsible for activity that occurs through your account unless caused by our error.',
      ],
    ),
    InfoSheetSection(
      heading: '3. Use of the App',
      bullets: [
        'Use the App only with compatible equipment and as permitted by applicable laws, clinical guidance, and device instructions.',
        'Do not misuse the App, interfere with service operations, attempt unauthorized access, or use the App to harm other users or connected systems.',
        'The App may require Bluetooth, internet access, and supported device permissions for certain features to function properly.',
      ],
    ),
    InfoSheetSection(
      heading: '4. Health and Safety',
      paragraphs: [
        'The App supports therapy-related workflows and device connectivity, but it is not an emergency service.',
        'You should follow clinician guidance, device labeling, and applicable safety instructions when using any connected therapy device.',
      ],
    ),
    InfoSheetSection(
      heading: '5. Privacy',
      paragraphs: [
        'Your use of the App is also subject to our Privacy Policy, which describes how information is collected, used, stored, and shared.',
      ],
    ),
    InfoSheetSection(
      heading: '6. Intellectual Property',
      paragraphs: [
        'The App, its content, branding, software, and related materials remain the property of ${AppConstants.appName} or its licensors unless otherwise stated.',
      ],
    ),
    InfoSheetSection(
      heading: '7. Availability and Changes',
      paragraphs: [
        'We may update, suspend, or change features from time to time. We do not guarantee uninterrupted availability of every feature on every device or network.',
      ],
    ),
    InfoSheetSection(
      heading: '8. Limitation of Liability',
      paragraphs: [
        'To the extent permitted by law, ${AppConstants.appName} is not liable for indirect, incidental, special, consequential, or punitive damages arising from use of the App.',
      ],
    ),
    InfoSheetSection(
      heading: '9. Contact',
      bullets: [
        AppConstants.supportEmail,
        supportUrl,
      ],
    ),
  ];

  static const List<InfoSheetSection> privacyAndSecuritySections = [
    InfoSheetSection(
      heading: 'Your Data',
      bullets: [
        'Profile details, session history, saved settings, and paired device information may be stored locally on your device and in supported backend systems.',
        'Authentication tokens and sensitive session details should be handled using secure device storage where available.',
      ],
    ),
    InfoSheetSection(
      heading: 'Permissions',
      bullets: [
        'Bluetooth and nearby-device access are used to discover and communicate with compatible therapy devices.',
        'Some Android devices may request location permission only because the operating system requires it for Bluetooth scanning.',
        'You can review and revoke permissions in your device settings at any time.',
      ],
    ),
    InfoSheetSection(
      heading: 'Account Security Tips',
      bullets: [
        'Use a strong password that you do not reuse on other services.',
        'Change your password immediately if you suspect unauthorized access.',
        'Log out when using a shared or borrowed device.',
      ],
    ),
    InfoSheetSection(
      heading: 'Need Help?',
      paragraphs: [
        'If you notice a security concern or need help with your account, contact support using the details below.',
      ],
      bullets: [
        AppConstants.supportEmail,
        supportUrl,
      ],
    ),
  ];
}
