# Hydrawav3 Mobile App — Bug & Feature Tracker

> Source: SharePoint app-update notes (5/21 → 6/8 2026), filtered to **mobile app only** (iPhone / Android / tablet / APK).
> Last updated: **2026-06-17**

**How this works:**
- A line that is **~~crossed out~~** is **fixed** — full detail (date, root cause, files) lives in [FIXES_BY_DATE.md](FIXES_BY_DATE.md).
- A plain line is **still open**.
- ⚠️ = needs on-device confirmation.
- Forward-looking feature releases are tracked in [RELEASE_PIPELINE.md](RELEASE_PIPELINE.md).

---

## Summary

| Status | Count |
|--------|-------|
| ✅ Fixed (crossed out below) | 36 |
| ❌ Open | 3 |
| ⚠️ Needs device testing | 3 |

---

## Bugs

### Open
- **B-22** — Two-way communication (BT & WiFi): app only sends commands; no live device→app state/pad telemetry. *Largest remaining piece.* → [Release 1](RELEASE_PIPELINE.md)
- **B-25** — Session history tied to account, not device: backend `GET /intake/all` is unscoped; mobile `SessionHistoryItem.fromJson` doesn't yet parse `createdBy`. Backend-dependent. → [Release 1](RELEASE_PIPELINE.md)
- **B-26** — Education / pad-placement link to a webpage: doesn't exist yet (only AI-chat hint text; backend `aiPadPlacement` exists, no UI link).

### Needs device testing (⚠️)
- **U-01** — Device restart → BT disconnect → ghost 00:00 session on stack start. Break logic now implemented (B-24); should be addressed — needs device confirmation.
- **U-03** — iPhone can't connect WiFi on its own hotspot. No hotspot detection in code; likely an iOS limitation, not a code bug.
- **U-04** — iPhone 17 BT issue (connects before pushing). No iOS-specific play-command ordering found; gated on the nRF Connect diagnostic.

### Fixed
- ~~**B-01** — Stack stuck on first protocol, doesn't advance (BLE & WiFi)~~
- ~~**B-02** — Live session not terminating after device stops/completes~~
- ~~**B-03** — Session timings missing / read 00:00 for new protocols~~
- ~~**B-04** — Can't stop protocol on WiFi after leaving/returning to live page~~
- ~~**B-05** — Tablet sleep stops timer~~
- ~~**B-06** — Bluetooth not always connecting~~
- ~~**B-07** — 2 devices same name / different MAC in BT list~~
- ~~**B-08** — Intermittent connect/disconnect loop w/ 2nd device~~
- ~~**B-09** — Shaky scrolling (Android) scan list~~
- ~~**B-10** — Scan button should continuously scan every few sec~~
- ~~**B-11** — iPhone BLE registration (name change + WiFi password)~~
- ~~**B-12** — "hydra-" prefix naming inconsistency~~
- ~~**B-13** — Session history shows link string not device name~~
- ~~**B-14** — iPhone disconnects when moved a few feet~~
- ~~**B-15** — "In Use" → "Use" toggle label~~
- ~~**B-16** — Privacy policy URL wrong domain~~
- ~~**B-17** — Default protocol should be Deep-Tension Recovery Stack~~
- ~~**B-18** — Autoconnect should default ON~~
- ~~**B-19** — MAC ID + name fields auto-populate with previous entry~~
- ~~**B-20** — Can't remove last active device → infinite spinner~~
- ~~**B-21** — No recently-used protocols list~~
- ~~**B-23** — "Select Protocol" time ≠ live session time~~
- ~~**B-24** — 90-second break between stacked protocols + highlight next (incl. Stop usable during break)~~
- ~~**B-27** — Session history not newest-first~~
- ~~**B-28** — Home "Protocols" header text too small~~
- ~~**B-29** — Foreground notification basic & out of sync~~
- ~~**B-30** — Register New Hardware scan inconsistent / flickers~~
- ~~**B-31** — Protocol durations wrong in "All" list; Protocol Plus shows 00:00~~
- ~~**B-32** — Show the delay/break time between stacked protocols (value)~~
- ~~**B-33** — Device Fleet / WiFi list spins forever for some accounts~~
- ~~**B-34** — Logout not working (CircularDependencyError)~~
- ~~**B-35** — Devices page showed the previous user's devices~~
- ~~**B-36** — Device fetch threw a red error on 401/403/404/204~~
- ~~**B-37** — No pull-to-refresh on Device Registration & Protocol List~~
- ~~**U-02** — General timing not correct for any session~~ (confirmed working)
- ~~**U-05** — Device not detected during WiFi registration scan~~ (confirmed working)
- ~~**U-06** — Colors exactly match web app~~

---

## Feature / Change Requests

### Open
- **F-06** — Session goals/tagging for stacked protocols. → [Release 2](RELEASE_PIPELINE.md)
- **F-07** — 2-way communication enabled (= B-22). → [Release 1](RELEASE_PIPELINE.md)
- **F-09** — Session history on account not device (= B-25). → [Release 1](RELEASE_PIPELINE.md)
- **F-10** — Education link for pad placements (= B-26). → [Release 2](RELEASE_PIPELINE.md)

### Fixed
- ~~**F-01** — Default protocol = Deep Tension Recovery~~ (B-17)
- ~~**F-02** — "In Use" → "Use" toggle~~ (B-15)
- ~~**F-03** — Keep Autoconnect on once toggled (persist)~~ (B-18)
- ~~**F-04** — Recently-used protocols list~~ (B-21)
- ~~**F-05** — Continuous scan every few seconds~~ (B-10)
- ~~**F-08** — Colors exactly the same as web app~~ (U-06)
- ~~**F-11** — Show 90-second break between protocols + highlight next~~ (B-24)
- ~~**F-12** — Larger header text in Home "PROTOCOLS" section~~ (B-28)
