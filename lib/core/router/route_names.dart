class RouteNames {
  RouteNames._();

  // Splash / bootstrap
  static const String splash = 'splash';

  // Auth
  static const String login = 'login';
  static const String signup = 'signup';
  static const String forgotPassword = 'forgot-password';
  static const String resetPassword = 'reset-password';
  static const String onboarding = 'onboarding';
  static const selectOrganization = 'selectOrganization';
  // Main tabs
  static const String protocols = 'protocols';
  static const String devices = 'devices';
  static const String history = 'history';
  static const String settings = 'settings';

  // Protocol sub-routes
  static const String protocolDetail = 'protocol-detail';
  static const String protocolPlus = 'protocol-plus';

  // Session
  static const String session = 'session';
  static const String sessionSetup = 'session-setup';

  // Device sub-routes
  static const String deviceRegister = 'device-register';
  static const String deviceDetail = 'device-detail';

  // History sub-routes
  static const String sessionDetail = 'session-detail';

  // Settings sub-routes
  static const String profileEdit = 'profile-edit';
  static const String changePassword = 'change-password';
  static const String subscription = 'subscription';

  // Paid features
  static const String presets = 'presets';
  static const String chat = 'chat';
}

class RoutePaths {
  RoutePaths._();

  // Splash / bootstrap (initial route; decides login vs home from stored token)
  static const String splash = '/';

  // Auth
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String onboarding = '/onboarding';

  // Main tabs
  static const String protocols = '/protocols';
  static const String devices = '/devices';
  static const String history = '/history';
  static const String settings = '/settings';

  // Sub-routes
  static const String protocolDetail = '/protocols/:id';
  static const String protocolPlus = '/protocol-plus';
  static const String session = '/session';
  static const String sessionSetup = '/session-setup';
  static const String deviceRegister = '/devices/register';
  static const String deviceDetail = '/devices/:id';
  static const String sessionDetail = '/history/:id';
  static const String profileEdit = '/settings/profile';
  static const String changePassword = '/settings/password';
  static const String subscription = '/settings/subscription';
  static const String presets = '/presets';
  static const String chat = '/chat';
}
