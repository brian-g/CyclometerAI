# #440 — Convert store bindings to `.sending`; toggle actions take a Bool

Plan: /Users/brian/.claude/plans/jiggly-hatching-glacier.md
Branch: `refactor/440-sending-bindings`

- [x] 1. Reducers: Settings toggles + turn-by-turn → `…Changed(Bool)`; guard `liveActivityChanged`
- [x] 2. Views: SettingsView, StartSheetView, RideDashboardView → `.sending`
- [x] 3. Tests: idempotence in Settings/StartSheet; Live Activity on/off through AppFeature
- [x] 4. Greps, targeted suites, snapshots, full suite
- [x] 5. Review section, PR

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
  - The full `CyclometerTests` run was still in progress when the PR was opened; see the PR for its result.
- **#439** is still open, so the text bindings were converted in place. Whichever of the two lands second rebases `SettingsView`.
