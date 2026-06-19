class ApiEndpoints {
  ApiEndpoints._();

//   Auth
  static const String profileMe = "/profile/me";
  static const String changePassword = "/profile/me/password";
  static const String forgotPassword = "/profile/me/forget-password";

  // Account management (admin user account resource).
  // PUT with `deleted: true` soft-deletes the account.
  static String userAccountById(String id) => '/admin/user/accounts/$id';

// /changed
// static const String login = '/auth/login';
  static const String login = '/auth/login';
  // Base URLs
  static const String djangoBaseUrl = 'http://54.241.236.53:8080/api/v1';
  //static const String nodeBaseUrl = 'http://3.111.197.247:5000/hydrawav/v1/';
  static const String nodeBaseUrl =
      'https://api.hydrawav3.studio/api/hydrawav/v1/';

  ///static const String nodeBaseUrl = 'https://6141-2401-4900-939b-c510-21c9-de96-7c0b-8093.ngrok-free.app/hydrawav/v1/';
  static const String deviceControlUrl = 'https://hydrawav3.app';

  // Auth

  static const String refreshToken = '/auth/refreshToken';
  static const String baseUrl = "http://54.241.236.53:8080";

  // Practitioner onboarding (native "Create account" flow, parity with web).
  // The submit needs an admin token from this public proxy (the user isn't
  // logged in yet), then a multipart POST to the onboarding endpoint.
  static const String proxyCreateUserUrl =
      'https://hydrawav3.app/proxy_create_user.php';
  static const String practitionerOnboarding = '/practitioners/onboarding';
  // Profile
//   static const String profileMe = '/profile/me';
//   static const String changePassword = '/profile/me/password';

  // Organizations
  static const String organizations = '/admin/organizations';
  static String organizationById(String id) => '/admin/organizations/$id';

  // Sensors / Devices
  static const String sensors = '/admin/sensors';
  static String sensorById(String id) => '/admin/sensors/$id';
  static String sensorsByOrg(String orgId) =>
      '/admin/sensors/organisation/$orgId';

  // Clients
  static const String clients = '/clients';
  static String clientsByOrg(String orgId) => '/clients/$orgId';
  static String clientDetails(String orgId) => '/clients/details/$orgId';
  static String clientById(String clientId) =>
      '/clients/clientDetails/$clientId';

  // Session music ("Atmosphere") tracks
  static const String musics = '/musics';

  // Protocols
  static const String protocols = '/protocols';
  static const String protocolsWithGoalTag = '/protocols/with-goal-tag';
  static String protocolById(String id) => '/protocols/$id';
  static const String goalTags = '/goal-tag';

  // Intake / Sessions
  static const String intake = '/intake';
  static const String intakeAll = '/intake/all';
  static String intakeByClient(String clientId) => '/intake/client/$clientId';
  static String intakeDashboard(String orgId) => '/intake/dashboard/$orgId';

  // Body Parts & Muscles
  static const String bodyParts = '/body-part';
  static const String muscles = '/muscle';

  // Placement Cards
  static const String placementCards = '/placement-cards';

  // Payments
  static const String publishableKey = '/payments/publishable-key';
  static String createCheckoutSession(String orgId) =>
      '/payments/create-checkout-session/$orgId';
  static String currentPlan(String orgId) => '/payments/current-plan/$orgId';
  static const String paymentUser = '/payments/user';
  static const String products = '/products';

  // Device Control (Wi-Fi)
  static const String sendTreatment = '/send_treatment2.php';

  // MQTT
  static const String mqttPublish = '/mqtt/publish';

  /// Node Nest: `GET /hydrawav/v1/sessions/active/:organizationId`
  /// Returns active sessions with per-device `moon` / `sun` pad strings.
  static String sessionsActive(String organizationId) =>
      'sessions/active/$organizationId';

  /// Node Nest: `POST /hydrawav/v1/sessions/:sessionId/pause/:organizationId`
  static String sessionPause(String sessionId, String organizationId) =>
      'sessions/$sessionId/pause/$organizationId';

  /// Node Nest: `POST /hydrawav/v1/sessions/:sessionId/resume/:organizationId`
  static String sessionResume(String sessionId, String organizationId) =>
      'sessions/$sessionId/resume/$organizationId';

  /// Node Nest: `POST /hydrawav/v1/sessions/:sessionId/stop/:organizationId`
  static String sessionStop(String sessionId, String organizationId) =>
      'sessions/$sessionId/stop/$organizationId';

  /// Node Nest: `GET /hydrawav/v1/protocol-plus` (list) and `/protocol-plus/:id`
  /// (detail). Returns Protocol Plus templates (ordered `protocolIds`).
  static const String protocolPlus = 'protocol-plus';

  /// Node Nest: `POST /hydrawav/v1/protocol-plus/start`
  /// Starts a Protocol Plus sequence (server starts protocol[0] + schedules
  /// the remaining protocol switches, emitted over the `/sessions` socket).
  static const String protocolPlusStart = 'protocol-plus/start';

  // AI (Next.js routes - uses Django base URL with different path)
  static const String aiAnalyze = '/api/analyze';
  static const String aiChat = '/api/chat';
  static const String aiPadPlacement = '/api/pad-placement';
}
