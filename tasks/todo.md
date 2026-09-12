# tasks/todo.md — #197 NavigationFeature: route following, turn firing, off-route

Branch: `feat/197-navigation-feature` · Milestone M8 · Plan:
`~/.claude/plans/immutable-sauteeing-eich.md`

Decision: a resumed ride finds its place from `Ride.routeProgressMeters`, saved at each checkpoint.

## 1. RouteGeometry

- [x] Per-segment projection kernel extracted; result is a `Projection` with `segmentIndex`
- [x] `projection(…, alongRoute:, heading:)` window (binary search over `cumulative`); `nil`/`nil` = today's behaviour
- [x] `firstPass(of:onto:cumulative:fromMeters:within:heading:)`
- [x] `RouteGeometryTests`: window, whole-route window = no window, off-route window, firstPass earliest/floor/nearest/nil, course picks the leg, 89°/91° boundary

## 2. NavigationFeature

- [x] `Features/ActiveRide/NavigationFeature.swift`: constants, `NavigationRoute`, State, actions, per-fix logic, banner timer, logging
- [x] `CyclometerTests/Models/RouteFixtures.swift` (walker moved from `TurnDerivationTests.path(legs:)`) + `point`, `bearing`, `fix`
- [x] `NavigationFeatureTests` (20 tests, sweep ×12): timing, lead preference, multi-turn, banner, out-and-back, early turnaround, off-route ×4, never-joined, detour, route end, no-route ×2, load ×2, resume ×2

## 3. Persistence for resume

- [x] `RideSummaryUpdate.route` (read-back only) + `routeProgressMeters`
- [x] `Ride.routeProgressMeters`, `summarySnapshot`, `apply`
- [x] `PersistenceClientTests` round-trip; a checkpoint never erases the route; free ride has neither
- [x] `RideSchemaMigrationTests`: legacy ride reads `routeProgressMeters == nil`

## 4. ActiveRideFeature wiring

- [x] `navigation` state/action; navigation `Scope` gets its own `.onChange(of: \.isCalibrationSuspended)`
- [x] `.task` loads the route; `.locationUpdated` forwards only with a route
- [x] `isCalibrationSuspended` includes turn alerts (+ WheelCalibration doc/log text)
- [x] `makeRideSummaryUpdate` + `State(resuming:)`; stale `route` doc rewritten
- [x] Tests: calibration suspension on a turn, `.task` loads the route, checkpoint carries route + progress, resume restores both

## 5. AppPreferences

- [x] `turnLeadDistanceMeters = defaultTurnLeadDistanceMeters` + decode; round-trip + legacy tests

## 6. Dashboard

- [x] `RideDashboardView.banner(turn:sourceSwitch:calibration:isOffRoute:)`: turn → source switch → calibration → off-route; icons
- [x] `RideBannerPriorityTests`; `RideBanner` Turn / Off route previews

## 7. Specs

- [x] DataModel.md §3.6 `turnLeadDistanceMeters` + consumer list
- [ ] Comment on #202: `Ride.routeProgressMeters` for §3.1, NavigationFeature shape for TCA.md §4/§10

## 8. Verify

- [x] Build clean — no warnings from changed code (the `fixedNow` isolation warnings in `ActiveRideFeatureTests` are pre-existing)
- [x] Targeted: 25 suites, 272 distinct cases, 0 failures; every new test found by name
- [x] Revert checks — each applied, run and restored by script, source diff hash identical after:
      (a) whole-route snap → `outAndBackStaysOnTheLegBeingRidden`, `earlyTurnaroundIsFollowedHome`;
      (b) Scope `.onChange` removed → `turnAlertSuspendsCalibration`;
      (c) plain `≤ lead` → `turnIsAnnouncedWithinTenMetresAtFortyKPH`;
      (d) floor ignores progress → `resumeLooksFromTheCheckpointedProgress`;
      (d2) `State(resuming:)` drops progress → `stateResumingRestoresTheRoute`;
      (e) no course filter → `outAndBackStaysOnTheLegBeingRidden`, `courseFindsTheLegWithoutACheckpoint`,
      `earlyTurnaroundIsFollowedHome` — the last only after it was fixed: it first **passed** under (e), because its
      rider rode out nearer the way back, the window-only match jumped there unasserted, and happened to be right by
      the turnaround. Now it rides out on the way-out side and asserts every outbound fix
