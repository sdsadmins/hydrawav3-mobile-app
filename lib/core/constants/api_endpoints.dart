class ApiEndpoints {
  ApiEndpoints._();

//   Auth
  static const String profileMe = "user/profile/me";
  // Profile served by the Node backend. No leading slash so it appends to the
  // Node base URL path (which ends in `.../hydrawav/v1/`) → `.../user/profile/me`;
  // a leading slash would drop the base path and hit the host root instead.
  static const String profileMeNode = 'user/profile/me';
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
  // Dev-only ngrok tunnel (URL rotates on restart + free-tier rate limits → intermittent ServerException). Do not ship.
  //static const String nodeBaseUrl =     'https://hung-homeless-president-beats.trycloudflare.com/hydrawav/v1/';

  static const String nodeBaseUrl =
      'https://api.hydrawav3.studio/api/hydrawav/v1/';

  // static const String nodeBaseUrl = 'http://192.168.31.92:5000/hydrawav/v1/';
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
  // Subscription purchase happens on the web app only — Stripe isn't
  // embedded in the mobile app (App Store/Play Store reject in-app purchase
  // flows that route around their own IAP), so "Upgrade Now" opens this in
  // an in-app browser instead (see subscription_screen.dart).
  static const String practitionerSubscriptionUrl =
      'https://hydrawav3.app/practitioner/subscription';
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

  // Treatment / Session plan (Node) — pad-placement plan for a body part
  // (web parity: getTreatmentPlanByBodyPart). Returns sun/moon electrode
  // placements + recommended protocol per area. Relative (no leading slash).
  static String treatmentPlanByBodyPart(String bodyPartName) =>
      'treatment-plans/body-part/${Uri.encodeComponent(bodyPartName)}';

  // RAG pad placement (Node Nest) — the recovery guided-assessment flow posts
  // an AssessmentPayload `{ state, learningCases, persist }` and gets the
  // Sun/Moon pad-placement plan back (ref: hydrawav3-ai `getRagPadPlacement`).
  static const String padPlacementSession = 'ai-padplacement/placement-session';

  // Performance protocols (Node) — the pad_protocols corpus. Two ways in to the
  // same pad-set payload: the catalogue (discipline → role → chain → chain) and
  // the query/chat pair. Relative (no leading slash) so they append to the Node
  // base URL path.
  //
  // The first three are metadata — cheap, cacheable, no safety gate. Only
  // `perfChain` returns pads, and it runs the same `safety.guard()` as
  // retrieval: on a block it answers a refusal envelope with `chain: null`, so
  // callers must branch on that instead of assuming pads.
  //
  // `sessionId` rides on EVERY call: a tier-1 safety lock is per session, so
  // without it an emergency named in turn 1 doesn't stick in turn 2. The user is
  // resolved server-side from the token and is deliberately not accepted from
  // the body.
  static const String perfDisciplines = 'performance-protocols/disciplines';

  static String perfRoles(String discipline, {String? sessionId}) =>
      _perfUri('performance-protocols/roles', {
        'discipline': discipline,
        'sessionId': sessionId,
      });

  static String perfChains(
    String discipline,
    String role, {
    String? subtype,
    String? sessionId,
  }) =>
      _perfUri('performance-protocols/chains', {
        'discipline': discipline,
        'role': role,
        'subtype': subtype,
        'sessionId': sessionId,
      });

  /// ★ The pad set. Gated — see the note above.
  static String perfChain(
    String discipline,
    String role,
    String chainId, {
    String? subtype,
    required String sessionId,
  }) =>
      _perfUri('performance-protocols/chain', {
        'discipline': discipline,
        'role': role,
        'chainId': chainId,
        'subtype': subtype,
        'sessionId': sessionId,
      });

  static const String perfQuery = 'performance-query/query';
  static const String perfChat = 'performance-chat/message';

  /// The RECOVERY conversational front door — the recovery v2 engine's own
  /// chatbot, not the performance one. Same envelope idea (reply + slots +
  /// options + render), different corpus and different slots (`region`, `side`,
  /// `goal`), so a typed message must go to whichever surface the conversation
  /// is on: performance → [perfChat], recovery → this.
  ///
  /// `slots` is the multi-turn memory and `redFlags` carries the screen answers
  /// (the recovery equivalent of `screenAnswers`); the engine's universal safety
  /// gate runs before anything else, so a reply can come back as a refusal.
  static const String recoveryChat = 'recovery-chat/message';

  /// The RECOVERY ENGINE, guided (non-conversational) front door — the chip flow's
  /// counterpart to [recoveryChat] and the recovery equivalent of
  /// [perfDisciplines] → [perfChain]. Web parity: `RecoveryEngineFlow.jsx` +
  /// `engine/recoveryGeneration.js`.
  ///
  /// ASK [recoveryCutover] FIRST, AND THEN USE ONE GENERATION'S WHOLE SET.
  ///
  /// There are two live generations. A generation's screen, its catalogue and its
  /// resolve are ONE set and must never be composed from two: region keys and
  /// pathway values are not the same across them, so asking v3's questions and
  /// resolving against v2 sends values v2 cannot match — which is how a pathway
  /// holding 156 points reports zero. The web shipped exactly that bug.
  ///
  /// There is also NO SENSIBLE DEFAULT. "Still loading", "the request failed" and
  /// "it is v2" are different facts, and a dispatch that treats the first two as
  /// v2 is a guess that is right until the day it is not. An unknown generation
  /// means wait, not fall back.
  static const String recoveryCutover = 'recovery-engine-v3/cutover';

  // ── v2: the older corpus, still serving wherever v3 has no live points ─────

  static const String recoveryV2Screen = 'recovery-engine/screen';

  /// Regions grouped per pathway, derived from the v2 corpus. A different shape
  /// from [recoveryIntake] — per-region `points`, `hasMovementTest`,
  /// `movementTests` as plain strings, `referrals` — and NOT a fallback for it.
  static const String recoveryV2Catalog = 'recovery-engine/catalog';

  /// Runs the v2 engine unconditionally. Its DTO is strict and narrower than
  /// v3's, so `movementTest`, `aspect` and `referral_side` are 400s here.
  static const String recoveryV2Resolve = 'recovery-engine/resolve';

  // ── v3.1 ───────────────────────────────────────────────────────────────────

  /// The AUTHORED CATALOGUE, and the reason the chip flow can't be hardcoded: the
  /// regions the live corpus can actually answer for, each with its CANONICAL id
  /// (`low-back`, not "Lower Back"), its own movement tests, its referral menu
  /// and the aspects it permits. The engine matches on those ids, so a body-map
  /// label sent as `region` resolves to nothing.
  ///
  /// Read `pathways[].regions` once a goal is chosen, NOT the whole-corpus
  /// `regions`: the selector hard-filters on `goal_pathway`, so the corpus-wide
  /// list offers combinations no point can answer.
  static const String recoveryIntake = 'recovery-engine-v3/intake';

  /// ★ The pad set. Gated twice — the universal safety gate runs before the
  /// engine and the engine's own pre-gate runs inside it — so a 200 can still be
  /// a refer-out with `sets: []`.
  ///
  /// This one goes through the cutover service SERVER-side, so it is correct even
  /// in the instant after a rollback. [recoveryV2Resolve] has no such property.
  static const String recoveryResolve = 'recovery-engine-v3/resolve';

  /// The universal red-flag screen (questions + the authored client disclaimer).
  static const String recoveryScreen = 'recovery-engine-v3/screen';

  /// Builds `path?a=b&c=d`, dropping null/blank values and encoding the rest.
  static String _perfUri(String path, Map<String, String?> params) {
    final q = params.entries
        .where((e) => (e.value ?? '').trim().isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}')
        .join('&');
    return q.isEmpty ? path : '$path?$q';
  }

  // Sports (Node) — the org's sport mappings (sport + positions) for the Add
  // Player form. `GET /sports/:organisationId` → { organizationId, data:
  // [{ mappingId, sport, positions, isActive }] }. Relative (no leading slash).
  static String orgSports(String orgId) => 'sports/$orgId';

  // Practitioner onboarding (Node). The web moved these three off Django onto
  // the Node backend under `user/*` (ref: hydrawav3-ai `actions/action.ts` —
  // getAccountTypes / createPractitionerOnboarding / createOrganization /
  // updateUserAccount). Relative (no leading slash) so they append to the Node
  // base URL path. The certificate upload is the one call still on Django.
  static const String onboardingAccountTypes = 'user/account-types';
  static const String onboardingCreate = 'user/onboarding';
  static const String onboardingOrganizations = 'user/organizations';
  static String onboardingAccountById(String id) => 'user/accounts/$id';

  /// The onboarding Business step picks its sports from the performance
  /// catalogue ([perfDisciplines]) — the same list the protocols surface reads —
  /// and sends the chosen DISPLAY NAMES as `sport`. The old `GET sports`
  /// catalogue (Mongo `_id`s, token-gated) is no longer served.

  // Notifications (Node) — the AI-report processor writes one when a report
  // finishes generating (web parity: actions/notification.ts). List per user +
  // mark-read. Relative (no leading slash) so they append to the Node base URL.
  static String notificationsByUser(String userId) => 'notifications/$userId';
  static String notificationRead(String id) => 'notifications/read/$id';

  // Warranty (Node) — per-device warranty status for the org. Relative (no
  // leading slash) so it appends to the Node base URL.
  static String warrantyByOrg(String orgId) => 'warranty/$orgId';

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

  // Live analysis system prompt (Node Nest). The web fetches this and sends its
  // `content` as `customSystemPrompt` with every `ai/analyze` call; the mobile
  // must do the same, otherwise the backend falls back to an older built-in
  // prompt that can emit non-numeric fields (e.g. age "not provided") the
  // AiReport schema rejects. Relative (no leading slash).
  static const String promptAnalysisLive = 'admin/prompts/analysis/live';

  // Session music ("Atmosphere") tracks
  static const String musics = '/musics';

  // Protocols
  static const String protocols = '/protocols';
  static const String protocolsWithGoalTag = '/protocols/with-goal-tag';
  static String protocolById(String id) => '/protocols/$id';
  static const String goalTags = '/goal-tag';

  // Intake / Sessions
  static const String intake = '/intake';
  static String intakeAll(String organizationId) =>
      '/intake/allByorg/$organizationId';
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

  // Token cost config — the backend's per-second session token rate
  // (session.service.ts: `perSecondCost`), used to show "this will cost ~N
  // tokens" on a protocol before starting it.
  static const String tokenConfig = '/token-config';

  /// Every SUBSCRIPTION product. `GET /products` deliberately drops the one
  /// named "Free" (`product.service.ts:150`) because it isn't purchasable — but
  /// that is the product a free org's plan points at, so its `aiCredit` (the
  /// period's token grant) is only reachable here.
  static const String subscriptionProducts = '/products/subscriptions';

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

  /// Node Nest: `POST /hydrawav/v1/protocol-plus/:sessionId/pause/:organizationId`
  /// Pauses the run AND holds the server's queued protocol switches. Without the
  /// hold those switches keep counting down through the pause and fire together
  /// on resume. Body optionally targets one device (`macAddress` / `deviceName`
  /// / `slotId`); an empty body pauses the whole session.
  static String protocolPlusPause(String sessionId, String organizationId) =>
      'protocol-plus/$sessionId/pause/$organizationId';

  /// Node Nest: `POST /hydrawav/v1/protocol-plus/:sessionId/resume/:organizationId`
  /// Resumes the run; every held switch is re-queued with the wait it had left.
  static String protocolPlusResume(String sessionId, String organizationId) =>
      'protocol-plus/$sessionId/resume/$organizationId';

  /// Node Nest: `POST /hydrawav/v1/protocol-plus/:sessionId/restart`
  /// Restarts the CURRENTLY RUNNING sub-protocol for this device from its own
  /// beginning (fresh timer/cycles) — the server re-serves the same
  /// protocol/index it already has active. Does NOT end the session or touch
  /// token/session lifecycle; unlike pause/resume this route is NOT nested
  /// under `:organizationId`.
  static String protocolPlusRestart(String sessionId) =>
      'protocol-plus/$sessionId/restart';

  /// Node Nest: `GET /hydrawav/v1/session/:sessionId/status/:organizationId`
  /// Per-device session snapshot, including `protocolIndex` (Protocol Plus
  /// sub-sequence position) — authoritative even if this client's socket
  /// missed a `START_PROTOCOL` broadcast (that event is a fire-and-forget
  /// socket.emit with no delivery guarantee; the backend still advances its
  /// own state either way). Used to recover after a missed switch, detected
  /// locally via BLE telemetry (`timeLeftSeconds` reaching 0) rather than
  /// waiting indefinitely for a socket event that may never arrive.
  static String sessionStatus(String sessionId, String organizationId) =>
      'session/$sessionId/status/$organizationId';

  // AI (Next.js routes - uses Django base URL with different path)
  static const String aiAnalyze = '/api/analyze';
  static const String aiChat = '/api/chat';
  static const String aiPadPlacement = '/api/pad-placement';
}
