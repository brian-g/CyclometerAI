# tasks/todo.md — #196 S05.1 active-route row + S05.2 Route picker

Branch: `feat/196-active-route-row` · Milestone M8 · Plan:
`~/.claude/plans/dapper-churning-acorn.md`

## Selection and ride hand-off

- [x] `StartSheetFeature`: `route`, `Delegate.startRide(RouteReference?)`, `path` + `Path.routePicker`, pop on pick
- [x] `AppFeature`: delete `activeRoute`, `presentStartSheet(_:route:)`, hand the route to `ActiveRideFeature`
- [x] `ActiveRideFeature`: `route`, passed to `createRide`

## S05.2

- [x] `Features/Rides/RoutePickerFeature.swift`
- [x] `Features/Rides/RoutePickerView.swift` + `RoutePickerList` seam; `RouteRow` made internal

## S05.1 view

- [x] `StartSheetView`: store-powered stack, `NavigationLink(state:)` route row, `ActiveRouteRow`, previews

## Tests

- [x] `.startRide` → `.startRide(nil)` at the four existing call sites
- [x] `StartSheetFeatureTests`: carried on Start Ride, pick route pops + sets, pick None clears
- [x] `RoutePickerFeatureTests`: success / empty / failure, tap → delegate
- [x] `AppRouteSelectionTests` rewritten against `startSheet?.route` / `activeRide?.route`, plus end-to-end
- [x] `ActiveRideFeatureTests`: seeded route reaches `createRide`; stale comment rewritten
- [x] `StartSheetSnapshotTests`: 14 references recorded, every PNG opened, none blank (231–256 distinct bytes)

## Verify

- [x] Build (`build-for-testing`), no new warnings from this change
- [x] Full suite ×2 (runs 2 and 3): 1,014 tests (946 Swift Testing + 68 XCTest), 0 failures, every new test named
- [x] Revert-the-fix: with `createRide(…, nil)` back, `taskCreatesRideWithItsRoute` is the one failure of 28
      (`ActiveRideFeatureStateMachineTests` — the file has no `ActiveRideFeatureTests` type; that filter ran 0)
- [x] `grep onDisappear` over both views is empty
- [x] Simulator: S05.1 → S05.2 → back → S05.2 → swipe-dismiss → reopen, driven by a throwaway XCUITest (deleted)
- [ ] PR

## Review

**Suite: 1,014 tests, 0 failures** on runs 2 and 3, snapshots included, each new test confirmed by name
in both logs. Run 1 recorded the 14 new references (its 7 failures were exactly the "no reference on disk"
first-record failures), then hung for ten minutes in `VariaRadarClientTests` "Unexpected disconnect … retries
on backoff ladder". That test is untouched here and passed in runs 2 and 3. Its shape matches the lessons
entry on state streams: `clock.advance` can land before the backoff task has started sleeping on the clock.
Not rewritten — I could not reproduce it failing, only hanging once.

**The route now lives in the sheet.** `AppFeature.activeRoute` was #195's one-shot placeholder, one-shot
because the row was read-only. With a picker in the sheet, a parent copy would have needed syncing; the
sheet's own state gives "forgotten on every way out" for free.

**Simulator, driven for the first time.** A throwaway XCUITest walked onboarding and permission alerts, then:
S05.1 at the half-screen detent with a real `NavigationLink` chevron on "Route  None"; S05.2 pushed (title
"Routes", back chevron, None checked, "No Routes"); back; pushed again; the whole sheet swiped away with S05.2
still on its stack; reopened on "Route, None". A `log stream` on `com.apple.runtime-issues` and app faults
logged no TCA warning across three drives — only an existing D-DIN "file already registered" font fault. The
drive's last assertion failed on my query, not the app: a `LabeledContent` link row exposes one button,
"Route, None", with no separate "None" text. The failure-time hierarchy shows the reopened sheet correct.

**Deviations from the plan.**
- A long route name does not stay on one line. `LabeledContent` stacks the label over the value and
  truncates the value — the platform's fallback, now pinned by `testRouteRowLongName`.
- The new `Path` uses `@Reducer` plus `Equatable` extensions: TCA 1.25.5 deprecates
  `@Reducer(state: .equatable, action: .equatable)`. `RoutesFeature.swift:148` still uses the deprecated form
  and warns; left alone.
- No new "picker takes no scan" test: it could not fail, since `AppFeature` owns the scan.

**Not verified automatically.**
- Picking a real route in the simulator: its library is empty and a Files import can't be driven. Covered by
  `StartSheetFeatureTests`, `AppRouteSelectionTests` and the picker snapshots.
- The runtime-issue capture had no positive control; it relies on TCA's Debug-build runtime warnings reaching
  `com.apple.runtime-issues`.
- Previews were not rendered.

**Specs.** Brian's PRD v0.5.0/UX edits went in as their own commit. A second commit fixes what they left: the
UX Screen Index row, the PRD §6 lists (plus the Phase 2 bike picker's "S05.1/S05.2"), UX §S05.2's key
components, and `TCA.md`'s picker line.

**Follow-ups.** The Routes tab itself is still Phase 2 in `PRD.md` §6 and `TCA.md:154` — #202. #197 restores
the route on resume (`routeId` on `RideSummaryUpdate`).
