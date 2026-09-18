# tasks/todo.md — Sprint: M9 Ride Summary & History

**Dates:** Fri 2026-09-18 → Thu 2026-10-01 (2 weeks) · **Team:** 1 (Brian + Claude)

**Sprint Goal:** A finished ride lands on a real Ride Summary screen and stays in real history —
`DemoRide` is deleted from the app.

---

## Why this sprint exists

M9 is due 2026-10-23 with **two** issues filed, and neither is the summary screen. Verified against
the tree, not the milestone:

- `RidesFeature.swift:9` — `var demoRides: [DemoRide] = DemoRide.sampleRides`. The Rides tab is a
  prototype against sample data.
- UX.md screen inventory — S10, S14 and S15 are all `Stub`.
- `ActiveRideFeature.swift:550` finalizes the ride to SwiftData and exports GPX, then presents
  **nothing**. There is no post-ride screen.
- No `HKWorkout` is ever written. `PermissionsClient.swift:120-125` already requests the
  authorization; nothing uses it.

What already exists and does **not** need rebuilding: `Ride` carries every field S10 needs
(`hrZoneDurations`, `averageCadenceRPM`, `vehiclePassCount`, elevation gain/drop, `maxSpeedMPS`);
`finalizeRide` / `RideSummaryUpdate` / `PendingRideEnd` crash recovery are all built and tested;
`RidesView.swift` already has chart and map components (`HeartRateProfileView`,
`ElevationProfileView`, `RideMapView`) — they just read demo data.

Design sources confirmed present in `Design.sketch`: **S10 — Ride Summary**, **S14 — Ride History**.
S15 has no artboard by design — UX.md §S15 spec's it as a standard detail view.

---

## Capacity

1 point ≈ one merged PR of this repo's typical size.

| Person | Available | Allocation | Notes |
|---|---|---|---|
| Brian + Claude | 10 working days | 24 pts | Travel GSO→SDY 9/19, working through it (confirmed) |
| **Total** | **10 days** | **24 pts** | Median 12 merged PRs/wk over W33–W38 (12, 14, 10, 12, 14, 10) |

**Planned capacity: 24 pts · Sprint load: 19 pts (79%)** — inside the 70–80% band.

---

## Sprint Backlog

| Pri | Item | Issue | Est | Depends on |
|---|---|---|---|---|
| P0 | Rides tab on real persisted rides — `fetchRides` + kill `DemoRide` | **#247** | 2 | — |
| P0 | S14 Ride History list — real rows, relative dates, swipe-to-delete, `ContentUnavailableView` empty state | **#248** | 2 | P0-1 |
| P0 | Capture + persist static map thumbnail at ride end | **#177** | 3 | — |
| P0 | S10 Ride Summary — screen + ride-end presentation | **#249** | 4 | P0-3 |
| P0 | Write `HKWorkout` at ride end, before S10 presents | **#250** | 2 | — |
| P1 | S15 Ride Detail on real data, via `StackState` + `NavigationLink(state:)` | **#251** | 2 | P0-1 |
| P1 | Unpaired HR strap connects and streams with no confirmation | **#180** | 2 | — |
| P1 | HR strap connects but never streams — no notify-state check, no staleness watchdog | **#181** | 2 | — |
| P2 | HealthKit HR zone tracking (`HKWorkoutZoneGroup`) — **stretch, not committed** | **#238** | 5 | — |

**P0 = 13 pts · P1 = 6 pts · committed = 19 pts · stretch = 5 pts**

### Order of play

Week 1 — P0-1 → P0-2 → P0-3 → P0-5
Week 2 — P0-4 → P1-6 → P1-7 → P1-8

P0-4 (S10) is the headline and is scheduled second week on purpose: it consumes the thumbnail from
P0-3 and the `HKWorkout` write from P0-5, and it is the item most likely to expand.

---

## Tasks

### Before any code
- [x] File the five missing M9 issues — #247, #248, #249, #250, #251
- [x] Move #180 and #181 into M9 — both are HR-path correctness bugs and S10 renders an HR zone breakdown
- [ ] Re-date M9 from 2026-10-23 to 2026-10-02 to match this plan (see Risks)

### P0-1 — Rides tab on real persisted rides — #247 (2)
- [ ] `PersistenceClient.fetchRides` returning finished rides, newest first (mirror `fetchRides(routeId:)`)
- [ ] `RidesFeature.State` holds `[Ride]`-derived value types, loaded on `.task`
- [ ] Delete `DemoRide` and `DemoRide.sampleRides` outright
- [ ] `TestStore` coverage with a seeded in-memory container

