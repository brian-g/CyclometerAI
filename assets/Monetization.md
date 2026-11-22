# Monetization Spec

**Status:** Draft v0.2 · 2026-11-22 · Milestone: M12 — App Store Submission
**Model:** Free download · 28-day full-feature trial · $9.99 one-time Lifetime Unlock · No subscription

---

## 1. Summary

Cyclometer is free to download. Every feature is unlocked for 28 days. After the trial, the app drops to a Free tier that still records rides with up to 3 sensors on one dashboard page. A single non-consumable in-app purchase unlocks everything permanently.

The trial is tracked by the app itself. It does **not** use a $0 "XX-day Trial" IAP. There is nothing for the rider to start, nothing to cancel, and no auto-billing.

---

## 2. Tiers

| Capability | Trial (28 days) | Free (after trial) | Unlocked |
|---|---|---|---|
| Ride recording, live dashboard | ✓ | ✓ | ✓ |
| Ride history & Ride Detail | ✓ | ✓ | ✓ |
| Apple Health workout write | ✓ | 🔒 | ✓ |
| GPX ride export | ✓ | ✓ | ✓ |
| Routes (import, navigate) | ✓ Unlimited | ✓ Unlimited | ✓ Unlimited |
| Sensors (HR, speed, cadence, power) | Unlimited | **Up to 3** | Unlimited |
| Dashboard pages | Unlimited | **1** | Unlimited |
| Radar (Garmin Varia) | ✓ | 🔒 | ✓ |
| AR glasses | ✓ | 🔒 | ✓ |
| Weather (WeatherKit) | ✓ | 🔒 | ✓ |
| Services (Strava, RideWithGPS, etc.) | ✓ | 🔒 | ✓ |

### Counting rules
- **Sensors** are counted per physical paired device (`PairedSensor`). A combined speed/cadence (CSC) sensor counts as **1**, even though it feeds both `SpeedFeature` and `CadenceFeature`.
- **Radar** and **AR glasses** are gated separately and **do not count** toward the 3-sensor limit.
- **Apple Watch** as a heart rate source does **not** count toward the limit.
- **Routes are never gated.**

---

## 3. Trial mechanics

- **Length:** 28 days of calendar time.
- **Start:** the first time a ride is recorded, not at download. A rider who installs and waits a week still gets the full 28 days.
- **Persistence:** the trial start date is written to iCloud key-value storage (`NSUbiquitousKeyValueStore`) and to an iCloud-synchronized Keychain item. Deleting and reinstalling the app, or moving to another device on the same Apple ID, does not restart the trial.
- **Fallback:** if no stored start date can be found but `AppTransaction.shared.originalPurchaseDate` is more than 28 days old **and** local ride history exists, treat the trial as expired.
- **Clock tampering:** not defended against beyond the above. Not worth the complexity at $9.99.
- **Mid-ride expiry:** never take a feature away during an active ride. If the trial ends mid-ride, the ride finishes fully unlocked and the new state applies when the next ride starts.

### Trial UI
- **Days 1–18:** a quiet "X days left in trial" row in Settings. No banners on the ride dashboard.
- **Days 19–28:** a dismissible banner on the Rides tab: "Trial ends in X days — Unlock for $9.99."
- **Day 29, first launch:** a one-time sheet explains what changed and what stays free, with Unlock and "Continue with Free" buttons of equal weight.

---

## 4. Day-29 downgrade behavior

Nothing the rider set up during the trial is deleted. Everything returns the moment they unlock.

| Item | Behavior after trial |
|---|---|
| Sensors beyond 3 | Stay paired. The rider chooses which 3 are active (prompted on the next ride start). The rest show a lock and "Unlock to use." |
| Dashboard pages beyond 1 | Saved and obscured. Page 1 stays active. Obscured pages are restored on unlock. Each Obscured page is overlayed with a layer that obscures the dashboard and has information to purchase on top. See S05 - Obscured in Sketch. |
| Radar | Stays paired. The radar column (W7) shows a lock state with an unlock prompt. No radar alerts. |
| AR glasses | Stay paired, no output. Lock shown in Settings → Sensors. |
| Weather | The weather widget shows a lock state. No WeatherKit calls. |
| Apple Health | No workout is written at ride end. The Apple Health row in Sync To (S10) shows a lock. Workouts written during the trial stay in Health. |
| Services | Accounts stay connected (tokens kept). Sync To in Ride Summary (S10) shows the services locked. No uploads. |

---

## 5. Paywall moments

