---
name: tca-feature
description: This skill should be used when the user asks to add a new TCA feature, scaffold a reducer, create a "<Name>Feature", wire a new sensor or widget into ActiveRideFeature or another parent feature, or add the accompanying tests for one. Encodes the actual reducer/view/test scaffold this codebase uses — as built in CadenceFeature and its siblings — not the aspirational, partly-stale layout in assets/TCA.md §8. Covers the "how" of building a feature; pair with the spec-first skill for the "what".
---

# TCA Feature Scaffold

This skill encodes the real pattern already living in `Features/ActiveRide/CadenceFeature.swift` and its three companion files — the most complete, currently-accurate example in the repo (a BLE-backed sensor feature with a reconnect grace window, a widget view, reducer tests, and snapshot tests). Use it as the template, not `assets/TCA.md` §8, whose nested file layout `CLAUDE.md` explicitly says the repo does not follow.

## File placement

Flat grouping: `Cyclometer/Cyclometer/Features/<Area>/<Name>Feature.swift` and `<Name>WidgetView.swift` (or `<Name>View.swift` for a non-widget screen) live side by side in the matching area folder (`ActiveRide/`, `Rides/`, `Routes/`, `Settings/`, `Onboarding/`). `PBXFileSystemSynchronizedRootGroup` is already configured in the `.xcodeproj` — any new `.swift` file under `Cyclometer/Cyclometer/` is picked up automatically. Never hand-edit the `.xcodeproj` file to add a source file.

## Reducer

Copy `assets/FeatureTemplate.swift.txt` and fill in the placeholders. Key shape, straight from `CadenceFeature`:

- `@Reducer struct <Name>Feature`, `@ObservableState struct State: Equatable`, `enum Action: Equatable`.
- Dependencies via `@Dependency(\.xClient) var xClient` — never import `CoreBluetooth`/`CoreLocation`/etc. directly in a reducer; go through the `@DependencyClient` in `Clients/`.
- A `.run { [xClient] send in ... }` effect subscribing to the client's `AsyncStream`, `.merge`d with a second `.run` for connection-state if the client exposes one separately (see `CadenceFeature.startListening`, which merges a cadence stream and a connection-state stream).
- Reconnect/timeout patterns use a private `enum CancelID { case reconnectTimer }` and `.cancellable(id: CancelID.reconnectTimer, cancelInFlight: true)`; new data arriving cancels the pending timer (`return .cancel(id: CancelID.reconnectTimer)`), a terminal `.disconnected` clears the reading immediately with no grace delay.
- `static let` constants for tunables (history window, grace delay) live on the reducer type itself, not scattered magic numbers.

## Composing into a parent

In the parent feature's `body`, add a `Scope` **before** the `Reduce`:

```swift
Scope(state: \.<name>, action: \.<name>) {
    <Name>Feature()
}
Reduce { state, action in ... }
```

Parent `State` gets `var <name> = <Name>Feature.State()`; parent `Action` gets `case <name>(<Name>Feature.Action)`. Start the sub-feature's stream alongside the parent's other effects — in `ActiveRideFeature` every sub-feature is kicked off in one `.merge(...)` inside the `.task` action handler (`.send(.cadence(.startListening))` sits next to the speed/calibration/timer/HR effects).

## View

A widget view takes **primitive parameters**, never a `Store` — `CadenceWidget` takes `cadence: Int?`, `cadenceHistory: [Double]`, `averageCadence: Int`, `maxCadence: Int`, `size: WidgetSize`. This keeps it independently previewable and snapshot-testable without a TCA harness; the parent dashboard view reads the fields off `store.state.<name>...` and passes them down. Rules that apply to every widget view in this codebase:

- Design-system tokens only: `cy`-prefixed colors (`Color.cyBgSecondary`, `Color.cyTextPrimary`, …), `Spacing`/`Opacity` constants, shared components (`HeroNumber`, `WidgetLabel`) — never a hardcoded hex, point size, or opacity literal.
- Layout branches on `size: WidgetSize` (`.oneByOne`/`.twoByOne`/`.twoByTwo`) with a dedicated `oneByOneContent`/`twoByOneContent` computed property per variant.
- Include `#Preview` blocks for the realistic-data case and the "no signal" / empty-state case, at both grid sizes the widget actually supports — copy the four-preview pattern at the bottom of `CadenceWidgetView.swift`.

## Tests

Two files, mirroring `CadenceFeatureTests.swift` and `CadenceWidgetSnapshotTests.swift`:

**`<Name>FeatureTests.swift`** — Swift Testing, not XCTest. Copy `assets/FeatureTests.swift.txt`:
- `@MainActor @Suite("<Name>Feature") struct <Name>FeatureTests`, a private `makeStore(...)` helper that installs `withDependencies` (fake client, `TestClock`, pinned `date`).
- `await store.send(.action) { $0.field = expected }` for direct state mutations; `await store.receive(\.action) { ... }` for effect-produced actions.
- Cover the reconnect grace window explicitly if the feature has one: data-cancels-pending-timer, no-timer-armed-without-a-prior-reading, timeout-clears-after-the-delay, recovery-within-the-window-keeps-the-reading, terminal-disconnect-clears-immediately. These five cases are the actual regression surface for every BLE sensor feature in this app — see `CadenceFeatureTests`' "BLE reconnect grace window" section.

**`<Name>WidgetSnapshotTests.swift`** — XCTest + `swift-snapshot-testing`. Copy `assets/WidgetSnapshotTests.swift.txt`:
- Fixed-size canvas matching the widget's actual grid slot in points (e.g. 393×96 for a 2×1 row, 196×96 for a 1×1). Look up the real slot size from a sibling widget at the same `WidgetSize` rather than guessing.
- One case per (size × active/no-signal × light/dark) combination that's visually distinct — not every permutation needs its own case if e.g. no-signal renders identically in light and dark.
- **Never** snapshot against ambient environment values (`.accentColor`, `.primary` where the token matters) — pass the explicit `cy*` token, or the reference silently encodes whatever the host bundle resolved at record time.
- These suites are recorded against a local simulator and are **skipped in CI** (`.github/workflows/tests.yml` has a skip-list) — add the new suite's name there, and always look at the recorded PNG after recording (not just "it passed on the second run") — a blank/solid-color reference is a test that can never fail again.

## Verification

```
xcodebuild build -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CyclometerTests
```
Run from `Cyclometer/`. Snapshot tests need a first local recording pass before they can assert — `swift-snapshot-testing` records on first run when no reference exists; re-run once to confirm the second run is green against the recorded reference, and open the recorded PNGs to confirm they're not blank.
