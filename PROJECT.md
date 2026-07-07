# Hydrawav3 Pro — Mobile App

Flutter app for controlling the **Hydrawav3 Pro** physical-therapy hardware. Practitioners register devices, run therapy protocols (single and stacked "Protocol Plus" sequences) over Bluetooth LE and WiFi, manage clients, and generate AI session reports. Built to match the **`Hydrawav3-ai` web practitioner portal feature-for-feature** — the web app is the source of truth for parity.

- **Package:** `hydrawav3` · **App ID:** `com.hydrawav3.hydrawav3` · **Version:** `1.0.3+3`
- **SDK:** Dart `^3.6.0`, Flutter `>=3.27.0`
- **Platforms:** Android + iOS (macOS/web scaffolding present but not primary)

---

## Tech Stack

| Concern | Choice |
|---|---|
| State management | Riverpod (`flutter_riverpod`, `riverpod_annotation`) |
| Navigation | `go_router` |
| Networking | `dio` + custom auth interceptor; `socket_io_client` / SSE for live feeds |
| BLE | `flutter_blue_plus` |
| Local DB | `drift` (+ `sqlite3_flutter_libs`, `drift_flutter`) |
| Key-value / secure storage | `shared_preferences`, `flutter_secure_storage` |
| Models / codegen | `freezed`, `json_serializable`, `build_runner` |
| Payments | `flutter_stripe` |
| 3D viewer | `flutter_inappwebview` hosting an offline three.js kinetic-chain viewer in `assets/3d` over a bundled localhost server |
| Audio | `just_audio` + `audio_session` (session "Atmosphere" looping music) |
| AI report PDF | `pdf` (pure-Dart), shared via `share_plus` |

---

## Architecture

Feature-first, layered inside each feature (`data / domain / presentation`, plus `services` where needed). Riverpod providers wire everything; the backend is the source of truth for sessions.

```
lib/
├── main.dart          # bootstrap: orientation lock, file logging, ProviderScope,
│                      #   auth check, background session runtime, BLE auto-connect,
│                      #   org-scoped live-session + token-balance feeds
├── app.dart           # HydrawavApp: MaterialApp.router, light/dark theme, router
├── core/
│   ├── bootstrap/     # app startup helpers
│   ├── constants/     # api_endpoints, app_constants, ble_constants, legal_content, theme_constants
│   ├── error/         # error types
│   ├── network/       # dio_client, auth_interceptor, connectivity_service,
│   │                  #   mqtt_publish_client, sse_client
│   ├── router/        # app_router.dart, route_names.dart
│   ├── services/
│   ├── storage/       # preferences (SharedPreferences provider), secure storage
│   ├── theme/         # app_theme + theme_mode_provider
│   └── utils/         # logger (TEMP-LOG-EXPORT file logging for field debugging)
└── features/
    ├── auth/            advanced_settings/   splash/         settings/
    ├── ble/             devices/             presets/        protocols/
    ├── session/         session_plan/        client_session/ clients/
    ├── intake/          ai_hub/  ai_chat/  ai_report/         history/
    ├── musics/          notifications/       payments/        sharing/
```

### Feature Modules

Each module follows `data / domain / presentation (+ services)`. Screens and key services below are the actual files under `lib/features/`.

| Module | What it does | Key screens / services |
|---|---|---|
| **auth** | Practitioner + client login, signup, forgot/reset password, org selection, practitioner onboarding (certification docs, business logo). Unified practitioner→client login fallback. | `login_screen`, `signup_screen`, `forgot_password_screen`, `onboarding_screen`, `select_organization_page`, `client_auth_provider`, `onboarding_remote_source` |
| **ble** | BLE scan / connect / reconnect, treatment & command writing, app-wide auto-connect (defaults ON). Handles firmware quirks (MAC ±1, name-match on iOS). | `ble_scanner`, `ble_connector`, `auto_connect_manager`, `ble_treatment_writer`, `ble_command_service`, `device_list_tile` |
| **devices** | Device fleet: register new hardware (BLE + WiFi provisioning), device detail, WiFi device list, Locate/Report/Edit-Name. | `device_register_screen`, `device_detail_screen`, `wifi_devices_provider`, `device_repository` |
| **protocols** | Browse therapy protocols, protocol detail, and **Protocol Plus** stacked sequences. Recently-used list; Deep-Tension Recovery default. | `protocol_list_screen`, `protocol_detail_screen`, `protocol_plus_model`, `protocol_plus_detail_provider` |
| **session** | Live therapy session runtime: active/live session feeds, background session runtime, WiFi remote control, sessions socket, busy-device tracking. Backend is source of truth. | `background_session_runtime`, `active_sessions_provider`, `live_sessions_provider`, `wifi_remote_control`, `sessions_socket` |
| **session_plan** | Session setup / planning before a run (protocol + client + goals selection). | `data / domain / presentation` |
| **client_session** | At-home client-mode session screen (leased device, restricted controls). | `client_session_screen`, `client_session_controller` |
| **clients** | Client CRUD + selection, **device lease** handshake (`setLeaseID`/`clearLeaseID`), client lease screen. | `clients_list_screen`, `client_lease_screen`, `lease_controller`, `new_client_sheet`, `client_selection_section` |
| **intake** | Guided assessment / intake: body map, ROM body parts, session-type cards, option pickers. Feeds AI reports. | `body_map`, `session_type_cards`, `guided_assessment_provider`, `rom_body_parts_provider`, `intake_models` |
| **ai_hub / ai_chat / ai_report** | AI hub landing, streaming AI chat (SSE), and queued AI session reports with PDF export. | `chat_screen`, `chat_sse_source`, `ai_reports_list_screen`, `ai_report` data/domain |
| **history** | Session history (newest-first), session detail. | `session_detail_screen`, `session_history_model`, `history_repository` |
| **musics** | Session "Atmosphere" looping background music (foreground-only playback). | `session_music_controller`, `music_provider`, `music_remote_source` |
| **presets** | Save/manage protocol presets. | `preset_management_screen`, `preset_repository` |
| **payments** | Stripe subscription + token balance (org-scoped live badge). | `token_balance_provider`, `token_balance_badge`, `plan_model`, `payment_repository` |
| **advanced_settings** | Device fine-tuning: light, temperature, vibration controls. | `light_control`, `temperature_slider`, `vibration_control` |
| **settings** | Profile edit, change password, subscription screen. | `settings_screen`, `profile_edit_screen`, `change_password_screen`, `subscription_screen` |
| **notifications** | In-app notification feed. | `notification_provider`, `notification_remote_source` |
| **sharing** | Social sharing of reports/sessions. | `social_share_service` |
| **splash** | Launch/bootstrap gating. | `app_bootstrap_provider` |

