# tasks/todo.md — #201 [M8] Unit tests: the navigation pipeline end to end

Branch: `feat/201-navigation-pipeline-tests` (off `main`, not stacked on #231) · Plan: `~/.claude/plans/hazy-cooking-piglet.md`

Decisions:
- A checked-in `.gpx` fixture, not a generated one.
- "S20 doesn't resurrect a deleted route" means a re-import of the same file (new id) has an empty Previous Rides.

## Implementation

- [x] Branch
- [x] `NavigationPipeline.gpx` fixture; confirm it is bundled in `CyclometerTests.xctest`
- [x] `RouteFixtures` polyline walker (`point(alongPolyline:)`, `bearing(alongPolyline:)`)
- [x] `NavigationPipelineTests` harness: live on-disk store, AppFeature store, import → S20 → start
- [x] 1. File on disk → turn tones within ±10 m (20/30/40 km/h)
- [x] 2. Off route within 5 s, clears on rejoin
- [x] 3. No-route ride never touches navigation
- [x] 4. Never-joined route: off route, no turns
- [x] 5. Deleted route keeps routeName; re-import has no history
- [x] 6. Killed mid-route ride relaunches still navigating

## Verify

- [x] Suite alone: 8 cases counted
- [x] Mutation checks bite (approved temp edits, fresh build)
- [x] Full `CyclometerTests` green, count = main + 8
- [ ] PR

## Review

- The suite alone passes: 6 tests, 8 cases (the turn test runs at 20/30/40 km/h).
- Full local `CyclometerTests` is green: 1,051 Swift Testing tests in 99 suites (+6 on `main`), and 89 XCTest cases, 0 failures.
- Mutation checks each failed only the test that should catch them. Each ran on its own `-derivedDataPath` with `COMPILATION_CACHE_ENABLE_CACHING=NO`, and the source was restored after (clean `git diff`):
  - Announce at the first fix inside the lead distance → only the ±10 m test fails.
  - `offRouteConsecutiveFixes = 8` → only the off-route test fails.
  - `State(resuming:)` drops `routeProgressMeters` → only the relaunch test fails.
- **Lesson (first run):** `ActiveRideFeature` forwards a fix to navigation as an effect. Reading navigation state right after `store.send` saw the *previous* fix, which is 11 m late at 40 km/h. `ride(...)` now does `receive(\.activeRide.navigation.locationUpdated)` while a route is being followed.
- No production code changed. The fixture's street names are Winston-Salem streets, but the geometry is synthetic (straight legs, 10 m points).
