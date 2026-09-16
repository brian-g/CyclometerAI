# tasks/todo.md — #230 [M8] S19 swipe a route row to use it for a new ride

Branch: `feat/230-swipe-use-route` · Plan: `~/.claude/plans/zany-snuggling-flamingo.md`

Spec notes:
- The issue and UX.md §S19 agree. §S19 listed no swipes at all; only the leading one is added, as the issue asks.
- It reuses `Delegate.useRoute`, so `AppFeature` gets no new code path. Its guard only gets a comment update.

## Implementation

- [x] Branch
- [x] `RoutesFeature.Action.useRouteSwiped(RouteReference)` → `.delegate(.useRoute)`
- [x] `RoutesView` leading `.swipeActions`: "Use This Route", `play.fill`, `cyPrimary`, full swipe, hidden while recording
- [x] Doc comments: `Delegate`, `RoutesNavigationStack.isStartRideHidden`, `AppFeature`'s guard
- [x] UX.md §S19 Key Components

## Tests

- [x] `RoutesFeatureTests`: the swipe emits `.delegate(.useRoute(route.reference))`
- [x] `AppRouteSelectionTests`: the swipe opens the sheet on the route with the pairing scan; it's ignored mid-ride

## Verify

- [x] Build + full `CyclometerTests` green locally (`** TEST SUCCEEDED **`), re-run after Brian's "Use Route" rename —
  no snapshot reference moved. The three new tests pass by name.
- [x] Live sim (throwaway XCUITest, since deleted), three of the four rider-facing criteria:
  - The leading swipe reveals a green "Use Route" with `play.fill`
  - Tapping it opens the Start sheet with **Route: Swipe Seed 230**
  - The trailing red Delete is unchanged
- [ ] Live sim, **no leading action mid-ride: not driven** — stopped at Brian's request. Three attempts never got back to
  the Routes tab while recording: the dashboard is a sheet over the tabs, so `Open` and `tabBars.buttons["Routes"]`
  both exist (and report hittable) while it still covers them, and the tap lands on the sheet. Covered by
  `AppRouteSelectionTests.swipeIsIgnoredDuringARide` and by the same `isStartRideHidden` flag that already hides
  S19's Start Ride and S20's CTA.
- [x] PR

Note: Brian renamed the CTA to **"Use Route"** mid-task, in `RoutesView` (this swipe) and `RouteDetailView` (S20).
UX.md §S20's "Use This Route" line and a few comments elsewhere still use the old wording — left alone, not this issue.
