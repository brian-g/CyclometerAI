# #330 — Larger grab targets: dashboard grabber + map sheet

Plan: /Users/brian/.claude/plans/harmonic-waddling-heron.md
Branch: `fix/330-grabber-target`

- [x] 0. Lesson (a code comment isn't evidence of render position) + fix the simulator-ui-drive memory
- [x] 1. Dashboard: 120×52 centred drag target overlaid under the capsule; capsule, footprint and banner unmoved; stale comments fixed
- [x] 2. Map sheet: gesture-less 52pt band across the top, under the controls, so drags reach the sheet's own dismiss pan
- [x] 3. `Spacing.grabberHitWidth` + UX.md §S05 Grabber sentence
- [x] 4. Unit suite green
- [x] 5. Sim drive (throwaway XCUITest, deleted)

## Review

- The capsule was already below the Dynamic Island (Brian's screenshot). The comment claiming it sat at the physical top was stale. The real defect was an 8pt drag target.
- Sim-verified: a drag starting 30pt below the capsule minimises the ride. A tap on the Speed widget's top-left, outside the band, still opens its detail.
- Map sheet: a drag starting on the system grabber itself (100×24) already dismissed without the band. A drag at (100, 95), inside the band but off the grabber, dismisses **with** the band and pans the map **without** it. Both builds were checked, fresh derived data.
- Not driven: a banner showing at the same time. Its position can't change, because the band is an overlay and the grabber's layout footprint is unchanged. The `zIndex` keeps the band above it.
- Not verified: finger feel on a device.

### Follow-up: drag feel (Brian's report) — moved to #333
- The squish, the jump under the island, square corners, a slow finish, and expand/collapse into the capsule are all in #333. Brian chose the system zoom transition with drag-anywhere dismiss.
- A draw-only offset, then fixed insets fed from `AppView`, were both tried here. The first changed nothing; the second still squished on device and once froze the app. Both reverted. #330 keeps no safe-area changes.
- Kept in #330: the flick fix. Dismissal uses `predictedEndTranslation`, measured in `.global` space; in local space the moving view made the predicted end come out short, so neither a flick nor a long drag dismissed. Sim drive: a slow 356pt drag minimises, an 80pt flick minimises, a short slow 60pt drag springs back. Unit suite 1661/0.

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

# #333 — Dashboard zooms from and into the ride capsule; auto-dim owns the whole window

Plan: /Users/brian/.claude/plans/harmonic-waddling-heron.md (decision: dim rules cover the whole window)
Branch: `feat/333-dashboard-zoom`

- [x] 1. Spike: zoom cover in AppView; sim drive checks zoom, no squish, sheet→cover and cover→summary, paging
- [x] 2. Dashboard: drop the hand-built drag, `onClose`, the #330 band, `grabberHitWidth`, `DashboardDismissTests`
- [x] 3. Auto-dim: window touch recognizer + blocker window; `touchBegan`/`touchEnded`/`wakeTapped`; `isTouchDown` guards
- [x] 4. Tests: AppScreenPowerTests (touch held, dimmed touches, race), WakeTapTests
- [x] 5. Docs: UX.md §S05 Grabber, #110 dim rule text
- [ ] 6. Verify: suite, sim drive (presentation + dim rules), device check by Brian

## Review

- Presentation: the dashboard is a `.fullScreenCover(item:)` with `.navigationTransition(.zoom)`, sourced from the tab accessory. The hand-built drag, the `.move` transition, the #330 band, `grabberHitWidth` and `DashboardDismissTests` are gone. The capsule stays as a cue, and VoiceOver's "Minimize Ride" calls `dismiss()`.
- Spike on the sim (frames at 0.25s):
  - the card scales uniformly with display corners and clips to the capsule on the way in; nothing re-lays out;
  - start sheet → cover lands; Finish → cover out, summary in, lands;
  - a page swipe pages without dismissing;
  - a slow drag, and flicks up to 250pt at 1500 px/s, collapse; a 60pt slow drag springs back;
  - synthesized flicks at ≥2500 px/s never start the system dismiss (no motion in any frame), so real flicks need the device check.
- Auto-dim: `AutoDimWindowBridge` puts a non-recognizing touch recognizer on the app window and a blocker `UIWindow` above it while dimmed.
  - Reducer: `touchBegan` cancels the countdown, `touchEnded` re-arms it, and `wakeTapped` (renamed from `userInteracted`) is the only wake.
  - `isTouchDown` guards arming, the timer firing and the brightness-read commit.
- Sim drive of the dim rules, with a location feed so the ride stays active. Every assertion passed:
  - a finger held for 34s plus a small drag: no dim, and it dimmed 30s after the lift;
  - dimmed: a long drag down, a 1.5s press and a sideways swipe left it dimmed, and after the wake the dashboard was still up on page 1;
  - a tap on Speed only woke the screen; no detail opened;
  - dimmed over the open map sheet: a drag neither woke it nor panned the map; a tap woke it and the sheet stayed open;
  - status bar and home indicator unchanged while the blocker shows.
- Suite: 1,668 passed, 0 failed. Mutation check: dropping the touch-down rules fails `heldTouchNeverDims`, `fingerDownBlocksAnInFlightDim` and `visibleUnderAFingerWaitsForTheLift`.
- Open for Brian's device check:
  - flick feel;
  - no resize at the island or the controls;
  - whether a whole-screen drag causes accidental minimises mid-ride (the #333 exclusion's revisit trigger).
- Added scope: the accessory's Open button is gone, and the whole strip is a plain-style `Button` with a `contentShape` over the Spacer's gap. Its five snapshots were re-recorded; apart from Open, the strip is unchanged (diffed by eye). Sim drive: collapse, then a tap on the strip's empty right side (where Open was) reopened the dashboard.
- Brian spread the strip's stats with Spacers, and I re-recorded its five snapshots to match. Added a "Collapsed (inline)" preview. Because `tabViewBottomAccessoryPlacement` is get-only, the strip moved into a private `AccessoryStrip(isCollapsed:)`, which the public view feeds from the environment.
- Review (xhigh) items 1–6 applied:
  - the backlight read runs under `CancelID.dimTimer`, so a tap mid-read cancels the dim (mutation-checked), and the `!isTouchDown` re-checks on the fire and capture steps are gone;
  - `touchEnded` while dimmed wakes, as a safety net if the blocker ever fails;
  - VoiceOver focus moves onto the blocker (`.screenChanged`);
  - `super` calls added in the recognizer;
  - stale S05.3, PRD and AppFeature text fixed;
  - `AccessoryStrip` replaced by `isCollapsedOverride`, plus a collapsed snapshot.
- PR comment: the dashboard reopens on the page it was left on. `dashboardPage` now lives in `ActiveRideFeature.State` (per ride), tested in `reopeningKeepsThePage`.
- PR comment: "dimming not working". Not reproduced on the sim: a ride started and left alone dimmed at 30s with Pause showing. The suspect on device is auto-pause (0 GPS speed for 10s), and paused rides never dim (#102). Waiting on Brian: was Pause or Resume showing?

# #141 — S07 Dashboard customization edit mode

Plan: /Users/brian/.claude/plans/rustling-mapping-pancake.md
Branch: `feat/141-dashboard-edit-mode`

- [x] 1. Model: `DashboardPage.id` (hand-decoded), `keepingValidPlacements`, `removingWidget`, `appendingBlankPage`, `prunedEmptyPages`; decode prunes
- [x] 2. Model tests (DashboardLayoutTests, AppPreferencesTests)
- [x] 3. Reducer: `isEditingDashboard`, long press / remove / Done, one validated write path, pruned getter outside edit mode
- [x] 4. Reducer tests (TestStore)
- [x] 5. Views: page ids in TabView, Add (disabled) / Done row, collapse blocked, edit chrome (0.90, glass, minus, wiggle / reduce motion), widgetDetail gate, widget `title`
- [x] 6. Edit-chrome snapshot (look at the PNG)
- [x] 7. Unit suite green; new tests confirmed in the log
- [x] 8. Sim drive: long press (widget, map, empty cell), remove, Done, drag-down blocked

## Review

- **Sketch S07** was read over HTTP (this session's MCP client connected before Sketch started). Add `plus` / Done `checkmark` sit beside the Dynamic Island, and the grid doesn't move. So the controls take the **status bar's band**, and the status bar is hidden while editing. This replaced the plan's "swap the grabber" row: a top-row widget's remove button lands just below the island, exactly where that row would have been.
- **Buttons:** `MapSheetButton` (exact 44 pt glass circle), not `rideControlButton`. `.buttonStyle(.glass)` pads past its frame to about 66 pt and overfilled the 62 pt band. `MapSheetButton` now reads `isEnabled` so the disabled Add greys out; its other callers are always enabled, so they are unchanged.
- **Equality includes `DashboardPage.id`.** Tests that compared a decoded layout with freshly built pages now compare `placements`. The blank page's id comes from `@Dependency(\.uuid)`, so TestStore can predict it.
- **The wiggle is split from the frame** (`dashboardWiggle` / `dashboardEditFrame`). `accessibilityReduceMotion` can't be set from a test, and a time-driven angle can't be snapshotted.
- **Unit suite:** 1735 passed, 0 failed. The new suites were confirmed in the log by name.
- **Snapshots** recorded and looked at: frame and button render in light and dark; off mode adds nothing. The first recording run crashed in SnapshotTesting's `prepareView` with no key window yet (a cold clone, with a key-window snapshot as the first test). That is a harness race; reruns were clean.
- **Sim drive** (three runs, throwaway test deleted):
  - long press enters edit mode from the Speed widget, the map and an empty cell, and no sheet opens;
  - a tap in edit mode opens nothing;
  - a slow drag down doesn't minimise;
  - Remove Heart Rate works;
  - the 4th blank page shows and is pruned on Done, leaving "Page 3 of 3";
  - `app-preferences.json` on the device shows HR gone from page 1 and 3 pages.
- **Not done:**
  - Finger feel of the wiggle and the long press on a device.
  - The minus glyph still overlaps the first letter of a widget's label, SpringBoard style. A tuning call for Brian.

### Follow-up: Brian's review (2026-10-01)
1. **"Bouncing" in a removed widget's space.** A burst of screenshots showed the removal itself is instant. What moved was the neighbours' glass frames: their rims and shadows spill past their cells, and they swung at a fixed 1°.
   - Fix: the wiggle now gives every widget the same 1.5 pt corner travel, with the angle derived from its size via `visualEffect`.
   - Fix: cards replace glass (item 3).
2. **Minus buttons.**
   - Red `cyDestructive` with a `cyTextInverted` minus, at `.title2`. The `.title` size was too big.
   - Centred on the card's top-left corner.
   - Widgets draw in reading order, so a button that overhangs into its neighbours sits on top of them. Sim-verified by tapping HR Zones' remove button, which overhangs Cadence.
   - The buttons stay outside the wiggle. Measured across 8 frames: the button centre held at exactly (59.0, 852.8) px while the card edge moved between 816 and 818 px.
3. **Frame.** Three variants were rendered on the simulator (launch-argument switches, all removed). Brian picked hairline `cyBorderStrong` cards.
4. **Add/Done.**
   - Glass capsules `Spacing.dynamicIsland` (37 pt) tall and φ as wide, with the hit area padded to 44 pt.
   - Done is tinted `cyPrimary`. That style was my pick, since Brian gave only the geometry.
   - Vertical centre checked against the status-bar clock, which iOS centres on the island: within about 1 pt.
   - `MapSheetButton` is back to main's version.
- **Snapshot suite.** It now renders offscreen, because nothing in it is glass any more. In the key window it lost its top padding and clipped the buttons. This also removes the cold-start `prepareView` trap.
- **Unit suite:** 1735 passed, 0 failed.

### Follow-up: PR #364 review + /code-review xhigh (2026-10-02)
- [x] PR: map bleed cut by the card clip outside edit mode — clip only while editing
- [x] PR: scale 1-column 90%, 2-column 95% (card + remove button in step); 2-wide snapshot
- [x] PR: edit-mode preview, driven through the reducer
- [x] PR: Add/Done inset `Spacing.xl` (Brian's change, kept)
- [x] Factory comparison by placements, not page ids (setter + decode)
- [x] Done always writes a valid `dashboardPage`; prune explicitly, not via the getter's flag
- [x] Banner never takes touches (covered top-row remove buttons in edit mode)
- [x] Lossy placement decode: an undecodable placement costs only itself
- [x] Validator rejects duplicate page ids
- [x] Enter/leave edit mode animate (send with animation)
- [x] Long press over the radar lane too; VoiceOver "Edit Dashboard" action
- [x] Add/Done band never 0 pt tall (no-island devices)

**Review notes**
- **Map bleed.** The card's `clipShape` clipped every widget, even outside edit mode, at the safe-area-inset frame. W8 draws its bleed past that frame. Now a `mask` clips to the card only while editing, and otherwise ignores the safe area. Sim-verified on page 1 (bottom map) and page 2 (top map), before edit mode and after Done.
- **Factory matching** uses `DashboardLayout.isFactory` (placements only) in the setter and on decode. The other fix considered was fixed UUID literals on the factory pages. That alone would leave a decoded factory copy pinning the rider until their next edit.
- **Not changed: one `TimelineView` per widget while editing.** Its closure only applies `visualEffect` rotation to a content placeholder, so widget bodies aren't re-evaluated each frame. Edit mode is also a short, deliberate state. Revisit if a device trace shows a cost.
- **Unit suite:** 1740 passed, 0 failed. The 5 new tests were confirmed in the log by name. Snapshots re-recorded and looked at; the 2×1 card's sides line up with the 1×1s above it.

# #142 — S08 Add Widget sheet

Plan: /Users/brian/.claude/plans/fuzzy-snacking-phoenix.md
Branch: `feat/142-add-widget-sheet`

- [x] 1. Model: `firstOpenPlacement`, `addingWidget`, `insertingBlankPage` + tests
- [x] 2. `WidgetCategory` + `category` on each widget
- [x] 3. Reducer: present / select / empty page + tests
- [x] 4. `AddWidgetSheet` (sections, scaled previews, sample store) + entry-order test + snapshot
- [x] 5. Wire Add button + sheet in `RideDashboardView`
- [x] 6. Docs: UX.md §S08 as built, TCA.md §8
- [x] 6b. Follow-ups filed: #368 (tap an empty cell to add), #367 (rearrange by drag; no issue had picked up UX.md §S05 item 2)
- [x] 7. Unit suite green; sim drive

## Review

- Unit suite: 1754 passed, 0 failed (the one expected failure is the deliberate `withKnownIssue`). The new cases are in the log by name.
- Snapshot `testAddWidgetCatalog` light/dark recorded and inspected. The first recording had a 2×2 narrower than the content and uneven row gaps, because a fixed-height frame squeezed `.fit`. The sheet scrolls, so the test now uses a `ScrollView` too. Cadence's sample AVG/MAX were blank, so the sample now sets them.
- Sim drive (throwaway XCUITest, deleted):
  - Full factory page 1: every entry dimmed, Empty page live.
  - Empty page inserts page 2 and moves to it.
  - HR 1×1 lands at (0,0), Speed 2×2 at rows 1–2.
  - Done prunes the trailing blank and stays on page 2.
- Only runtime warning: the known onboarding `ifLet` (`deviceManagement(.onDisappear)`).
- Not done: UX.md's screen table still says Stub for S08, as it does for the built S07. The status column doesn't track builds.
- Follow-up (Brian): removed S07's auto-appended blank page. New pages now come only from Empty page (UX.md §S05 item 5). Entering edit mode still saves the layout as shown, so empty pages a ride left behind mid-edit don't come back and shift the page index. `appendingBlankPage` and its test are deleted, and the edit-mode tests are rewritten without the page. The Empty page icon is now `text.rectangle.page`, the mockup's glyph; snapshot re-recorded and checked. Unit suite 1753/0.
- /code-review xhigh fixes:
  - The snapshot now uses imperial units, so it no longer depends on the machine's locale.
  - Finish closes the Add Widget sheet, so auto-end's alert can show.
  - Done after an unused Empty page returns to the page it was inserted from, not the next one.
  - Empty page row: full width, 52 pt tall.
  - Previews subtract the radar lane from their width.
  - A zero canvas renders nothing instead of scaling by ∞.
  - `presentationChanged(true)` only opens the picker in edit mode.
  - `setDashboardLayout` returns Bool, so a refused save doesn't move the rider or close the sheet.
  - The Xcode preview opens the picker.
  - Skipped as cleanups: the duplicate grid scan, the sample store being built per render, and sharing the card styling.
  - Unit suite 1754/0.

# #368 — S08: tap an empty cell to add a widget there

Plan: /Users/brian/.claude/plans/twinkly-pondering-graham.md
Branch: `feat/368-tap-empty-cell`

- [x] 1. Model: `emptyCells`, `fits(_:at:)`, `openPlacement(…at:)`, `addingWidget(…at:)` + tests
- [x] 2. Grid layout key carries cell + size; `dashboardPlacement(at:size:)`
- [x] 3. Reducer: `addWidgetCell`, `emptyCellTapped`, select/Empty page/close paths + TestStore tests
- [x] 4. Sheet: catalog `cell` filter, Page section hidden (filter is `page.fits`, tested in the model; `entries(in:)` unchanged)
- [x] 5. `DashboardEmptySlot` (dashed 90% card, VoiceOver) in `DashboardPageView` + snapshot
- [x] 6. Docs: UX.md §S05 Empty cells, §S08 as built
- [x] 7. Unit suite green; sim drive

## Review

- Unit suite: 1762 passed, 0 failed. The 9 new cases are in the log by name: 4 model, 4 `TestStore`, 1 snapshot.
- Snapshot `testDashboardEditChromeEmptySlot` was recorded in light and dark and checked: the dashed slot matches the 1×1 card's size and inset.
- Sim drive (throwaway XCUITest, deleted) passed. It covered:
  - Removing Pace leaves a "row 5, left" slot. The sheet from it lists only 1×1s, with no Page section, and dims widgets already on the page.
  - Pace lands back at its cell.
  - A right-column cell offers no 2×1.
  - Row 1 left, under the Add/Done band, offers a 2×2. Speed 2×1 lands at row 1.
  - The row 7 right slot opens the sheet even with the ride controls over that row.
  - Add still shows Empty page, and puts Map 2×2 in the first open spot (rows 6–7).
  - Done leaves no slots.
- Design choice: the grid's layout key now carries cell + size, not a `WidgetPlacement`, so slots and widgets share one frame calculation and no dummy widget id is needed.
- Not done: no runtime-issue log stream was captured during the drive. No device check.
- /code-review high --fix: applied 5 fixes. Full unit suite 1762/0 after them.
  - The cell stays set as the sheet closes, so it doesn't redraw as Add's sheet while sliding away.
  - `emptyCellTapped` carries `pageID`.
  - `firstOpenPlacement` reuses `openPlacement(at:)`.
  - `fits` is derived from `emptyCells`.
  - Fixed the plan's view name.
- Skipped from the review:
  - The single-enum sheet target: it would rework the #142 binding.
  - Computing the placement twice: the existing #142 pattern.
  - Gating the slot `ForEach`: at most 14 cells.
  - The UX.md "contradiction": a misread. A 1×1 gap does show only 1×1s.

# #367 — S07 rearrange widgets by drag (move to empty spot, swap same size)

Plan: /Users/brian/.claude/plans/proud-whistling-pearl.md
Branch: `feat/367-drag-rearrange`

- [x] 1. Model: `DashboardPage.moving`, `DashboardLayout.movingWidget`, `DashboardGrid.Direction`, `moveTarget`, `DashboardGrid.cell(nearest:in:)` + tests
- [x] 2. Reducer: `moveWidget(pageID:widgetID:to:)` + TestStore tests
- [x] 3. View: `DashboardWidgetCell` (lift gesture, offset/zIndex, edit-mode a11y element + Move actions); wiggle `isHeld`
- [x] 4. UX.md §S07 "As built (#367)" + Updated line
- [x] 5. Unit suite green (new tests confirmed present in log)
- [x] 6. Sim drive (throwaway XCUITest, deleted): move, swap, refused, page swipe, remove, persistence
- [x] 7. VoiceOver: card labels found by the sim drive; Move actions covered by `moveTarget` tests only (see Review)

## Review

- **Gesture, changed during the work.** The planned SwiftUI `LongPressGesture.sequenced(before: DragGesture)` blocked paging. A sim probe showed a swipe starting on a widget didn't page in edit mode, though one starting on an empty slot did; with the gesture disabled, the widget swipe paged again. I switched to the plan's contingency, `UILongPressGestureRecognizer` via `UIGestureRecognizerRepresentable` (`DashboardLiftGesture`). The probe then paged from a widget, an empty slot and the centre.
- **Sim drive** (fresh install, throwaway XCUITest, deleted) passed end to end:
  - long press enters edit mode;
  - a horizontal hold-drag swaps Heart Rate and HR Zones, and the page stays 1;
  - a 1×1 onto Cadence's 2×1 springs back;
  - Remove Directions removes;
  - a diagonal drag moves HR Zones into the gap;
  - a swipe pages;
  - on page 2, Pace moves into the empty last row;
  - after Done and a relaunch, all three moves are kept.
- **Unit suite:** 1770 passed, 0 failed. All 8 new tests are confirmed in the log, and the edit-chrome snapshots are unchanged.
- **Not verified:**
  - VoiceOver Move actions weren't performed, because XCUITest can't invoke custom actions. Their targets are covered by `moveTarget` tests; the labels were found on the sim.
  - Drag feel on a device: the 0.25 s hold, the 5% lift, and the spring.

# #373 — BLE reconnect tests stall on CI

Plan: /Users/brian/.claude/plans/prancy-dreaming-yao.md
Branch: `fix/373-ble-reconnect-tests`

- [x] 1. Find the real cause from CI run 37083342499's log
- [x] 2. `SteppedClock`: no yields, wakes the sleeper directly, `advanceToNextSleep()` returns the step length
- [x] 3. Swap both BLE harnesses to it; ladder steps assert their length; recovery checks assert `clock.isIdle`
- [x] 4. Revert checks, 20 iterations, full suite
- [ ] 5. CI: the three tests under 2 s, the CSC live suite under 10 s

## Review

- **The issue's cause was wrong.** There was no late-sleeper race; that would hang the test forever, not slow it down. `Task.megaYield()` runs each of its 20 yields as a detached `.background` task and waits for it. `TestClock.advance` does at least 3 megaYields, so the 10-step ladder was about 600 background hops. The CI VM throttles background QoS, so each advance took 10–30 s. Locally, under the same CI-style serial run, the test took 0.008 s. The test, event-loop and reconnect tasks were measured at priority 25, so only megaYield's own tasks were throttled.
- **A check I nearly weakened:** the "+120 s, nothing reconnects" checks relied on `TestClock`'s yields after waking. Without them, removing the client's cancel-on-success still passed. Fix: in the two recovery tests the check is now `clock.isIdle`, which is deterministic because both clients cancel before publishing `.connected`. With the cancel removed they fail 3/3. The three user-disconnect checks assert that a task is *never* spawned, which no clock can make deterministic, so they keep `advance(by:)` + yields as before, at the caller's priority.
- Revert checks: a wrong ladder value fails at once (`:776`).
- Results: both suites green over 20 iterations, 1360/0. Full CI-style suite 1488/0 in 37 s.
# #361 — VoiceOver: every tappable widget is one button

Plan: /Users/brian/.claude/plans/prancy-dreaming-yao.md
Branch: `feat/361-widget-voiceover-buttons`

- [x] 1. `.widgetDetail(label:value:)`: grouping, label/value, `.isButton` (not in edit mode), explicit default action
- [x] 2. Map, Cadence, Speed pass their summaries; Directions drops its hand-rolled modifiers
- [x] 3. UX.md §S05 sentence
- [x] 4. Spoken-text unit tests
- [x] 5. Tree shape + activation test (in-process, via the automation switch; no XCUITest needed)
- [x] 6. Full unit suite green, snapshots unchanged

## Review

- The modifier owns grouping, label/value, trait and the default action. `label` is required, so a widget can't adopt the tap without saying what VoiceOver reads.
- Before this change, **Map had no accessibility element at all**, not just a missing trait. Cadence, Speed and Directions came out as loose texts (revert check).
- Found by the tests: `accessibilityAddTraits([])` in edit mode still left `.button`. SwiftUI infers the trait from the tap gesture and the action, so edit mode now removes it explicitly.
- SwiftUI builds no accessibility tree in a unit test. The tests turn on libAccessibility's automation switch (`_AXSSetAutomationEnabled`, private, test target only), and the suite is `.serialized` because the switch is process-wide.
- Directions' spoken text moved "Directions" into the label: "No turn ahead" replaces "Directions, no turn ahead".
- Full suite 1780/0. The 28 widget/edit-chrome snapshot tests ran, and no reference changed.
- Not verified: VoiceOver on a device. In-process `accessibilityActivate()` is the same entry point VoiceOver uses, but nobody has listened to it.

### Follow-up: /code-review high (findings 1–4 applied)
- The test host's automation switch is counted, not a flag, and its window is shown but never made key, so other suites running during `settle()` don't find it.
- Labels come from the catalog (`CadenceDashboardWidget.title` and the rest), the same names #367's edit-mode card reads.
- The element test also checks `accessibilityValue`. Revert check: removing `.accessibilityValue(value)` fails Cadence, Speed and Directions.
- Units are spoken in words through new `UnitSystem.spokenSpeed`, `spokenDistance` and `spokenTurnDistance`. The turn distance shares its rounding with `turnDistance`.
- Not applied: the Speed badge/trend, the Directions 1×1 wording, the edit-mode trait guard, the formatting cost, localization, locale pinning (see the PR thread).
- Full suite 1793/0, snapshots unchanged.

# #372 — CI stops rebuilding SPM dependencies on every run

Plan: /Users/brian/.claude/plans/prancy-dreaming-yao.md
Branch: `ci/372-dependency-build`

- [x] 1. Prebuilt swift-syntax: measured, doesn't apply (xcodebuild still compiles it for the macro host)
- [x] 2. `ARCHS=arm64`: a clean build goes from 1,926 to 1,523 units, 0 x86_64
- [x] 3. DerivedData cache: survives a fresh checkout locally (326 units, 0 packages)
- [x] 4. CI cold + warm runs (37156042525 attempts 1–2)

## Review

- The cache works: the warm run compiled 302 units, none from packages. Restore takes ~22 s, ~800 MB.
- **The wall-clock win is unproven.**
  - Cold took 16.1 min and warm 19.4 min, but the runners differed 1.7× on identical tests (144 s vs 250 s).
  - Relative to each machine's own speed, the warm build was ~15% faster.
  - Package targets compiled in parallel; the app and test modules are the serial path.
- Brian chose to ship both. The measured numbers are in the `tests.yml` comment.
- Untouched fixed costs, now about half the build step:
  - ~2 min of xcodebuild startup;
  - ~1 min re-resolving packages, which "Resolve SPM dependencies" had already done;
  - 1–3 min regenerating SDK stat caches every run.

  These are candidates for a follow-up.

# #374 — CI boots the simulator during the build; skips docs-only pushes

Plan: /Users/brian/.claude/plans/prancy-dreaming-yao.md
Branch: `ci/374-sim-boot-docs-skip`

- [x] 1. `resolve-simulator.sh` starts the boot in the background (`simctl boot` itself blocked ~2 min)
- [x] 2. "Resolve a simulator" moved first; test step split into build-for-testing, wait, test-without-building
- [x] 3. `paths-ignore` for assets/, tasks/, .claude/, **/*.md on both triggers, with the required-check caveat
- [ ] 4. CI run: simulator step under 15 s, wait step a few seconds, green
- [ ] 5. First docs-only change after merge starts no Tests run
- [x] 6. First CI run (37160465778): simulator step 3 s, wait 1 s, but red on a flaky HR test
- [x] 7. HR flake fixed: `unexpectedDropReadmitsOnlyThePairedStrap` checked the rescan straight after the status flip, but the client publishes `false` before calling `startScanning`. Now `expectEventually`, the repo's helper for exactly this; 20 iterations green
- [x] 8. `-collect-test-diagnostics never` in CI: the failing run spent 10 min gathering diagnostics after the tests ended, two minutes short of the timeout
