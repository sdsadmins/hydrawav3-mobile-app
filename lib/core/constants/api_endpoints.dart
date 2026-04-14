class ApiEndpoints {
  ApiEndpoints._();

//   Auth
static const String profileMe = "/api/v1/profile/me";
static const String changePassword = "/api/v1/profile/me/password";
static const String forgotPassword = "/api/v1/profile/me/forget-password";

// /changed
static const String login = '/auth/login';
  // Base URLs
  static const String djangoBaseUrl = 'http://54.241.236.53:8080';
  static const String nodeBaseUrl = 'http://127.0.0.1:5000/hydrawav/v1';
  static const String deviceControlUrl = 'https://hydrawav3.app';

  // Auth

  static const String refreshToken = '/auth/refreshToken';
static const String baseUrl = "http://54.241.236.53:8080";
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

  // Protocols
  static const String protocols = '/protocols';
  static String protocolById(String id) => '/protocols/$id';

  // Intake / Sessions
  static const String intake = '/intake';
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
  static String currentPlan(String orgId) =>
      '/payments/current-plan/$orgId';
  static const String paymentUser = '/payments/user';
  static const String products = '/products';

  // Device Control (Wi-Fi)
  static const String sendTreatment = '/send_treatment2.php';

  // MQTT
  static const String mqttPublish = '/mqtt/publish';

  // AI (Next.js routes - uses Django base URL with different path)
  static const String aiAnalyze = '/api/analyze';
  static const String aiChat = '/api/chat';
  static const String aiPadPlacement = '/api/pad-placement';
}
