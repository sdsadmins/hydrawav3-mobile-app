class AppConstants {
  AppConstants._();

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration aiAnalysisTimeout = Duration(minutes: 5);
  static const Duration aiChatTimeout = Duration(minutes: 2);

  // Token
  static const Duration tokenRefreshBuffer = Duration(minutes: 5);
  static const Duration accessTokenExpiry = Duration(days: 1);
  static const Duration refreshTokenExpiry = Duration(days: 7);

  // Pagination
  static const int defaultPageSize = 50;
  static const int defaultPage = 1;

  // Protocol cache
  static const Duration protocolCacheStaleness = Duration(hours: 1);

  // Presets
  static const int maxPresets = 3;

  // Discomfort scale
  static const int discomfortMin = 0;
  static const int discomfortMax = 10;

  // Subscription tiers
  static const String tierFree = 'free';
  static const String tierPaid = 'practitioner';

  // App info
  static const String appName = 'Hydrawav3';
  static const String supportEmail = 'support@hydrawav3.com';
  static const String privacyPolicyUrl = 'https://hydrawav3.app/privacy';
  static const String termsUrl = 'https://hydrawav3.app/terms';

  // Version and Release Notes
  static const String appVersion = '1.0.2';
  static const String buildNumber = '3';
  static const String releaseNotes = '''
Version 1.0.2
- Session notifications now show while running in the background
- Improved background session reliability
- Bug fixes and stability improvements
Version 1.0.1
- Bug fixes and performance improvements
- Enhanced user interface
- Improved device connectivity
Version 1.0.0
- Initial release
  ''';
}
