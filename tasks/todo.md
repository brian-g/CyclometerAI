# Coming-soon site (11ty) in docs/

Plan: /Users/brian/.claude/plans/luminous-stargazing-lynx.md
Branch: `site/coming-soon`

- [x] 1. 11ty scaffold in `docs/` (package.json, eleventy.config.js, src/)
- [x] 2. Shared layout, home hero (coming-soon / App Store CTA switch), privacy policy migrated verbatim
- [x] 3. site.css on colors.md tokens, light + dark; system-ui → Open Sans → sans-serif
- [x] 4. Hero photo (Unsplash, Viktor Bystrov) at 1600/2400w; favicon + apple-touch-icon from Cyclometer.icon layers
- [x] 5. `.github/workflows/pages.yml` (PR build, main build + deploy)
- [x] 6. Verify: build, privacy text parity, screenshots light/dark × desktop/390px, no horizontal scroll

## Review

- Privacy text: tag-stripped diff vs `main:docs/privacy-policy/index.html` is identical; URL unchanged (`/privacy-policy/`).
- Screenshots (Playwright Chromium) at 1440 and 390 wide, light + dark: no horizontal scroll; the hero copy is moved above the rider on narrow screens.
- The hero always uses dark-mode tokens because it sits on a darkened photo. Light-mode links use `primaryDark`, since `primary` on white has too little contrast.
- The live CTA is a styled text button. Apple's official badge host (tools.applemarketingtools.com) didn't resolve from here, so swap in the official badge at launch.
- Manual: Settings → Pages → Source "GitHub Actions"; custom domain cyclometer.app + HTTPS; apex DNS → GitHub Pages.

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
