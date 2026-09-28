# #331 — Routes Map/List toggle moves to the bottom

Plan: /Users/brian/.claude/plans/unified-juggling-tome.md
Branch: `fix/331-routes-toolbar`

- [x] 1. RoutesView: drop the toolbar toggle; bottom-trailing `safeAreaInset` glass button (reuses `MapSheetButton`)
- [x] 2. UX.md §S19 + Updated line
- [x] 3. Re-record RoutesSnapshotTests screen references; inspect every PNG
- [x] 4. Unit suite green (1660/0, case count checked)
- [x] 5. Minimised-ride clearance verified (key-window AppView render; the sim drive can't minimise the dashboard)
- [x] 6. ios-reviewer, PR

## Review

- The approved segmented List | Map capsule was replaced mid-work with a single glass button, at Brian's call. The first version nested a segmented track inside a glass capsule and read as a switch. Lesson recorded.
- Snapshots stay offscreen, as before. Offscreen capture draws no glass, so the references show a bare glyph (the same as `MapSheetButtonsSnapshotTests`). Key-window capture drew the glass, but it gave two deterministic renders of the light empty state (freshly booted vs. already-run simulator), so it was dropped.
- Verified: in the real `AppView` with a minimised ride, the button sits above the accessory. Not verified: the accessory inline with a scroll-minimised tab bar. The safe-area mechanism should cover it, but it's untested.

# #303 — Recorded altitude ignores verticalAccuracy

Plan: /Users/brian/.claude/plans/goofy-petting-shore.md
Branch: `fix/303-vertical-accuracy`

- [x] 1. `LocationUpdate.altitude: Double?` + `init(_ location: CLLocation)`; LocationManagerState uses it
- [x] 2. `ActiveRideFeature.State.altitude: Double?`
- [x] 3. `TrackPointDTO.altitudeMeters: Double?`
- [x] 4. CoreData v3 (optional altitude), TrackPointMO NSNumber?, PersistenceClient mapping
- [x] 5. GPXExporter omits `<ele>` for nil
- [x] 6. `RouteTerrain.movingAverage([Double?])` + RideEnergy uses it
- [x] 7. HealthKit routeLocations `?? 0`
- [x] 8. Tests: LocationClient, recording, RideEnergy, GPX, Persistence, migration (v1+v2), RouteTerrain
- [x] 9. Full suite green (1660/0), ios-reviewer, PR

## Review

- Altitude is absent, not held: holding couldn't cover the points before the first valid vertical fix (still `<ele>0`), and #221 already rules out recording held values.
- Deviation from the issue: `LocationUpdate.altitude: Double?` at the client boundary instead of a new `verticalAccuracy` field.
- The issue's energy figure is wrong. At 300 m, a single 0 m fix smooths into a 9.7 m one-second step, which the 25% grade cap already discards. The energy effect is real only below ≈ 8 × speed metres (≈ 1.1 kcal at 40 m, 8 m/s). The GPX `<ele>0` and the profile dip were the real defects.
- Rides recorded before the update keep their stored altitudes. A 0 m invalid fix can't be told apart from sea level.
- Review follow-ups: comment wording (ActiveRideFeature, RideDetailSeries, migration test) and a HealthKit nil → 0 test.

# #318 — iPhone workout session for live HR zone updates (decision)

Plan: /Users/brian/.claude/plans/staged-churning-yao.md
Branch: `docs/318-workout-session-decision`

- [x] 0. Move #318 to "Phase 2 — Companion & History" (stays open, with S17)
- [x] 1. PRD §9.4 decision note
- [x] 2. PRD revision history 0.6.7
- [x] 3. UX.md §W12 source line + header Updated line
- [x] 4. PR #323, comment on #318

## Review

- Decision: no iPhone `HKWorkoutSession` / `HKLiveWorkoutBuilder`. The strap's HR never reaches HealthKit, so a live builder could only re-zone the app's own readings, and that would cost a new HR share permission and a double write against a Watch. The existing background modes already cover the ride. The session would replace #250 and #277's idempotent, retried post-ride write, and add a second crash-recovery system alongside #175 and #188.
- #318's premise that W12 shows time in zone is not built. W12 shows the current zone only, and #145 holds the open question on time in zone. The decision records that W12's time in zone, once built, is local.
- Docs only, with no code or test changes.

# #277 — Retry the ride's HKWorkout write until it lands

Plan: /Users/brian/.claude/plans/buzzing-doodling-piglet.md
Branch: `feat/277-retry-hkworkout`

- [x] 0. Spike: a same-version re-save (sim, iOS 27) returns and *replaces* — new workout UUID, count 1, one distance sample. Keep version 1
- [x] 1. `Ride.isHealthWorkoutOwed` (default false → legacy rides done)
- [x] 2. Persistence: finalize sets owed; owed list; settle; `OwedHealthWorkout`; client + mock
- [x] 3. `RideHealthWorkout.backfill()` (energy block moved from ActiveRideFeature)
- [x] 4. `BackfillGate` + `healthWorkoutGate`
- [x] 5. Finish path calls the backfill
- [x] 6. AppFeature launch + close-outs run it
- [x] 7. UX.md §S10
- [x] 8. Tests: migration, persistence, backfill, RideEndFailure relaunch/close-out, AppFeature orphan
- [x] 9. Verify: full `CyclometerTests`, sim ride → one workout

## Review

- The workout write moved out of the Finish effect into `RideHealthWorkout.backfill()`, the only writer, modelled on `RideMapThumbnail.backfill()`. It runs after Finish's finalize, at launch and after both AppFeature close-outs. It goes newest first and stops at the first failure.
- `Ride.isHealthWorkoutOwed` (default false) is set by `finalizeRide` and cleared when a write returns, including a skipped duplicate. Rides that ended before this change are not owed (decision: mark as done).
- A ride that ends before it starts is settled without a write, so it can't block the queue forever.
- `MapThumbnailGate` became `BackfillGate`, with a second `healthWorkoutGate` key so workouts never wait behind map tiles.
- Spike (sim, iOS 27): re-saving at the same sync version *replaces* the workout (new UUID, count 1). Apple only documents replacement for a higher version.
- Full `CyclometerTests`: ** TEST SUCCEEDED **, 1617 cases. All 17 new or extended tests confirmed by name in the log.
- Sim drive: an earlier ride opened as not owed with its one workout intact. A new ride's workout was written once and settled, and relaunches left it (same UUID).
- Harness finding: a pending launch Health sheet (types #276 added) silently blocks the Start sheet in a drive. Grant it first.
- Review follow-ups (/code-review high):
  - The #175 orphan close-out settles its ride without a workout, since its `endedAt` is the relaunch. Mutation-checked.
  - `rideNotFound` on settle (ride deleted mid-write) no longer ends the batch.
  - New `HealthKitClient.isWorkoutSharingAllowed`: without Workouts share access the backfill does no reads.
  - UX.md §S10: a launch that resumes a ride doesn't retry. Header order fixed, and a test doc comment moved back.
- Full `CyclometerTests` after the follow-ups, on a fresh derived data path: ** TEST SUCCEEDED **, the three new or changed tests confirmed by name.
- Merge with main (#238): the workout's zone stamp moved from the Finish effect into `RideHealthWorkout`, resolved at write time from the shared `riderProfile` and Health, as S10 and S15 do, so a retried workout carries the zones too.

# #238 — Health's preferred HR zones as a zone source

Plan: /Users/brian/.claude/plans/elegant-drifting-harp.md
Branch: `feat/238-healthkit-zones`

- [x] 0. Spike: N boundaries → N+1 zones (index 0-based, first min / last max nil), `[min, max)`; non-increasing input raises an ObjC exception (crash, not a throw); sim `preferred` → nil
- [x] 1. `HealthKitClient.fetchHeartRateZoneCeilings` + pure `zoneCeilings(from:)` + mock
- [x] 2. `RiderProfile`: `healthZoneCeilings` term — `boundaryOverride ?? (no resting/max override ? health : nil) ?? karvonen`, validity check
- [x] 3. Thread ceilings through ActiveRide, Settings, RideSummary, RideDetail
- [x] 4. `RideWorkout.heartRateZoneBoundariesBPM` + `setCustomZoneConfiguration` in `saveWorkout`
- [x] 5. Tests (RiderProfile, HealthKitClient, 4 features, RideEndFailure) + mutation check
- [ ] 6. Docs: PRD §8.5/§9.4 + 0.6.5, UX §S12, DataModel §3.5
- [x] 6. Docs: PRD §8.5/§9.4/OQ9 + 0.6.6 (0.6.5 was taken by #276), UX §S10/§S12, DataModel §3.5
- [x] 7. Housekeeping: filed #318 (live session, M9) and #319 (HeroNumber digits, M10.5); closed #167 as superseded; PR #320. No #238 comment (declined)

## Review

- Spike findings the design rests on: `HKWorkoutZoneConfiguration(zoneBoundaries:)` takes the N inner boundaries → N+1 zones, each `[min, max)`. A non-rising list raises an Objective-C exception (a crash, not a Swift throw), so `stampZones` checks order first. On the sim, `preferredWorkoutZoneConfiguration` returns nil.
- Ceiling = `ceil(next zone's minimum) − 1`, matching Karvonen's `lowerBound(next) − 1`. The workout stamp adds the 1 back.
- The fallback is logged once, at fetch (source, zone count, ceilings). It is not logged in `RiderProfile`, which runs at 1 Hz on the dashboard. This departs from the plan.
- The stamp is nil when the resolved ceilings equal Health's, and otherwise holds the resolved ones. That includes Karvonen when Health has no zones, so the existing #250 workout test now expects `[138, 151, 164, 177]`.
- Not unit-testable: `stampZones` (live HealthKit). A stamp failure is `try?` + a log, the same as the route.
- Harness: `-only-testing:CyclometerTests/ActiveRideFeatureTests` matches nothing, because the file's suites are `ActiveRideFeature<Area>Tests`. The full run confirmed the new dashboard test by name.
- Full `CyclometerTests`: ** TEST SUCCEEDED **, 1627 passed, 0 failed.
- Mutation checks:
  - (1) Health term dropped → 9 new tests fail.
  - (2) Override and order guards dropped → the override test (×2), the edge test and 4 of the 6 shape cases fail. The count guard kept by that mutation covers the other 2; with it removed, the suite crashes on an out-of-range index.
- **Code review fixes:**
  - The workout stamp now happens only with an S12 override (`RiderProfile.hasZoneOverride`). Before, a failed, late or denied Health read stamped Karvonen over the rider's Health zones.
  - Health's ceilings are no longer capped at the app's max. `tableMaxBPM` raises zone 5's top to meet them instead, so zones set by a rider older than the 220 − age formula assumes aren't dropped.
  - A failed zone read is now logged, and the ceilings are logged `.private`.
  - Full suite: 1634 passed, 0 failed.
  - Mutation checks: always-stamp fails 2 tests, and an unraised top fails 1.
- Declined review points: speed (4 numbers, 1 Hz), a HealthTerms refactor (separate issue if wanted), the duplicated rising check, and the #162 doc fix, which was in the plan.
- Pending on device: S12 matches iOS Health → Heart Rate Zones; after a strap ride, Fitness shows those zones; with an S12 override set, Fitness shows the overridden ones.

# #276 follow-up — heart-rate energy model (Keytel), physics as the fallback

Plan: /Users/brian/.claude/plans/twinkling-brewing-volcano.md
Branch: `feat/276-active-energy`

- [x] 1. `RideEnergy`: `Rider`, `Sex`, `Estimate { kilocalories, method }`, and Keytel at the mean HR over recording time, less 1 MET, clamped ≥ 0
- [x] 2. `RiderProfile.age(fromDateOfBirth:on:)` extracted from `estimatedMaxBPM`
- [x] 3. `HealthKitClient.fetchBiologicalSex` + mock; `biologicalSex` read type
- [x] 4. Ride end: weight, date of birth and sex read in parallel; log which model ran
- [x] 5. Tests: Keytel male/female, 50% coverage threshold (mutation-checked), mean costing, clamp, sex/age fallback, ride-end HR integration
- [x] 6. Docs: PRD §9.4 + 0.6.3, UX §S01/§S10, Info.plist

## Review

- Why: a real 14:52 ride gave 15 kcal from physics. Counting 1 kJ of work as 1 kcal leaves out the cost of moving your legs at all, which dominates at easy power.
- The HR model runs only with strap-level coverage (≥ 50% of recording seconds) plus weight, date of birth and a Male/Female sex. Anything less uses physics (decision: no averaged equation for Not Set or Other). No weight still means no energy.
- Harness finding: an unpaired strap's reading is blanked by the tick (#161), and pairing opens a 10 s warm-up (#221). `runRideToEnd(heartRateBPM:)` pairs first and resends until a reading lands.
- Build finding: a stale module after the earlier mutation revert made the tests compile against the old API. Fresh `-derivedDataPath` + `COMPILATION_CACHE_ENABLE_CACHING=NO` fixed it (as the memory note says).
- Full `CyclometerTests` passed (** TEST SUCCEEDED **, 1586 cases).
- Pending on a device: an easy strap ride should now read tens of kcal, not 15. Compare it with the Watch's Active Energy for the same window.

# #276 — Active energy on the ride's HKWorkout (physics model, MET fallback; supersedes #274)

Plan: /Users/brian/.claude/plans/twinkling-brewing-volcano.md
Branch: `feat/276-active-energy`

- [x] 1. `RideEnergy` estimator (physics per 1 Hz pair, MET for gaps/no speed/implausible grade/residual time); bike weight a 10 kg constant
- [x] 2. `RideWorkout.activeEnergyKilocalories`
- [x] 3. `PermissionsClient`: `bodyMass` read, `activeEnergyBurned` share
- [x] 4. `HealthKitClient.fetchBodyMass` + energy sample in `saveWorkout`
- [x] 5. `ActiveRideFeature` ride end: body mass → estimate → workout (nil without body mass)
- [x] 6. Tests: `RideEnergyTests`, `RideEndFailureTests`, `PermissionsClientTests`
- [x] 7. Docs: PRD §9.4 + changelog, UX.md §S10, Info.plist share string
- [x] 8. Verify: full `CyclometerTests`; device Move-ring check is Brian's

## Review

- `RideEnergy` (pure enum) estimates active kcal from the persisted track: per 1 Hz pair, pedal power = (air + rolling + gravity) ÷ (1 − 2.5% drivetrain loss), clamped at 0 so coasting adds nothing, on altitude smoothed over ~31 s. kJ ≈ kcal. MET (2024 Compendium, minus 1 for resting) covers a pair with no speed, a gap > 5 s, or a smoothed grade > 25%, plus recording time the track doesn't cover. Stationary seconds (#262 threshold) add nothing.
- The ride-end effect reads `HealthKitClient.fetchBodyMass` (latest sample). If there's none, `RideWorkout.activeEnergyKilocalories` is nil and no energy is written. `saveWorkout` adds an `activeEnergyBurned` sample (`<rideId>-energy`) when share access allows, mirroring distance.
- New types: `bodyMass` read and `activeEnergyBurned` share. PRD §9.4 + 0.6.3 row, UX §S01/§S10, and the Info.plist read string are updated.
- Bike weight is a 10 kg constant (decision), which departs from #276's Data Model criterion. #274 is superseded.
- 2024 Compendium 01060 (>20 mph) is 16.8 MET, not the 2011 value of 15.8.
- Tests: `RideEnergyTests` (flat ≈ 547 kcal/h at 30 km/h, climb = m·g·h/0.975, coasting descent 0, pause, gap/no-speed/implausible-grade/uncovered MET, bands) and `RideEndFailureTests/workoutCarriesEstimatedEnergy`. The existing workout test pins nil energy without body mass. Full `CyclometerTests` passed (** TEST SUCCEEDED **, 1577 cases).
- Not verified: the Move ring on a device, and how a paired Watch's own Move reading interacts with it.
- Device test (2026-09-26, walking pace, 1.24 m/s mean): Health stored 3.63 kcal, which matches a replay of the GPS fixes through the formula. The write path works. Added logging for each way the energy can go missing.
- `/code-review high` follow-up. Fixed: a no-speed second counts as stationary (was GPS wander costed at MET), and altitude is smoothed per run, never across a > 5 s gap (mutation-checked). Inside the track, gaps and implausible grades are costed as flat physics instead of MET, because MET ran 1.5–2.6× the physics rate. MET is only used for a ride with no usable track. A failed body-mass read is logged as itself. `RouteGeometry.segmentMeters` replaces a two-element array. Filed #303 (altitude ignores `verticalAccuracy`). Skipped: kJ ≈ kcal gross vs active (the issue specifies it, and it's the power-app convention), Watch double counting (device check), and serializing the ride-end reads (negligible). Full suite passed, 1579 cases.

# #280 — Ride thumbnails framed so the track fills the square

Plan: /Users/brian/.claude/plans/sprightly-gathering-tarjan.md
Branch: `fix/280-thumbnail-zoom`

- [x] 1. `Spacing.mapThumbnailMargin`
- [x] 2. `RideMapThumbnail.mapRect(for:)` replaces `region(for:)`; 200 m floor
- [x] 3. `MapSnapshotClient.render` takes `MKMapRect`
- [x] 4. UX.md §S14 framing clause
- [x] 5. Framing tests replace `regionContainsTrack`
- [x] 6. Verify: full suite, before/after PNGs on real tiles

## Review

- Root cause: the thumbnail reused S19's `RoutesMapCamera.region(fitting:)`. Its 0.015° minimum span (about 1.7 × 1.2 km) swallowed short rides, and its 1.6× padding in degrees left even long rides at about 62% of the square.
- Now `RideMapThumbnail.mapRect(for:)` frames a square `MKMapRect` so the stroke sits 3pt from the edge on the longer axis, with at least 200 m across for rides that barely moved. Stored thumbnails are left as they are (decision): only new renders change.
- S15 (`RideDetailView`) also used `region(for:)`. It now calls `RoutesMapCamera.region(fitting:)` directly, so its framing is unchanged.
- Real-tile renders (throwaway test, not committed): the 0.4 mi out-and-back fills the square, the stationary ride shows as a dot, and a long ride fills diagonally.
- Suite: all thumbnail tests pass. 4 failures unrelated to this change: `RideDateTextTests` today/yesterday/calendarDayBoundary and `RidesSnapshotTests.testPopulatedRideHistory`. `DateFormatter.doesRelativeDateFormatting` uses the wall clock, not the injected `now` (pinned to 2026-09-23), so these only pass on that date. Same 4 fail on a clean `main` worktree. Filed as #291 (PR #292, merged). After merging `main` in, the full suite passes.
- Review follow-up (`/code-review high`): the frame is clamped inside `MKMapRect.world` for tracks across ±180°; the track rect comes from `RouteGeometry.boundingBox` corners instead of a hand-rolled union; tests check that `capture` passes `mapRect(for:)` to render and that every stretch of a paused ride fits. Skipped: re-rendering stored thumbnails (decided against), and a named helper for S15's one-line framing.

# #291 — S14 row date follows `now`, not the device clock

Branch: `fix/291-ride-date-now`

- [x] 1. `RideDateText.relativeFormatted` moves the ride's time of day onto the day `daysAgo` before the clock's today
- [x] 2. Tests: `now` years from the clock; de_DE keeps "Gestern"
- [x] 3. Verify: full `CyclometerTests`

## Review

- Cause: `DateFormatter.doesRelativeDateFormatting` names the day against the device clock, so the tests pinned to 2026-09-23 passed only on that day.
- Fix keeps the locale's own relative pattern. Known edge: a ride inside a spring-forward gap, projected onto a DST day, could print a shifted hour.
- Full suite green on 2026-09-24, including the 4 tests that failed on `main`; the S14 snapshot reference is unchanged.
- Review follow-ups (two `/code-review high` passes). The shift is now a whole-day move by the offset from `now` to the clock's today, and reports an issue if that can't be computed. A ride after `now` goes to the absolute branch. RideRow re-reads the clock through `TimelineView(.everyMinute)` when `now` isn't pinned, replacing a `now` fixed at build time; an earlier notification-driven `@State` was dropped. The de_DE test uses a far `now`.
- Known edges: the code and the formatter each read the clock, so a render straddling midnight can name the neighbouring day once. The TimelineView refresh isn't unit-tested; it holds no logic of its own.

# Coming-soon site (11ty) in docs/

Plan: /Users/brian/.claude/plans/luminous-stargazing-lynx.md
Branch: `site/coming-soon`

- [x] 1. 11ty scaffold in `docs/` (package.json, eleventy.config.js, src/)
- [x] 2. Shared layout, home hero (coming-soon / App Store CTA switch), privacy policy migrated verbatim
- [x] 3. site.css on colors.md tokens, light + dark; system-ui → Open Sans → sans-serif
- [x] 4. Hero photo (Unsplash, Viktor Bystrov) at 1600/2400w; favicon + apple-touch-icon from Cyclometer.icon layers
- [x] 5. Hosting: Cloudflare Pages (project `cyclometer`); the GitHub Pages workflow was dropped
- [x] 6. App icon in the hero wordmark; two feature sections (Built for the ride, Private by design)
- [x] 7. Verify: build, privacy text parity, screenshots light/dark × desktop/390px, no horizontal scroll

## Review

- Privacy text: tag-stripped diff vs `main:docs/privacy-policy/index.html` is identical; URL unchanged (`/privacy-policy/`).
- Screenshots (Playwright Chromium) at 1440 and 390 wide, light + dark: no horizontal scroll; the hero copy is moved above the rider on narrow screens.
- The hero always uses dark-mode tokens because it sits on a darkened photo. Light-mode links use `primaryDark`, since `primary` on white has too little contrast.
- The live CTA is a styled text button. Apple's official badge host (tools.applemarketingtools.com) didn't resolve from here, so swap in the official badge at launch.
- Cloudflare Pages served `docs/` raw (no build): the preview had `/src/index.njk` at 200 and `/` at 404. Before merge, set Root directory `docs`, Build command `npm run build`, and Build output `_site`.

# #251 — S15 Ride Detail on real ride data, via stack navigation

Plan: /Users/brian/.claude/plans/251-streamed-wren.md
Branch: `feat/251-ride-detail`

- [x] 1. `RideStats` + `PersistenceClient.fetchRideStats` (actor, live, testValue, mock)
- [x] 2. `RideDetailFeature` (+ `RideDetailSeries.heartRate`)
- [x] 3. `RidesFeature` stack (`Path`, `path`, `.forEach`) + `RidesNavigationStack`, AppView
- [x] 4. `RideDetailView` / `RideDetailList<MapRow>` / `RideMapView` on real data
- [x] 5. Delete `PreviewContent/RideDetailData.swift`
- [x] 6. Tests: RideDetailFeature, RideDetailSeries, RidesFeature push, fetchRideStats, snapshots
- [x] 7. UX.md S15 Stub → Complete (+ exclusions note)
- [x] 8. Full local suite green; simulator drive

## Review

- Full local suite: 1226 Swift Testing + 95 XCTest, 0 failures. The only known issues are
  NavigationPipelineTests' deliberate `withKnownIssue`. Existing S14 snapshot references are unchanged.
- Simulator drive (seeded ride through `PersistenceClient.liveValue`, throwaway tests since deleted):
  S14 → S15 push, real track + 2 pass markers (40 mph label; a nil-speed pass has no label), stats
  15.7/25.1 mph, 89/94 rpm, 2 passes, HR chart, back pops. No TCA runtime issues.
- Found by the drive, not the tests: on a loop ride the Finish flag covered Start. Fixed with
  `RouteMapContent`'s loop rule (25 m). The map isn't snapshotted, so there's no automated guard for it.
- Interpretation to confirm: passes are one map marker each labelled with the vehicle's speed, plus
  a count row in Stats (not a per-pass list).
- Not done (per #251 scope): full-screen map sheet, Strava, GPX re-export, Create Route. The HR chart
  is not zone-coloured, although UX.md §S15 says "HR zone graph". That's noted under §S15.
- Issue #251's line references were stale (`RideSummary.recorded` no longer existed).

## Follow-up: HR zones on S15 (Brian, after PR #281 opened)

- HR Profile draws S12's zone bands (`cyHRZone1`–`5` at `Opacity.zoneBand`) behind a `cyTextPrimary`
  line. The y-domain is fitted to the ride ±5 bpm, and only the zones the ride reaches are banded.
  Ticks go at the zone edges crossed (the ride's min/max when it stays in one zone).
- Bounds use `RiderProfile.bounds(for:)` with Health resting + 220 − age (Settings' read).
- Fixed in the same change, at Brian's call: the live `RiderProfile.zone(forBPM:)` ignored S12's pinned
  boundaries (#103) while the table honoured them. It now classifies by the resolved boundaries and is
  identical to Karvonen when nothing is pinned (checked over bpm 0–250 × 6 profiles).
  Mutation-checked: putting Karvonen back fails the pinned-boundary test.
- The revert-check stale-build trap happened again: the restored source still ran mutated. A fresh
  derived-data build passed, and the default build folder was cleaned.
- Full suite: 1232 Swift Testing + 95 XCTest, 0 failures.

---

# #249 — S10 Ride Summary, presented at ride end

Branch `feat/249-ride-summary`. Plan: `~/.claude/plans/rosy-riding-forest.md`.

- [x] 1. Persistence: `renameRide`; `RideStats.routeName`
- [x] 2. `RideTitle.defaultTitle`: route name, otherwise part of day + Loop / Out and Back / Ride
- [x] 3. `RideSummaryFeature`: waits for finalize (shared `RidesFeature.awaitFinalized`), zones from the track
- [x] 4. `RideSummaryView`: artboard structure, "Finish Ride" title + glass button
- [x] 5. AppFeature: `@Presents rideSummary` on confirmFinish; the rename is saved on `.dismiss` (button + swipe)
- [x] 6. Tests: reducer, presentation, RideTitle, zoneSeconds, persistence, snapshots light/dark
- [x] 7. UX.md §S10 + inventory → Complete; stale "#249" comments in S14/S15
- [x] 8. Full local suite green; simulator drive

## Review

- Full local suite: 1518 passed, 0 failed.
- Simulator drive (throwaway XCUITest, since deleted): Start → ride → Pause → Finish → confirm. S10 opens
  and shows finalized numbers once the save lands. Tapping the Name *label* opens the keyboard. After the rename
  and Finish Ride, S14 lists the new name, and it's still there after a relaunch. No new TCA runtime issues (only the known
  onboarding `ifLet` one).
- Found by the drive, not the tests: a 0.1 mi ride was named "Evening Loop". `RideTitle.shape` now requires
  the ride to get more than 250 m from the start before it can be a loop. Test `wentNowhere` added.
- Snapshot trap: `.glassProminent` blanked the whole offscreen capture to white. The S10 suite snapshots
  with `drawHierarchyInKeyWindow: true`. There's no loading-state snapshot, because in a real window the spinner animates.
- `AppFeature` sees S10's state on `.dismiss` (TCA nils it after the parent reduces). The swipe test proves it.
- Deviations from the issue, settled with Brian: zones/elevation come from track points (`Ride.hrZoneDurations`
  and `elevationGainMeters` are never written); the default name is offline only; the labels read "Finish Ride";
  the map is the live `RideMapView`, not the thumbnail.
- Issue text was stale: `RideSummary` (RidesView.swift:262) no longer exists, so there was no collision.
- Follow-up candidates (not filed): (1) reverse-geocoded place in the default name; (2) the unwritten
  `Ride.hrZoneDurations`/`elevationGainMeters`; (3) `ActiveRideFeature.vehiclePassCount` is `Int = 0`, so a
  ride with no radar stores 0, not nil, and S10/S15 show "Vehicle Passes 0" (seen in the drive).
- UX gap, not addressed: the Name field starts filled with the default, so renaming means deleting it first.

# #286 — Rewrite the ride's GPX track name after a rename

Plan: /Users/brian/.claude/plans/cheerful-purring-thacker.md, revised after `/code-review high` (option b)
Branch: `286-gpx-rename-rewrite`

- [x] 1. Ride end names an untitled ride with `RideTitle.defaultTitle` before the export, so the first file already carries the name
- [x] 2. `GPXExporter.fetchInputs` / `generate(_:)` / `rewrite(rideId:)`: one fetch path shared by export and rewrite
- [x] 3. `RidePersistenceActor.replaceGPXFile` + `removeGPXFile`: check and write on the actor, so a rename can't recreate a file a delete just removed
- [x] 4. `AppFeature` dismiss: rename → reload S14 → rewrite (failure logged with the ride id)
- [x] 5. Tests + mutation checks + fresh full suite

## Review

- First version rewrote inside `renameRide`. Review findings: S10 renamed nearly every ride to its default on dismiss, so every ride exported twice; S14 waited behind the rewrite; the fetch pipeline was duplicated; and a rename could recreate a file a concurrent delete had just removed (#261).
- Now the default name is stored before the export, so S10 only renames when the rider actually types a name. The calendar is resolved inside `titleForExport`, so it's read only when a name is made. Twelve ride-end tests that use a live client now pin `$0.calendar`.
- `replaceItemAt` was tested and ruled out for the race: it creates a missing original, just like an atomic write does.
- Mutation checks: dropping the ride-end naming fails the lifecycle test (row + file name); dropping the rewrite fails the dismiss test.
- Suite: 1,535 passed, 0 failed (fresh DerivedData).
- Remaining gap: if the rider types a name and dismisses S10 before finalize lands, the replace finds no URL. That file keeps the default name, not the typed one.
- Declined: patching the file instead of rebuilding it (review finding 6), and a shared test fixture (finding 9).

# #284 — Remove Ride's never-written zone and elevation fields

Plan: /Users/brian/.claude/plans/deep-tinkering-hartmanis.md (decision: remove all three)
Branch: `284-remove-dead-ride-fields`

- [x] 1. `Ride`: drop `elevationGainMeters`, `elevationDropMeters`, `hrZoneDurations` and their `init` assignments
- [x] 2. `RideSchemaMigrationTests`: legacy store carries real values in the dropped columns; new test proves it opens
- [x] 3. DataModel.md §3.1 sketch, §9 migration row, header
- [x] 4. Verify: grep, targeted tests, full suite (fresh DerivedData), main→branch install over an existing store

## Review

- Removed all three (decided with Brian): nothing read them. S10/S15 derive the elevation profile and zone
  seconds from the track, and a stored breakdown would go stale once Health's zones change (#238).
- No migration code. Inferred lightweight migration drops the columns. The legacy fixture now writes real values into all
  three (the transformable dictionary included), and `opensStoreWithRemovedAttributes` proves the store opens.
- Suite: 1,649 passed, 0 failed (fresh DerivedData). Migration suite 5/5, and the new test ran by name.
- Real store: the sim's `default.store` had main's schema (#277 column present) with 2 rides and the three columns.
  After installing the branch build over it, the app launched to S14 with no fatal in the log stream. The columns are gone,
  and both rides keep the same titles and distances. Backup is in the session scratchpad.
- Left alone: PRD.md §10 and TCA.md still sketch `hrZoneDurations`. Both sketches are stale throughout, and the
  issue names only DataModel.md.