- [x] Full `CyclometerTests` ×2 — baseline 1,018 (950 + 68) + added, every new test named in both logs
      - Run 1: exit 0, **1,060 distinct cases passed, 0 failed** = 1,018 + the 42 new test functions
        (992 Swift Testing + 68 XCTest)
      - Run 2, after the throwaway drive tests were deleted: exit 0, **1,060 passed, 0 failed**. All 42 new tests
        named in both logs; no warnings from changed files; working tree holds only the intended 21 files
- [x] Simulator, **riding a real route in the app** (iPhone 17 Pro, iOS 26.5). `simctl openurl` could not work — the
      app declares the GPX type but no `CFBundleDocumentTypes` — so a throwaway test seeded an 800 m N / 400 m E
      route into the host app's live store, a throwaway XCUITest started a ride on it through S05.1 → S05.2, and
      `simctl location start --speed=10` rode it. The app's own `navigation` log: route loaded (1 turn, 1,200 m) →
      on route at 0 m → **turn announced 97.5 m out (lead 100)** → calibration gate shut, then open after the turn →
      route complete; 200 m ridden past the finish raised no off-route. No runtime issues or app faults. The
      dashboard screenshot at ride time 01:13 shows the **"Turn right" banner with its arrow**; 01:10 has none. First
      attempt failed only because xcodebuild ran both tests on a *clone* — `-parallel-testing-enabled NO` (memory
      updated). Both throwaway tests deleted
- [ ] Commit + PR on Brian's go-ahead

## Deviations from the approved plan

- **Direction filter (Finding 6, added in step 2).** A window alone lets the way back of an out-and-back win within
  250 m of the turnaround, and locks an early turnaround onto the way out. Both searches skip segments running
  against the GPS course when it is meaningful (≥ 2 m/s). Plan file updated.
- **`.onChange` on the navigation `Scope`, not `CombineReducers`.** Same TCA semantics — each base forwards what it
  flips — without re-indenting the 500-line `Reduce`.
- **Dropped "free-ride `.task` never calls `fetchRoute`".** `skipInFlightEffects` can cancel a load before it reaches
  the mock, so the test could pass vacuously. Covered instead by the child no-route tests and the 8 unchanged
  exhaustive location tests.

## Review

**Built.** `NavigationFeature` follows the ride's route:
- Snapping keeps the rider on the leg they're riding: a 100 m back / 500 m ahead window, route segments that run
  against the GPS course are ignored, and the first pass is used rather than the nearest.
- Turns are announced within ±5.6 m of the lead distance at 40 km/h (PRD allows ±10).
- Off-route is flagged on the 5th fix in a row beyond 50 m and cleared inside 30 m.
- A ride that reaches the end goes quiet, including while it rides on past the finish.
- A turn alert suspends wheel calibration.
- A ride killed mid-route comes back on the right leg from `Ride.routeProgressMeters`.

The banner priority is turn → source switch → calibration → off-route.

**Verified.**
- 1,060 / 1,060 cases, twice, with all 42 new tests named in both logs.
- Six revert checks, each turning its guard test red.
- A real ride in the app on the simulator: the log shows the turn announced 97.5 m out, and the dashboard shows the "Turn right" banner.

**A test that proved nothing, caught by a revert check.** `earlyTurnaroundIsFollowedHome` passed with the direction
filter removed. Its rider rode out nearer the way back, the window-only match jumped there unasserted, and by the
turnaround it happened to be right. Fixed by riding out on the way-out side and asserting every outbound fix. Same
shape as the #210 lesson: a green revert check proves the fixture, not just the code.

**Not changed, for you.**
- The shared banner slot sits over the top of the hero speed digits (see the 01:13 drive screenshot). That's where the
  source-switch and calibration banners already go. Moving UI needs your approval.
- A rider standing still while being placed on a self-overlapping route can be put on the wrong leg. It corrects
  itself once they move, at worst with a single off-route fix. Only a checkpointed relaunch can hit it.

**Seams for the rest of M8.**
- #198: attach the tone to the `announcedManeuverIndex` transition (no delegate added, as nothing would use it yet).
- #199: draw `navigation.activeRoute.coordinates`.
- #200: read `nextManeuver` and `distanceToNextTurnMeters`.
- #201: GPX from disk through to an announced turn.
- #202 has a comment asking for `Ride.routeProgressMeters` and the NavigationFeature §4/§10 entries.

