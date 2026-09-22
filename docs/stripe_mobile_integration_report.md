# Stripe / Subscription Purchase Integration — Mobile App Report

**Scope:** what it takes to let a practitioner actually buy/upgrade a plan from inside the Flutter mobile app (Android + iOS), given what's already built.

---

## 1. Current state (verified in the codebase, not assumed)

| Piece | Status |
|---|---|
| Backend Stripe integration | ✅ Full — `Hydrawav3-Server/src/modules/payment/` (Stripe SDK v22, checkout sessions, products, subscriptions) |
| `flutter_stripe` package | Installed (`pubspec.yaml`, v11.2.0) but **not used anywhere** in the app |
| `PaymentRepository.createCheckoutSession()` | Exists, returns a **Stripe Checkout web URL** — **dead code, called from nowhere in the UI** |
| `subscription_screen.dart` | Shows plan/usage info only — **no purchase button anywhere, by deliberate design** |
| Android in-app billing (`com.android.vending.BILLING`) | Not present |
| iOS In-App Purchase capability/entitlement | Not present |
| `in_app_purchase` / StoreKit package | Not installed |

**The most important existing artifact is a comment already in the code**, `subscription_screen.dart:16-25`:

> "Information only, identically on both platforms — no Stripe SDK, no card fields, no native payment sheet, no 'Upgrade' button, and no purchase link/redirect of any kind anywhere in this file. Apple's Guideline 3.1.1 (In-App Purchase) treats ANY button, link, or call-to-action — even plain, non-tappable text — that points a purchase of in-app functionality anywhere other than Apple's own In-App Purchase as a rejection; Netflix and Spotify's iOS apps don't even mention where to sign up for exactly this reason. Rather than have iOS and Android diverge, this screen simply never offers a way to buy anything on either platform until real StoreKit (iOS) and a matching purchase flow (Android) are built."

This means: **someone already researched this and concluded Stripe Checkout (the web-redirect flow the backend already supports) cannot be shown on iOS at all.** That conclusion is correct per Apple's current App Review Guidelines, and it's the reason the app currently sells nothing on either platform — not an oversight, a guard rail.

---

## 2. Apple App Store — what's actually required (the hard constraint)

Apple's **Guideline 3.1.1 (In-App Purchase)** requires that any purchase of digital content or services consumed inside the app — subscriptions, credits/tokens, unlocking premium features — **must go through Apple's own In-App Purchase (StoreKit)**, not Stripe, not a web checkout link, not even a plain-text mention of "subscribe on our website."

**What this means concretely for this app:**

- The existing `createCheckoutSession()` → Stripe web checkout URL **can never be shown inside the iOS app**, in any form (in-app browser, external Safari redirect, a "Manage billing" link) if it's used to purchase something consumed in-app. Apple review will reject this categorically — it's the single most consistently enforced guideline in the App Store.
- The subscription plans / token packs this app sells (per `Product`/`SubscriptionPlan` models already in the code) are exactly the kind of "content or services used in the app" that trigger 3.1.1 — there's no exemption route (no "physical goods" carve-out applies here; tokens/session credits are digital).
- iOS must offer purchases **only** through Apple's In-App Purchase, using the `StoreKit` framework (or the `in_app_purchase` Flutter plugin, which wraps it). Apple takes its standard commission (15-30% depending on tier/program) on every transaction made this way — this is unavoidable if the app sells subscriptions on iOS at all.
- **Alternative that keeps Stripe on iOS**: don't sell anything purchasable *from inside the iOS app*. Plans/tokens are bought only via the web app or another channel, and the iOS app is **read-only** for billing (view current plan/usage, no buy button) — which is exactly what `subscription_screen.dart` does today. This is a legitimate, permanent strategy some apps use (the "reader app" pattern), not just a temporary stopgap — but it means iOS users can never upgrade from their phone.

**Apple's External Purchase Link Entitlement** (introduced 2024, US-only, under ongoing legal/regulatory changes) technically allows linking out to an external purchase flow under narrow conditions, but it's a special entitlement Apple grants case-by-case, has strict UI/disclosure requirements, and its availability outside the US is not guaranteed and has been in flux. **Do not build against this without first confirming current eligibility directly with Apple** — it is not a safe default assumption for a report like this.

---

## 3. Google Play — the actual requirement, less restrictive but not equivalent to "just use Stripe"

Google Play has its own, similar (though not identical) policy: **Google Play's Billing policy** requires apps distributed via the Play Store to use **Google Play Billing** for purchases of in-app digital content/subscriptions, with limited exceptions.

- Historically Google's policy was narrower than Apple's and had more real-world tolerance for external payment links (many apps got away with a Stripe/web checkout flow for years). That has tightened significantly — Google now enforces this closer to how Apple does, especially for subscription apps.
- As of recent policy updates, Google **does** allow some regions/app categories to offer an alternative billing system alongside or instead of Play Billing (the "User Choice Billing" program), but enrollment is selective, program-specific, and comes with its own compliance requirements (disclosure UI, reporting, a signed agreement with Google) — **not a default you get by just calling Stripe from Android code.**
- Practically: **treat Android the same way as iOS for this report** — assume Play Billing is required for any real subscription/token purchase shipped through the Play Store, unless you specifically pursue and get approved for User Choice Billing.

