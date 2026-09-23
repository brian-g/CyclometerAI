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
