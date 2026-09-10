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
- [x] Full suite ×2: 997/997 on runs B and C (run A recorded S20 and failed only on those 4)
- [x] Simulator: the app installs, launches and stays up (S20 itself is reachable only via the preview
      or a manual GPX import)
- [ ] PR

## Review

**Suite: 997 tests, 0 failures** on two consecutive full local runs, snapshots included. Every new
suite was confirmed by name in both runs' logs. The freshly built app installs and launches clean on
the iPhone 17 Pro simulator (iOS 26) and stays up.

**Navigation was corrected before any code was written.** The issue prescribed S11's plain `Scope`
behind a `NavigationLink`. I first offered three workarounds, and then a view-owned store modelled on
the Rides tab. Brian: use correct TCA patterns, and accept the scope. The Routes tab now owns a
`StackState` path, rows are `NavigationLink(state:)`, and `RoutesNavigationStack` is the one place
that stack is built. Recorded in `tasks/lessons.md`.

**Two of the new reducer tests passed with nothing loaded.** A `TestStore`'s `state` does not advance
past received actions at `finish()`: `TestReducer`'s `.receive` branch records the resulting state
without adopting it (`TestStore.swift:2385-2387`). Asserting straight after `finish()` therefore read
the state from before either load. Four tests failed on it, and two passed without anything having
loaded. Fixed with `skipReceivedActions()`. The "never ridden" test now also asserts that the route
loaded, so it can fail for the right reason.

**`NavigationLink(state:)` outside a store-powered stack is a test failure.** S19's snapshot harness
and previews wrapped `RoutesView` in a bare `NavigationStack`. TCA reports an issue there, and XCTest
records it as a failure. `RoutesNavigationStack` fixed that, and the "Routes — List" preview now
pushes a fully loaded S20.

**The inline title renders white in offscreen snapshots: the harness, not S20.** My first theory, an
unspecified light trait, was wrong; pinning `.light` changed nothing. A three-case ladder settled it:
- a bare inline title rendered offscreen is white
- the same view with a large title is black
- the inline title drawn in the key window is black

S20's references therefore render the list without a navigation bar. Added to the snapshot-toolbar
memory.

**Minor deviations from the plan.**
- The stack tests live in a new `RoutesNavigationTests.swift` instead of being appended to the
  1,100-line `RoutesFeatureTests`.
- `StartSheetPresentationTests.makeStore` gained an `initialState` closure, so `@Shared` state is
  built inside its storage scope.
- `distanceLabel(_:_:)` moved up beside `elevationLabel` so S20 and the filter sheet share one format.
- No M10.6 companion issue was filed, because #204 already exists.

**Not verified automatically.**
- S20's live map (flags, chevrons without panning, the loop collapse) has no pixel coverage.
- The "Use This Route" toolbar button has no pixel coverage either.
- The simulator can't be driven through a Files-app GPX import without UI automation the repo doesn't
  have. The "Routes — List" preview is the one-tap way to look.
- Previous Rides can't populate on a device until #196/#197 write `Ride.routeId`.
