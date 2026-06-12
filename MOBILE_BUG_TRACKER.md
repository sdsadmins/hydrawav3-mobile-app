# Hydrawav3 Mobile App — Bug & Feature Tracker

> Source: SharePoint app-update notes (5/21 → 6/8 2026), filtered to **mobile app only** (iPhone / Android / tablet / APK). Status verified against the current Flutter codebase.
> Last updated: **2026-06-10**

**Legend:** ✅ Fixed · 🔧 Fixed today · ❌ Not fixed · ⚠️ Unclear / needs device testing

---

## 1. Summary

| Status | Count |
|--------|-------|
| ✅ Already fixed (in code) | 14 |
| 🔧 Fixed today (2026-06-10) | 10 |
| ❌ Not fixed | 5 |
| ⚠️ Unclear / needs device testing | 6 |

---

## 2. Bugs

### ✅ Already fixed in code (verified)

| ID | Bug | Evidence |
|----|-----|----------|
| B-01 | Recovery/protocol **stack stuck on first protocol**, doesn't advance (BLE & WiFi) | `session/services/protocol_plus_controller.dart` (START_PROTOCOL listener advances each protocol) |
| B-02 | **Live session not terminating** after device stops/completes | `session/services/session_engine.dart` (auto-completes + sends STOP at elapsed ≥ total) |
| B-03 | **Session timings missing / read 00:00** for new protocols | `protocols/domain/protocol_model.dart` (`totalDurationSeconds` computed for every protocol) |
| B-04 | **Can't stop protocol on WiFi** after leaving/returning to live page | `session/presentation/screens/session_screen.dart` (Stop button always rendered for WiFi) |
| B-05 | **Tablet sleep stops timer** (publish blocker) | `session_screen.dart` WakelockPlus + `session_engine.dart` wall-clock reconcile |
| B-06 | **Bluetooth not always connecting** | `ble/services/ble_connector.dart` (6s timeout + retry w/ backoff, 5 attempts) |
| B-07 | **2 devices same name / different MAC** in BT list | `ble/services/ble_scanner.dart` (dedup keyed on MAC, UI shows both) |
| B-08 | **Intermittent connect/disconnect loop w/ 2nd device** | `ble/services/auto_connect_manager.dart` (concurrent-connect cap + scan-stop-before-connect) |
| B-09 | **Shaky scrolling (Android)** scan list | `ble/services/ble_scanner.dart` (stable merged list, stale filtering) |
| B-10 | **Scan button should continuously scan** every few sec | `ble/services/ble_scanner.dart` (auto-restart loop) |
| B-11 | **iPhone BLE registration** (name change + WiFi password) | `devices/.../device_register_screen.dart` (iOS scan-then-connect path) |
| B-12 | **"hydra-" prefix naming inconsistency** | `device_register_screen.dart` (prefix normalized at register/edit) |
| B-13 | **Session history shows link string not device name** | `history/presentation/screens/history_list_screen.dart` (resolves `deviceName`) |
| B-14 | **iPhone disconnects when moved a few feet** | `ble/services/ble_connector.dart` (auto-reconnect; reactive only, no RSSI) |

### 🔧 Fixed today — 2026-06-10

| ID | Bug | What changed | File(s) |
|----|-----|--------------|---------|
| B-15 | **"In Use" → "Use"** toggle label | Label now reads `Use` | `devices/.../device_list_screen.dart` |
| B-16 | **Privacy policy URL** wrong domain | `hydrawav3.app/privacy` → `https://www.hydrawav3.com/privacy` (+ terms) | `core/constants/app_constants.dart` |
| B-17 | **Default protocol** should be Deep-Tension Recovery Stack | Corrected default to full name `Deep-Tension Recovery Stack`; protocol title now wraps to 2 lines so the full name shows (was truncated at 1 line) | `devices/.../device_list_screen.dart` |
| B-18 | **Autoconnect should default ON** | Default value now `true` — auto-connect is on unless the user explicitly turns it off (still persisted across restarts) | `core/storage/preferences.dart` |
| B-19 | **MAC ID + name fields auto-populate** with previous entry on "+ new device" | `_clearScanSelection()` now also clears the MAC + name controllers | `devices/.../device_register_screen.dart` |
| B-20 | **Can't remove last active device → infinite spinner** instead of empty state | Lists render from last-known value; show "No registered devices" on reload; spinner only on first load | `devices/.../device_list_screen.dart` |
| B-21 | **No recently-used protocols list** | New persisted `recentProtocolIdsProvider` + "Recently used" chip strip at top of protocol picker bottom sheet; selecting a protocol records it (max 8, persists across launches) | `protocols/.../protocol_provider.dart`, `devices/.../device_list_screen.dart`, `core/storage/preferences.dart` |
| B-27 | **Session history not newest-first** | Sort the history list by `createdAt` descending in the app (backend returns it unsorted; no backend change). | `history/presentation/screens/history_list_screen.dart` |
| B-28 | **Home "Protocols" header text too small** | Replaced the small grey `SectionHeader` with a larger icon + 16px bold header matching "Active Devices" (shared `SectionHeader` left untouched). | `protocols/presentation/screens/protocol_list_screen.dart` |
| B-29 | **Foreground (background-session) notification basic & out of sync** | Rebuilt as a **Spotify-style media notification** (framework `Notification.MediaStyle`, no new deps): single card with **protocol name** title, **colored dot indicators** per device (🟢 running / 🟡 paused / 🔴 stopped / ⚪ idle), a **"X of Y devices running"** summary, live count-up **timer**, app icon, **tap-to-open**, and a **Pause/Resume + Stop** control row. Added an `ACTION_UPDATE` sync path so it tracks **all in-app cases** — Protocol Plus switches, per-device completion, pause/resume, overall status. Kotlin compiles (`compileDebugKotlin` ✓). | `android/.../BleForegroundService.kt`, `android/.../MainActivity.kt`, `session/services/background_session_runtime.dart`, `session/services/session_engine.dart` |

