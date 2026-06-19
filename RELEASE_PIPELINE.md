# Hydrawav3 Mobile App — Feature Update Pipeline

> Forward-looking feature roadmap by release. Bug fixes are tracked separately in
> [MOBILE_BUG_TRACKER.md](MOBILE_BUG_TRACKER.md); shipped work is logged in [FIXES_BY_DATE.md](FIXES_BY_DATE.md).
> Last updated: **2026-06-18**

**Status legend:** ☐ Not started · ◐ In progress · ✅ Done · 🔗 maps to an existing bug/feature ID

---

## Release 1 — 24th June

| # | Feature | Detail | Maps to | Status |
|---|---------|--------|---------|--------|
| 1 | **2-way communication** | App responds to the device, especially while the device is running a session; surface diagnostic values. | 🔗 B-22 / F-07 | ☐ |
| 2 | **Advanced settings on stack** | Advanced settings configurable per stacked protocol. | — | ☐ |
| 3 | **Pause / resume (stack)** | Ability to pause and resume during a stack run. | — | ☐ |
| 4 | **Warranty registration** | Register via MAC id (manual) or BLE with a timestamp; expires after 1 year; ability to extend the expiration date. | — | ☐ |
| 5 | **Music sync** | Play looping "Atmosphere" music while the session runs, with a track picker + mute — **at parity with the web** (one shared track per live session covering all its devices; plays while running, silent when muted, stops on leaving). Foreground-only by design (pauses on background/lock, resumes on return); no new store permissions. | — | ◐ **Android verified playing (2026-06-17)**; iOS not yet tested (check silent-switch + call interruption on a device) |
| 6 | **Account usage** | Session history scoped to the **account**, not the device. | 🔗 B-25 / F-09 | ☐ |
| 7 | **Token usage** | Show the number of usage tokens in the user's account. | — | ☐ |
| 8 | **App logo** | Add the logo to the top of the app. | — | ✅ (2026-06-18) — theme-aware logo on the Home header (white in dark, black in light) |
| 9 | **"Locked" → greyed "Advanced"** | Rename "Locked" to a greyed-out "Advanced"; tapping it shows an info bubble prompting an account upgrade. | — | ✅ (2026-06-17) |
| 10 | **Recently Used restyle** | "Recently Used" should look like the protocols list instead of session goals. | 🔗 (extends F-04 / B-21) | ✅ (2026-06-17) |
| 11 | **Constant scan** | Scan button continuously scans for Hydrawav3 devices every few seconds. | 🔗 B-10 / F-05 | ✅ |
| 12 | **Education / pad-placement link** | Link to a webpage explaining pad placements. | 🔗 B-26 / F-10 | ☐ |
| 13 | **Live session terminates in sync with device** | When a protocol (e.g. Upper Body Metabolism) completes and the device stops, the mobile live session should auto-end in sync instead of continuing to run. | 🔗 B-02 | ✅ |
| 14 | **Mobile new account creation** | Create a new account from the mobile app. Built natively: a themed 4-step practitioner onboarding (Practitioner → Credentials → Business → Review) matching the web (labels, hints, asterisks, file uploads for cert docs + business logo), replacing the old web redirect. Submits to `/practitioners/onboarding` via the proxy admin token; no auto-login (admin-pending application). Store-safe (`file_picker` adds no Android permissions / ships an iOS privacy manifest). | — | ◐ Built (2026-06-18); needs device QA + one real submit |
| 15 | **Web ↔ mobile live-session sync** | Web app should show live sessions started by mobile on a device, and vice versa. | 🔗 (depends on B-22) | ☐ |

---

## Release 2 — 1st July

| # | Feature | Detail | Status |
|---|---------|--------|--------|
| 1 | **Feature-rich protocol** | Show token cost, protocol description, number of cycles explained, and a detailed graphic/diagram of the stacked protocols. | ☐ |
| 2 | **Bluetooth registration (iPhone)** | Register the device on the account over Bluetooth. | ☐ |
| 3 | **AI engine (RAG)** | Work with Manav to integrate database vectorization. Give the HW3 team/admin a link to delete the folder tree. Powered by a proprietary prompt that lets you choose which sub-folder to query for efficient results. | ☐ |
| 4 | **Chatbot + 3D pad placements** | Interactive frontend that proactively asks questions, queries the RAG model, and displays pad placements on a 3D interactive model. | ☐ |
| 5 | **Home lease** | Unlock the device for home use with a timestamp option and IP tracking; 32-hex code generation stored in the cloud; ability to charge the practitioner via future Stripe integration; generate client-specific user id + password. | ☐ |
| 6 | **Post-session questions** | Log the response for each protocol and report the average recovery value (%) on the app dashboard. | ☐ |
| 7 | **Choose client** | Choose a client for the session. | ☐ |
| 8 | **App dashboard** | Avg recovery rate %, hours the device was used, token availability, chat with HW3 team, start a session, read about the protocol library, purchase device (shop), sources. | ☐ |

---

## Release 3 — 8th July

| # | Feature | Detail | Status |
|---|---------|--------|--------|
| 1 | **Stripe integration** | Purchase packages, recharge tokens, and top up for home lease. | ☐ |
| 2 | **AI engine (Claude)** | Provide a guided session plan with suggestions for 3D KC-a / KC-b with biomechanical expressions. | ☐ |

---

## Release 4 — 15th July

| # | Feature | Detail | Status |
|---|---------|--------|--------|
| 1 | **Breathing** | Breathing rate (inhalation / exhalation / pause), graphical representation of the confidence score, pre- and post-session tracking. | ☐ |
| 2 | **Parasympathetic score** | Graphical outcome of the score with timestamps during and after the session, and how it compares against global users. | ☐ |

---

## Release 5 — 29th July

| # | Feature | Detail | Status |
|---|---------|--------|--------|
| 1 | **Text-to-speech (ElevenLabs)** | Use ElevenLabs API tokens to request a set of prompts that collect range-of-motion and discomfort questions, to derive 3D positioning / pad placements from KC and the affected body parts. | ☐ |
| 2 | **Protocol-specific binaural beats** | Option to integrate music with specific protocols. | ☐ |
| 3 | **At-home exercise** | At-home exercise feature. | ☐ |
| 4 | **Social link share** | Share via a social link. | ☐ |
| 5 | **User geotagging** | User geotagging. | ☐ |
| 6 | **WiFi online feature** | Pending — ask Shiva. | ☐ |