### P0-2 — S14 Ride History list — #248 (2)
- [ ] Rows per UX.md §S14: 56×56pt thumbnail, name + relative date, distance (`HeroNumber` small), elapsed (D-DIN Condensed 20pt)
- [ ] Trailing swipe: Delete (destructive). Leading Sync / Make Route are Phase 2 — do not build
- [ ] `ContentUnavailableView` empty state exactly as UX.md §S14 gives it
- [ ] Snapshot tests, light + dark, empty and populated

### P0-3 — Ride map thumbnail (#177) (3)
- [ ] `@Attribute(.externalStorage)` light + dark variants on `Ride`, mirroring `weatherData`
- [ ] `MKMapSnapshotter` over the recorded track at ride end, POI labels suppressed
- [ ] Polyline composited in `cyPrimary` via the snapshot's `point(for:)`
- [ ] Bounding-box + pixel-projection logic unit-testable without live map tiles

### P0-4 — S10 Ride Summary — #249 (4)
- [ ] `RideSummaryFeature` + view against the `Design.sketch` **S10** artboard
- [ ] Map thumbnail, distance / time / avg speed, elevation profile, HR zone pie, avg cadence, vehicle pass count
- [ ] Rename field — tapping the title focuses it; defaults to route name
- [ ] Presented from the ride-end sequence; Done dismisses to the dashboard
- [ ] No Sync button — the sync sheet is Phase 2 (UX.md §S10). No GPX export action — the file is already written
- [ ] `TestStore` for the reducer, snapshots light + dark

### P0-5 — HKWorkout at ride end — #250 (2)
- [ ] Write the workout in the ride-end sequence, before S10 presents (UX.md §S10)
- [ ] Failure degrades and logs — never blocks the ride ending, matching `finalizeRide`'s existing posture

### P1-6 — S15 Ride Detail — #251 (2)
- [ ] Drill down from S14 on `StackState` + `NavigationLink(state:)` + delegate — not a workaround
- [ ] Repoint the existing chart/map components at real `TrackPoint` data

### P1-7 — #180 unpaired strap streams (2)
- [ ] Reproduce and confirm what actually fires `pairButtonTapped`
- [ ] Pairing requires a real confirm step; no single `Button` tap can commit it

### P1-8 — #181 strap connects, never streams (2)
- [ ] `BLEClient` implements `didUpdateNotificationStateFor`; failure stops `broadcastPairing(true)`
- [ ] Staleness watchdog on the BLE HR stream, mirroring the HealthKit staleness handling in `ActiveRideFeature.swift:14`

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| The milestone chain has no slack: M9 10/23 → M10.5 10/29 (17 issues) → M10.6 11/02 → M11 11/06 | Any M9 slip eats M10.5 whole, and M10.5 is the largest open milestone | Re-date M9 to 2026-10-02. M9 finishing on its filed date leaves M10.5 six days for 17 issues; finishing 10/02 leaves four weeks |
| Travel 9/19, no return flight booked | Capacity assumption of "normal" is unverified past week 1 | Mid-sprint check-in 9/25 is the decision point — cut P1 first, in listed order |
| S10 is the one screen with no existing code and the most surface | 4 pts could become 6 | Artboard exists and `Ride` already has every field — no data work inside it. Scheduled week 2 so it can absorb the slip |
| ~~Five of eight items have no issue yet~~ **Resolved 2026-09-17** | — | All eight committed items now have filed issues with ACs |
| #180's trigger was never mechanically confirmed from logs | A fix could miss the real cause | AC-1 is reproduce-and-confirm before fixing |

---

## Definition of Done

- [ ] Feature branch + PR — no direct commits to `main`
- [ ] Reducer logic covered by Swift Testing + `TestStore` with `withDependencies`
- [ ] UI covered by snapshot tests, light + dark, explicit `cy*` tokens (never ambient `.primary`/`.accentColor`)
- [ ] `xcodebuild build` and `xcodebuild test -only-testing:CyclometerTests` green on iPhone 17 Pro
- [ ] Specs reconciled — UX.md screen inventory flipped `Stub` → `Complete` for S10, S14, S15
- [ ] Issue ACs ticked against verified behavior, not assumed

---

## Key Dates

| Date | Event |
|---|---|
| Fri 2026-09-18 | Sprint start |
| Sat 2026-09-19 | Travel — GSO → ORD → BIL → SDY |
| Fri 2026-09-25 | Mid-sprint check-in — cut P1 here if week 1 landed under 10 pts |
| Thu 2026-10-01 | Sprint end |
| Thu 2026-10-23 | M9 due (recommend re-dating to 10/02) |

---

## Review

_To be completed at sprint end._