Show the unlock prompt only when the rider reaches for a locked feature. No paywall on launch.

| Trigger | Headline |
|---|---|
| Pairing a 4th sensor | "Use more than 3 sensors" |
| Pairing a radar | "Radar alerts on your dashboard" |
| Pairing AR glasses | "Ride data in your glasses" |
| Adding a 2nd dashboard page | "Build more dashboard pages" |
| Turning on weather | "Live weather on your ride" |
| Tapping the locked Apple Health row in Sync To | "Save rides to Apple Health" |
| Connecting a service / tapping a locked Sync To row | "Send rides to Strava and more" |

Every paywall shows:
- What this specific tap unlocks (headline above)
- A short list of everything else included
- **"Unlock Cyclometer — $9.99 once"** (localized price from StoreKit)
- "No subscription. Yours forever."
- **Restore Purchase** link (required by Apple for non-consumables)
- A close button

Radar copy stays factual, not fear-based.

---

## 6. App Store Connect setup

| Field | Value |
|---|---|
| App price | Free |
| IAP type | Non-consumable |
| Reference name | Lifetime Unlock |
| Product ID | xyz.acmeapps.ride.lifetime |
| Price | $9.99 (US base) |
| Family Sharing | On |

**App Store listing:** the store page won't show a trial badge, so put the offer in the copy. Subtitle or first line: "28-day free trial, then $9.99 once. No subscription."

**App Review notes:** "Free download. All features are unlocked for 28 days, starting with the first recorded ride. After that, ride recording with up to 3 sensors and 1 dashboard page remains free. A one-time non-consumable IAP (Lifetime Unlock) unlocks radar, AR glasses, weather, Apple Health workouts, services, unlimited sensors and dashboard pages. To test the expired state, use Settings → Debug → Expire Trial (debug builds only)."

---

## 7. Architecture

One TCA dependency owns all entitlement logic. Views and reducers ask it; they never check dates or StoreKit directly.

```swift
struct EntitlementsClient {
    var state: @Sendable () async -> EntitlementState
    var updates: @Sendable () -> AsyncStream<EntitlementState>
    var purchase: @Sendable () async throws -> PurchaseResult
    var restore: @Sendable () async throws -> Void
    var recordFirstRide: @Sendable (Date) async -> Void
}

enum EntitlementState: Equatable {
    case trial(daysRemaining: Int)
    case free
    case unlocked
}

enum Limits {
    static let freeSensors = 3
    static let freeDashboardPages = 1
}

enum GatedFeature: CaseIterable {
    case radar, arGlasses, weather, appleHealth, services
    case extraSensors, extraDashboardPages
}
```

- **Live client:** StoreKit 2 `Transaction.currentEntitlements` + `Transaction.updates` for the unlock, plus iCloud KVS / Keychain for the trial start.
- **Mock clients:** `.trial(days:)`, `.free`, `.unlocked` for Simulator, previews and tests.
- **Unlock always wins:** any verified Lifetime Unlock transaction → `.unlocked`, whatever the trial state.
- **Refunds:** a revoked transaction (`revocationDate` set) → back to `.free`. Downgrade rules from §4 apply.
- **Debug menu:** Settings → Debug → Set trial day / Expire trial / Reset (debug builds only). StoreKit sandbox returns a fixed `originalPurchaseDate`, so trial logic must be testable without it.

---

## 8. Tests

- Trial starts on the first recorded ride, not at install
- Trial start survives reinstall (KVS/Keychain read)
- Day 28 → trial; day 29 → free
- Trial expiring mid-ride keeps features until the ride ends
- Unlock purchased during the trial → unlocked, trial UI hidden
- Refund/revocation → free
- Restore → unlocked
- Free: 4th sensor pairing triggers the paywall; a CSC sensor counts as 1; radar and glasses don't count toward 3
- Free: with more than 3 sensors paired, the ride start prompts the rider to choose 3
- Free: pages 2+ are obscured, not deleted; restored on unlock
- Free: no WeatherKit calls; no HKWorkout write; no service uploads; tokens kept
- Free: an Apple Watch HR source doesn't count toward 3
- Routes: no limit in any state

---

## 9. Resolved

1. Family Sharing for Lifetime Unlock: **on** (2026-11-22)
2. Apple Watch as an HR source: **doesn't count** as a sensor (2026-11-22)
3. Milestone: **M12 — App Store Submission** (2026-11-22)
4. Launch discount: **none** (2026-11-22)
5. Trial length: **28 days**, up from 14; Apple Health workouts move into the unlock (2026-11-22)
