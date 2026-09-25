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