### Key runtime wiring (from `main.dart`)
- **Auth**: `authStateProvider.checkAuthStatus()` on launch; org-scoped feeds start/stop as auth + selected org change.
- **Background session runtime**: keeps a running session alive across screens; removes the session from `activeSessionsProvider` when it stops.
- **BLE auto-connect**: `autoConnectManagerProvider` runs app-wide for connect/reconnect (auto-connect defaults ON).
- **Live feeds**: `liveSessionsProvider` + `tokenBalanceProvider` are org-scoped and mirror the web app (every run creates a backend session rendered from this feed).

---

## Backend

Two backends behind the app:
- **Django** — `http://54.241.236.53:8080/api/v1` (auth, profile, admin/organizations, admin/sensors, protocols, clients, AI reports, musics). Bearer token; `401` on `/admin/sensors` is role-based, not an auth failure. Auth interceptor uses a one-retry refresh guard (fixed an infinite refresh loop).
- **Node** — `https://api.hydrawav3.studio/api/hydrawav/v1/` (device control / session orchestration).
- **Device control / MQTT** — commands published to topic `HydraWav3Pro/config` (e.g. Locate `{mac,beeping}`, Report `{mac,selfCheck}`, play `{mac,playCmd}`). Same command shape as the web app.

Backend is shared with the web portal — see the web app for command/flow parity.

---

## Routing

`go_router`, route table in [lib/core/router/route_names.dart](lib/core/router/route_names.dart):

`/` splash · `/login` `/signup` `/forgot-password` `/reset-password` · `/onboarding` · `/protocols` (+ `/protocols/:id`, `/protocol-plus`) · `/devices` (+ `/devices/register`, `/devices/:id`) · `/session`, `/session-setup` · `/history` (+ `/history/:id`) · `/ai-hub`, `/chat`, `/ai-report`, `/ai-reports`, `/ai-report-clients` · `/kinetic-chain-3d` · `/client-lease`, `/client-home` (at-home client mode) · `/presets` · `/settings` (+ `/settings/profile`, `/settings/password`, `/settings/subscription`)

---

## Notable Domain Behavior

- **BLE / device quirks** — firmware drops BLE during WiFi provisioning; no clear-WiFi command; BLE MAC can be ±1 off the label; iOS matches by device name (not MAC). Auto-connect is app-wide.
- **Protocol Plus (stacked sequences)** — countdown timer and completion semantics have device/app divergences handled mobile-side (local continuous timer for Plus; app-side STOP + final-protocol completion). 90-second break between stacked protocols with next-highlight.
- **Client / Guest mode + Device Lease** — web-parity practitioner→client login fallback, `setLeaseID`/`clearLeaseID` BLE handshake, at-home client login.
- **AI reports** — queued generation, PDF export, guided assessment intake.

---

## Build & Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json / drift codegen
flutter run                                                 # or: flutter run --release
flutter build apk        # Android
flutter build ipa        # iOS
```

Release process and store submission are documented in [RELEASE_PIPELINE.md](RELEASE_PIPELINE.md).

---

## Repo Docs

| File | Purpose |
|---|---|
| [MOBILE_BUG_TRACKER.md](MOBILE_BUG_TRACKER.md) | Live bug/feature tracker (open vs. fixed, needs-device-testing) |
| [FIXES_BY_DATE.md](FIXES_BY_DATE.md) | Dated fix log with root causes + files |
| [RELEASE_PIPELINE.md](RELEASE_PIPELINE.md) | Forward-looking releases + submission process |
| [docs/APP_STORE_REJECTION_CLIENT_BRIEF.md](docs/APP_STORE_REJECTION_CLIENT_BRIEF.md) | iOS App Store rejection history + remediation |

## Monorepo Context

Sibling projects under `d:\SumeruDigital\Hydrawav3\`:
- **`Hydrawav3-ai/`** — Next.js/React practitioner portal — **parity reference** (mirror its BLE/WiFi/session flows).
- **`Hydrawav3-Server/`** — backend.
