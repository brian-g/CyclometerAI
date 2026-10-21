# #411 — Serialise LiveActivityClient's start / update / end

Plan: /Users/brian/.claude/plans/enumerated-conjuring-leaf.md
Branch: `fix/411-live-activity-serialise`

- [x] 0. Spike: does `activities` list a requested activity at once; do client closures run nonsending
- [x] 1. Real-ActivityKit test `endDuringAStartLeavesNothingShowing`; confirm it fails unserialised
- [x] 2. Serial queue in `LiveActivityClient.liveValue` (start/update/end); doc comments
- [x] 3. Reducer: drop the extra `end` in `.started`; update `settingOffWhileStartingSendsNothingMore`
- [x] 4. Flake check (10× each way), LiveActivity suites, full suite
- [x] 5. Review section, PR

## Review

- **Cause.** `start` waits on ActivityKit (about 4 ms per `activity.end` in the sim) while it sweeps older ride activities, and only then requests. An `end` arriving in that window snapshots `Activity.activities` before the request lands, so it never sees the new card.
- **Fix.** `LiveActivityClient.liveValue` runs `start`, `update` and `end` through `SerialCalls`: a `Mutex`-held tail of tasks, each waiting for the one before (the `RideDataBuffer.flush` idiom). An actor alone wouldn't serialise these calls, because it's reentrant across ActivityKit's awaits. `ended` stays out of the queue, since it waits as long as the card shows. Each call runs in its own task, so a cancelled caller can't drop an `end`.
- **Spike findings.** `Activity.activities` lists a requested activity as soon as `request` returns, so the queue doesn't need to hold the `Activity`. The client's closures run on the caller's actor up to their first await (approachable concurrency, nonsending), so the queue order is the call order.
- **Reducer.** The extra `end` in `.started` for a start that was pending when the S12 toggle went off is gone. The client's ordering covers that case now. `settingOffWhileStartingSendsNothingMore` now expects one `end`. The finish path is unchanged.
- **Tests.**
  - New `LiveActivityClientTests.endDuringAStartLeavesNothingShowing`, against real ActivityKit: **failed 10/10** on the old client, each time on "nothing left showing", and **passed 10/10** with the queue.
  - Full `CyclometerTests` minus the two known local hangs: 1,821 unique cases, all passing. `PersistenceClientTests` and `MapWidgetAccessibilityTests` run alone: 50 cases, all passing.

---

# #440 — Convert store bindings to `.sending`; toggle actions take a Bool

Plan: /Users/brian/.claude/plans/jiggly-hatching-glacier.md
Branch: `refactor/440-sending-bindings`

- [x] 1. Reducers: Settings toggles + turn-by-turn → `…Changed(Bool)`; guard `liveActivityChanged`
- [x] 2. Views: SettingsView, StartSheetView, RideDashboardView → `.sending`
- [x] 3. Tests: idempotence in Settings/StartSheet; Live Activity on/off through AppFeature
- [x] 4. Greps, targeted suites, snapshots
- [x] 5. Full suite
- [x] 6. Review section, PR

## Review

- **Bindings.** Eleven `Binding(get:set:)` sites became `$store.x.sending(\.action)`: nine in `SettingsView`, one in `StartSheetView`, one in `RideDashboardView`. Five remain, all of them sites the issue excludes: `AppView.dashboardStore`, three `RoutesView` range-slider bindings, and `RoutesView`'s camera.
- **Actions.** `autoPause`, `autoDim`, `placeNameLookup` and `liveActivity` (SettingsFeature), plus `turnByTurn` (StartSheetFeature), are now `…Changed(Bool)` and set the value rather than toggling it. `Delegate.liveActivityToggled` keeps its name.
- **Guard.** `liveActivityChanged` returns early when the value is unchanged, so the delegate only fires on a real toggle. A repeat wouldn't have broken anything, because `LiveActivityFeature.start` and the off path are already idempotent. The guard is there so the delegate's name stays true.
- **Tests.**
  - Each toggle test sends the same value twice; the second send asserts no state change.
  - The Live Activity Settings test also asserts that no delegate fires.
  - `settingsToggleReachesTheRide` now turns the setting off and back on through `AppFeature`, and checks the ride's activity ends and then starts again.
  - **Mutation:** removing the guard fails `liveActivityTogglePersists`.
- **Verification.**
  - The targeted suites pass: Settings, StartSheet and LiveActivity feature tests, plus Settings and StartSheet snapshots. No reference images changed.
  - Full `CyclometerTests` minus `PersistenceClientTests`: 1,823 unique cases, all passing. `PersistenceClientTests` alone: 47 cases, all passing. The first full run hung on the known Persistence × MapKit deadlock (a sample confirmed it), so it was split.
  - No test renders `RideDashboardView`'s body, so the plan's dashboard snapshot check had no suite to run. Its `TabView` binding is covered only by compilation and the `dashboardPageChanged` reducer tests. A swipe on the simulator would confirm it.
- **#439** is still open, so the text bindings were converted in place. Whichever of the two lands second rebases `SettingsView`.
