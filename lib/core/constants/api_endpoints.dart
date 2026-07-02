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

  // Client auth (Node Nest — at-home client login, distinct from the Django
  // practitioner `/auth/login`). Relative (no leading slash) so it appends to
  // the Node base URL path. Login body `{clientName, password}`; rejected with
  // "Lease is not active" unless the client's lease is active.
  static const String clientAuthLogin = 'auth/login';
  static const String clientAuthRefresh = 'auth/refresh';

  // Clients
  static const String clients = '/clients';
  static String clientsByOrg(String orgId) => '/clients/$orgId';
  static String clientDetails(String orgId) => '/clients/details/$orgId';
  static String clientById(String clientId) =>
      '/clients/clientDetails/$clientId';
  // `PATCH /clients/:clientId` — lease activation / deactivation / password
  // reset (web parity: `updateClient` in `actions/action.ts`).
  static String clientPatch(String clientId) => '/clients/$clientId';

  // AI reports (Node Nest — parity with web `actions/action.ts` + `hydrawav3-api.ts`).
  // Two-phase queued generation: POST analyze -> poll status -> POST ai-reports.
  // NOTE: distinct from `aiAnalyze`/`aiChat` below (those are the old Next.js routes).
  static const String aiReportAnalyze = 'ai/analyze';
  static String aiReportAnalyzeStatus(String id) => 'ai/analyze/$id';
  static const String aiReports = 'ai-reports';
  static const String aiReportsRecent = 'ai-reports/recent';
  static const String aiReportsAll = 'ai-reports/all';
  static String aiReportById(String id) => 'ai-reports/$id';

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

  // ROM body parts (for the Range of Motion intake step; parity with web getRoms).
  static const String roms = 'roms';

  // Placement Cards
  static const String placementCards = '/placement-cards';

  // Payments
  static const String publishableKey = '/payments/publishable-key';
  static String createCheckoutSession(String orgId) =>
      '/payments/create-checkout-session/$orgId';
  static String currentPlan(String orgId) => '/payments/current-plan/$orgId';
  // Provision the org's free plan + starter tokens (web parity: `freeplanCheckout`
  // on org selection). Without this a newly created org has no plan, so the token
  // balance badge stays empty for first-time / newly onboarded accounts.
  static String freePlan(String orgId) => '/payments/free-plan/$orgId';
  static const String paymentUser = '/payments/user';
  static const String products = '/products';

  // Device Control (Wi-Fi)
  static const String sendTreatment = '/send_treatment2.php';

  // MQTT
  static const String mqttPublish = '/mqtt/publish';

  /// Node Nest: `POST /hydrawav/v1/sessions/start`
  /// Creates a backend session (status RUNNING) and broadcasts `SESSION_STARTED`
  /// over the `/sessions` socket. Mobile normal runs call this (parity with web)
  /// so they appear in the org-wide live-session feed.
  static const String sessionStart = 'sessions/start';

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