### ❌ Not fixed

| ID | Bug | Why / Notes |
|----|-----|-------------|
| B-22 | **Two-way communication** (BT & WiFi) not working | App only sends commands; no live device→app state/pad telemetry. Largest remaining piece. |
| B-23 | **"Select Protocol" time ≠ live session time** | Picker shows base duration; session adds `startDelay`, never reconciled. |
| B-24 | **90-second break between stacked protocols** + highlight next | Switch is immediate (STOP→800ms→PLAY); no break UI/countdown. Likely also resolves the "ghost 00:00 session on stack start" report. |
| B-25 | **Session history tied to account, not device** | **Backend confirmed:** `GET /intake/all` runs `intakeModel.find()` with **no scoping** — returns every account's intakes. Mobile sessions are **guest** (`clientId` is null), so scoping must use **`createdBy` (the logged-in user id)**, which the intake schema always stores. Fix = filter `getAllIntakes()` by `req.user.id`. Deferred per decision (sort-only for now). |
| B-26 | **Education / pad-placement link** that opens a webpage | Doesn't exist yet (only AI-chat hint text). Backend endpoint `aiPadPlacement` exists but no UI link. |

### ⚠️ Unclear / needs device testing

| ID | Bug | Note |
|----|-----|------|
| U-01 | Device restart → BT disconnect → ghost 00:00 session on stack start | Tied to missing break logic (B-24); not directly handled. |
| U-02 | General timing not correct for any session | Code does wall-clock reconcile, but device↔app sync over WiFi latency / mid-sleep switches unverified without hardware. |
| U-03 | iPhone can't connect WiFi on its own hotspot | No hotspot detection in code — likely an iOS OS limitation, not a code bug. |
| U-04 | iPhone 17 BT issue (connects before pushing) | No iOS-specific play-command ordering found. |
| U-05 | Device not detected during WiFi registration scan | No code defect found — likely permissions / environment / firmware. |
| U-06 | Colors exactly match web app | Palette exists in `theme_constants.dart`; can't verify pixel match without comparing to web theme. |

---

## 3. Feature / Change Requests (mobile)

| ID | Request | Status |
|----|---------|--------|
| F-01 | Default protocol = Deep Tension Recovery | ✅ Done (B-17) |
| F-02 | "In Use" → "Use" toggle | ✅ Done (B-15) |
| F-03 | Keep Autoconnect on once toggled (persist) | ✅ Done (B-18) |
| F-04 | Recently-used protocols list | ✅ Done (B-21) |
| F-05 | Continuous scan for Hydrawav3 devices every few seconds | ✅ Done (B-10) |
| F-06 | Session goals/tagging for stacked protocols | ❌ Pending |
| F-07 | 2-way communication enabled | ❌ Pending (B-22) |
| F-08 | Colors exactly the same as web app | ⚠️ Needs comparison (U-06) |
| F-09 | Session history on account not device | ❌ Pending — backend-dependent (B-25) |
| F-10 | Education link for pad placements (opens webpage) | ❌ Pending (B-26) |
| F-11 | Show 90-second break between protocols + highlight next | ❌ Pending (B-24) |
| F-12 | Larger header text in Home "PROTOCOLS" section | ✅ Done (B-28) |

---

## 4. Roadmap (from notes)

### V2 of mobile app — before EOM
- Mobile new account creation
- 2-way communication (B-22)
- Pause / resume on stacked protocols
- Diagnostic values
- Mobile app ↔ web app sync
- Advanced settings on stacks
- Home lease
- Warranty addition
- Token display
- Session goal tagging for stacks (F-06)
- WiFi online feature

### V3 of mobile app — mid-to-late July
- Chatbot
- 3D model with pads
- At-home exercises
- Social link share
- User geotagging

---

## 5. Next recommended work
1. **B-22 / F-07 — Two-way communication** (largest gap; unblocks live telemetry, diagnostics, app↔web sync).
2. **B-24 / F-11 — 90-second break between stacked protocols** (also likely clears the ghost-session report U-01).
3. **B-23 — Reconcile "Select Protocol" duration with live session duration**.
4. **B-25 / F-09 — Account-scoped history** — pending backend confirmation.
