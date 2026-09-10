# tasks/todo.md — #195 S20 Route Detail

Branch: `feat/195-route-detail` · Milestone M8 · Plan:
`~/.claude/plans/zesty-forging-sifakis.md`

## Geometry

- [x] `RouteGeometry.elevationProfile(_:sampleCount:)` + `RouteGeometryTests` (21/21)

## Feature

- [x] `Features/Routes/RouteDetailFeature.swift` + `RouteDetailFeatureTests`
- [x] `RoutesFeature`: `Path` stack, `.forEach`, `Delegate.useRoute`, plus `RoutesNavigationTests`
- [x] `RoutesNavigationStack`: one store-powered stack for AppView, the previews and the S19 snapshots
- [x] `AppFeature`: `activeRoute`, `presentStartSheet`, one-shot clears, plus `AppRouteSelectionTests` (4/4)
- [x] `RouteSummary.reference`

## UI

- [x] `Features/Routes/RouteDetailView.swift`: map, sections, toolbar CTA, `RouteDetailList<MapRow>` seam
- [x] `RoutesView`: `NavigationLink(state:)` rows, prototype removed, doc comments updated
- [x] `ElevationProfileView` `unitLabel`
- [x] Stub removal: `RouteSegmentStub` → `RideDetailData.swift`, delete `RouteDemoData.swift`
- [x] `RoutePreviewData`: `RouteRideSummary` fixtures

## Snapshots

- [x] `RouteDetailSnapshotTests` (elevation ± × rides ±, light/dark) + CI skip-list; 8 references, none blank
- [x] Re-record `RoutesSnapshotTests` populated/filtered, inspect PNGs (chevrons only)

## Verify

- [x] Delete `InlineTitleLadderTests` and its references (throwaway)
- [ ] Full suite ×2 (run A recorded S20: 997 tests, only the 4 recording failures)
- [ ] Simulator: the app launches (S20 itself is reachable only via the preview or a manual GPX import)
- [ ] PR

## Review
