# Issue #68 — Minimal BLE pairing screen (scan, discover, pair, unpair)

Branch: `feat/68-ble-pairing`, from `origin/main` (#69 merged as `1c416f4`). Milestone M6.

M6 runs before M10, so live CSC needs a pairing surface before full S11 Device Management exists.
Before this, `BLECSCClient` auto-connected the first CSC sensor it saw and the rider could not see
what was found, choose between two sensors, or reject one. Settings' Sensors row led to a hardcoded
three-row demo list.

## Decisions (user-approved plan)
- **Replace the pushed Sensors screen**, not a modal sheet. UX.md S12 says "Sensors (navigates to
  S11)", the `NavigationLink` already existed, and TCA.md §8 names it `DeviceManagementFeature`.
- **Keep auto-connect, add a session ignore-set.** Removing the heuristic outright is the clean end
  state and what #70 wants, but with no persistence until #67 it would mean no sensor connects after
  a launch until the rider opens the screen.
- **Purpose-built `DeviceRow`.** `SensorStatusRow` is private to the Start sheet and models a fixed
  category, not a device.
- Pairing is in-memory only; `PairedSensor` and the role sheet are #67.

## Tasks
- [x] 1. `BLECSCClient.DiscoveredSensor` + `discoveredSensors` stream with replay-on-subscribe.
- [x] 2. `beginPairingScan` / `endPairingScan` refcount that bypasses the cold-state guard.
- [x] 3. `pair(UUID)` (speculative) and `unpair(UUID)` (per-device) endpoints.
- [x] 4. `unpairedThisSession` exclusion honoured by `claimUnfilledRoles`.
- [x] 5. `DeviceManagementFeature` + `DeviceManagementView` with Paired / Available sections.
- [x] 6. Wire into `SettingsFeature` via `Scope`; delete `SensorManagementView` + `SensorStatus`.
- [x] 7. Tests — 7 client cases via the existing `Harness`, 5 feature cases via `TestStore`.
- [x] 8. `assets/TCA.md` §8/§9 — correct the `SensorStatusRow` claim.
- [x] 9. Build + full suite; no regression past the known baseline failure.

## Review

**The issue's own proposed mechanism would not have worked, and that shaped the design.** #68
suggested pairing via `connect(peripheralID:roles:speculative: true)` so the existing measurement-flags
capability narrowing would free a role the sensor doesn't support. But the public `connect` closure
always passes `speculative: false`, which sets `isAutoAssigned = false` (`BLECSCClient.swift:414`),
and narrowing is gated on exactly that flag. Pairing through the public API would have pinned both
roles forever. Hence a separate `pair(UUID)` endpoint that takes **no roles**: capabilities are
unknown until the first measurement, so it claims both speculatively and lets narrowing decide.
`pairKeepsCapabilityNarrowing` is the regression test — a wheel-only sensor must give up `.cadence`.

**Scanning is shared and unrefcounted, so both directions needed guarding.**
`BLEClient.requestedServices` is a plain `Set` with `formUnion`/`subtract`, so a naive
`stopScanning` from either side cancels the other's scan. The refcount lives in `BLECSCClient`
(`pairingScanCount`) rather than the transport, keeping the change local: `stopScanning()`,
`disconnect()` and `endPairingScan()` each release the hardware scan only when no other holder
remains. Deliberately separate from `isScanning`, so a pairing scan never flips dashboard role tiles
to `.scanning` behind a settings screen — `recomputeRoleStatesLocked` is untouched.

**`discoveredNames` could not serve as the device inventory.** It is `[UUID: String]`, and assigning
`nil` *removes* a key, so a sensor advertising no name could never get a row. Added `discoveredIDs:
Set<UUID>` as the inventory and left `discoveredNames` for names.

**The list broadcast piggybacks on `recomputeRoleStatesLocked`.** That runs at all ten sites where
slots mutate; enumerating them by hand would drift the first time someone adds an eleventh. The one
case it does not cover — a name-only `.discovered` for an unpaired peripheral — broadcasts at its own
site.

**One test of mine was timing-sensitive, not the code.** A combined "replays and tracks pair/unpair"
case asserted `isPaired == true` on the first non-empty emission, but the replay can land before
`claimUnfilledRoles` has claimed the sensor. Split into two tests, one using a `connectionState`
transition as a deterministic sync point. (The apparent 10-minute hang while diagnosing was a red
herring: macOS has no `timeout` binary, so each loop iteration was exiting 127 and re-building. The
suite runs in 25s.)

**Tests: 12 new cases, all green.** Full suite passes except the known pre-existing
`HeroNumberSnapshotTests.testCustomColor()`. The `Harness` gained `scanStopped` and `disconnected`
recorders so per-device unpair can be told apart from the all-devices teardown.

**Not verifiable without hardware.** The simulator has no BLE radio, so the client tests are the real
gate. On-device checklist is in the plan — the one to actually watch is that an unpaired sensor
*stays* unpaired for 10s or more, which is the whole point of the exclusion set.

## PR #87 review round

- [x] Extract the row into `UI/Components/SensorListRow/SensorListRowView.swift` and use it from
      both the Start sheet and the Sensors screen (closes #11). `SensorRowButton` goes with it —
      the capsule "Pair" / "Unpair" / "Tap to Pair" button was duplicated verbatim in both files.
      Each screen keeps a thin private wrapper, because the two model different things (category
      vs device) and pass different trailing controls.
- [x] Available-section empty state is the spinner alone; the "Searching for sensors" text is gone.
- [x] Fix the previews. Root cause was not the mock data: previews resolve dependencies to
      `liveValue` (this client has no `previewValue`), so the screen built a real CBCentralManager
      and the live stream's empty replay cleared the seeded devices on `.task`. Both previews now
      override `bleCSCClient`; demo devices live in `PreviewContent/SensorDemoData.swift`.
- [x] `assets/TCA.md` §8/§9 — reverse the "not a shared component" entry this PR added, and
      `assets/UX.md` — register the `iconTile` opacity token the shared row uses.

**Verified by rendering, not by assertion.** Both screens were snapshotted through a throwaway test
(since deleted): the Sensors screen shows Paired/Available with the right tints and destructive
Unpair, and the Start sheet is unchanged — same category tints, battery label, badge, button.
The Start sheet has no snapshot suite, so that check existed only for the duration of the refactor.

**A wrong first fix, caught by rendering.** Overriding the dependency alone left the preview empty
in a snapshot host. Driving the preview's exact store directly proved the stub was fine — `.task`
simply does not run under `assertSnapshot`, even in the key window. The populated preview now seeds
`State` *and* stubs the stream, so it renders in either host.

## Left for the follow-ups

- `BLEClient.readValue` still has **no issue filed**. #71 named it an M6 prerequisite; it blocks #67
  (0x2A5C) and #63 (0x2A19), though not this work. Worth filing before #67 starts.
- Persistence, the 0x2A5C capability read and the Speed/Cadence/Both role sheet are #67, which is
  also where `unpairedThisSession` should become durable.
- Radar/HR/power sections, unpaired-to-top sorting, richer per-row status and sensor source priority
  are M10 — PRD §13 says M10 *extends* this screen, so it was built to grow.