**Bottom line: this is not "iOS is restricted, Android is free to use Stripe."** Both stores require their own billing system for in-app digital purchases today. Stripe (the flow the backend already has) can only safely be used for purchases that happen **outside the app** — i.e., on the web, or if the mobile app never shows a "buy" UI at all (today's approach).

---

## 4. What changes for a real purchase flow — Android

If you decide to build native purchasing into the Android app:

1. **Add the `in_app_purchase` Flutter package** (wraps Google Play Billing Library) — not `flutter_stripe` for the purchase itself.
2. **`android/app/src/main/AndroidManifest.xml`** — add the `com.android.vending.BILLING` permission.
3. **Google Play Console setup**:
   - Create the subscription products / in-app products in Play Console, matching (or replacing) the backend's Stripe `Product` catalog conceptually — Play Console is the source of truth for price/availability on Android, not the Stripe dashboard.
   - Set up a **Real-time Developer Notifications (RTDN)** topic (Pub/Sub) so the backend gets notified of renewals/cancellations/refunds from Google, independent of the client.
4. **Backend work** (`Hydrawav3-Server`): needs a NEW verification path — Android purchases are verified via the **Google Play Developer API** (purchase token verification), completely separate from Stripe's webhook/API. The existing Stripe subscription state in Mongo (`payment.schema.ts`) would need either a parallel Android-purchase schema or a unified "entitlement" model that doesn't care which payment rail granted it.
5. **Reconciliation**: a user's plan/token entitlement must be resolved consistently regardless of whether they bought on web (Stripe) or Android (Play Billing) — this is a real backend design decision, not just a client change.

---

## 5. What changes for a real purchase flow — iOS / the IPA specifically

This is the part with the most "extra, iOS-only" requirements:

1. **Add `in_app_purchase` package** (wraps StoreKit — StoreKit 2 is what Apple pushes for new integrations; the Flutter plugin supports it).
2. **Xcode capability**: enable **In-App Purchase** capability in the Runner target (Signing & Capabilities tab) — this adds the entitlement to the app's provisioning profile. Currently **not present** (`ios/Runner.entitlements` doesn't exist in this project at all — confirmed by search).
3. **App Store Connect setup** (before any TestFlight/App Store build can even test purchases):
   - Create matching subscription products / auto-renewable subscription group in App Store Connect.
   - Complete **Paid Applications Agreement** (a separate legal agreement from the free-app one) — without this signed, StoreKit purchases silently fail even in sandbox.
   - Set up **App Store Server Notifications** (v2) so the backend learns about renewals/refunds/cancellations from Apple — parallel to Stripe's and Google's webhooks, a third independent notification system.
4. **Backend work**: verify iOS receipts/transactions via Apple's **App Store Server API** (JWS-signed transaction verification, StoreKit 2 style) — again, a completely separate verification path from Stripe and from Google Play.
5. **Sandbox testing**: Apple requires testing with **Sandbox Apple IDs** (separate from your real Apple ID) before submission — purchases in TestFlight builds still hit the sandbox environment, not real billing.
6. **App Review submission notes**: Apple explicitly asks reviewers to test the purchase flow — the submission must include a working IAP flow reviewers can complete, or the build gets rejected/held. A "coming soon" or partially-wired purchase button is treated the same as a real violation.
7. **Guideline 3.1.3(b)** (if you ever want a "Restore Purchases" button, which Apple requires for any non-consumable/subscription IAP) — needs explicit implementation, not automatic.
8. Given this app **already got rejected twice before** (per project memory: iOS App Store v1.0(8), rejected for screenshots then for an external-browser registration flow under a related "send users outside the app" guideline) — Apple's review team for this specific app is now primed to scrutinize anything that smells like a payment redirect. Extra care is warranted, not less.

---

## 6. Net comparison

| | Android (Play) | iOS (App Store) |
|---|---|---|
| Can use Stripe directly for in-app purchase? | No (not by default) | No, essentially never (3.1.1) |
| Required billing system | Google Play Billing (`in_app_purchase` package) | StoreKit / Apple IAP (`in_app_purchase` package) |
| New backend verification path needed | Yes — Google Play Developer API | Yes — App Store Server API |
| New store-side product setup | Yes — Play Console products/subscriptions | Yes — App Store Connect products + Paid Apps Agreement |
| Extra capability/entitlement in the app | `BILLING` permission (manifest) | In-App Purchase capability (Xcode, creates entitlement) |
| Extra legal/agreement step | None beyond standard developer account | **Paid Applications Agreement** (separate signature) |
| Commission | 15-30% (Google) | 15-30% (Apple) |
| Alternative to avoid native billing entirely | User Choice Billing (selective enrollment) | External Purchase Link Entitlement (narrow, US-focused, status can change — verify current eligibility before relying on it) |
| Current app status | Not built | Not built — deliberately withheld by design |

---

## 7. Recommendation

Given the current codebase already made the safe call (no purchase UI anywhere, avoiding a guaranteed 3.1.1 rejection), the actual decision needed isn't a code change — it's a **product/business decision**:

- **Option A — Keep it read-only on mobile.** Practitioners view their plan/usage in the app but upgrade only via the web app (Stripe Checkout, already fully built server-side). Zero additional store-billing work, zero commission cut, but no in-app upgrade path on phone.
- **Option B — Build native IAP on both platforms.** Real work on both backend (two new verification/notification pipelines) and both native shells (Play Billing + StoreKit), plus new legal agreements and a 15-30% cut to each store on every mobile sale. This is the only way to offer "buy from the app" on iOS at all.
- **Option C — Android via Stripe, iOS stays read-only.** Google's policy is currently more permissive in practice (though tightening) — a hybrid where Android gets a real purchase flow (via Stripe or Play Billing) while iOS stays informational-only is a real middle ground some apps run, but it needs its own Play policy review to confirm eligibility, since "more permissive in practice" is not the same as "guaranteed compliant."

There is no path that lets Stripe alone power a real in-app purchase button on iOS — that's the one fixed constraint everything else has to work around.
