# Issue #63 — Sensor battery level in the Start sheet + BLE battery reads

Branch: `feat/63-sensor-battery`, from `main` (#68 merged as `ee571da`). Milestone M6.

`SensorRow.batteryPercent` has existed since #42 and `StartSheetView` already rendered it, but
nothing ever wrote it — no client read a battery characteristic, so UX.md §S05.1's "When Connected,
the battery level if supported" was unmet. The `readValue` prerequisite the issue names had already
landed in #85.

## Decisions (user-approved plan)
- **Read once on connect *and* subscribe to notify.** The read guarantees a level on sensors that
  only support reads; the subscription is one line and keeps it live on the majority that push.
  No polling — battery moves slowly and the Start sheet is where a fresh value matters.
- **Both surfaces**: the Start sheet (S05.1, per-role) and the Sensors screen (S11, per-device).
- **Level-aware glyph + low tint** at or below 20%, restyling the existing label in place.
- **One shared handshake, not three.** The Battery Service belongs to the device, not the profile.

## Tasks
- [x] 1. `BatteryService` — 0x180F/0x2A19 constants, `parseLevel`, and the event-driven
      discover → read → notify step function shared by all three clients.
- [x] 2. `VariaRadarClient.batteryLevel()` with replay; 0x180F in `discoverServices`; cleared on
      disconnect and on radio stand-down.
- [x] 3. `BLEHRClient` — new `live(bleClient:)` factory, `makePairingStream` now replays,
      `batteryLevel()` with replay.
- [x] 4. `BLECSCClient` — `Slot.batteryPercent`, `DiscoveredSensor.batteryPercent`,
      `batteryLevel(role:)` deduped and broadcast from `recomputeRoleStatesLocked`.
- [x] 5. `SensorBatteryLabel` in `UI/Components/SensorListRow/`, used by both screens.
- [x] 6. `StartSheetFeature` — `batteryUpdated(Kind, Int?)`, `setBattery`, four subscriptions.
- [x] 7. Tests — 26 new cases across five files plus a new snapshot suite.
- [x] 8. `assets/BLE.md` §14; corrected the `readValue` doc comment.
- [x] 9. Build + full suite; no regression past the known baseline failure.

## Review

**The handshake is shared because the Battery Service is a device concern.** The issue proposed
adding battery reads to each of the three clients. Written that way it is the same ~30 lines of
discover → read → parse three times. `BatteryService.handle(_:bleClient:owns:)` takes the event and
an ownership predicate, performs the transport calls itself, and returns a level when one arrives;
each client calls it once at the top of its event loop and keeps only the two things that genuinely
differ — what "owns" means (a single `targetPeripheralID` for radar and HR, `slots[id] != nil` for
CSC) and where the level is stored.

**One `discoverServices` call, not two.** `BLECentral.didDiscoverServices` broadcasts the
peripheral's *full accumulated* service list, so a separate `discoverServices(id, [0x180F])` would
re-emit `.servicesDiscovered` still containing the profile service and re-fire each client's own
discover → notify chain. Adding 0x180F to the existing call avoids that entirely; the handshake's
doc comment states it as a caller contract.

**Enabling notify contradicted a doc comment, so the comment was wrong.** `BLEClient.readValue`
asserted that 0x2A5C and 0x2A19 "are never notify-enabled". The correlation argument it was
supporting survives for a different reason — every 0x2A19 update carries a battery level whatever
triggered it — and the comment now says that instead.

**Two HR fixes were required, not incidental.** `BLEHRClient.liveValue` hard-wired
`BLEClient.liveValue`, so `HRClientState` had no test coverage and the battery path would have had
none either; it now has the `live(bleClient:)` factory radar and CSC already had. Separately,
`makePairingStream` did not replay, so a strap that paired before the sheet opened left the row at
`.notPaired`, `visibleSensors` filtered it out, and HR battery could never appear at all. Both are
covered by new tests.

**CSC battery is deduped, unlike CSC names.** `recomputeRoleStatesLocked` broadcasts names
unconditionally. Battery follows `roleState` instead and only emits changes, because the radar and
HR clients dedupe and three clients behaving alike matters more than matching the neighbouring line.
It also makes the stream assertable with `==` rather than a drain loop.

**Out-of-range levels are rejected, not clamped.** A sensor answering 0xFF is reporting a fault; a
"255%" row is worse than no label.

**Tests: 26 new cases, all green.** Full suite 261 passing, one failure — the known pre-existing
`HeroNumberSnapshotTests.testCustomColor()`. The parser and the handshake are tested standalone
(the handshake against a recording transport, since `BLECentral` needs a radio); each client's
integration suite drives the events through to its battery stream.

**Rendering verified for one screen, reasoned for the other.** The Sensors screen was snapshotted
through a throwaway test (since deleted) and shows the level between subtitle and Unpair.
`StartSheetView` renders blank under `assertSnapshot` — confirmed by stashing this branch and
rendering it on unmodified `main`, so it is pre-existing and is why that screen has no snapshot
suite. What it renders is the same `SensorBatteryLabel` in the same `SensorListRowView` trailing
slot, and the label itself has its own snapshot suite covering every glyph band, both schemes, and
the 20/21 threshold boundary.

## PR #88 review round

- [x] **User disconnect left the replayed state lying.** `HRClientState.disconnect()` nils
      `targetPeripheralID` before the transport answers, so the `.disconnected` branch that clears
      `isPaired` / `batteryPercent` guard-fails and never runs. Pre-PR nothing stored or replayed
      those, so only live subscribers were affected; adding replay-on-subscribe made every *new*
      subscriber inherit the lie. After Finish (`ActiveRideFeature.swift:178` calls
      `bleHRClient.disconnect()`), reopening the Start sheet showed the powered-off strap as
      "Connected — 45%". Both fields are now cleared in `disconnect()` itself.
- [x] **The radar had the same asymmetry**, unflagged by the review: `disconnect()` sets
      `.disconnected` but never cleared `batteryPercent`, for exactly the same reason. Not
      user-visible today only because the Start sheet hides disconnected rows — a latent trap for
      whoever changes that gate. Fixed alongside.
- [x] Both regressions are covered by tests that assert through a **fresh** subscriber, since the
      failure is in replay rather than in the live broadcast. Each was confirmed to fail against the
      unfixed code before the fix was restored.

**Not verifiable without hardware.** The simulator has no BLE radio. On-device checklist:
1. Console filtered to `com.xavier.cyclometer` — no `read skipped — 2A19 …` line.
2. Connect a strap or radar, open the Start sheet → battery next to Connected.
3. Open the sheet with a sensor *already* connected → battery appears immediately (replay).
4. Power the sensor off → the row leaves the connected state and battery disappears.
5. Sensors screen → the paired CSC device row shows its level.
6. A sensor without 0x180F shows no battery and no error.

## Left for the follow-ups

- Battery is not shown anywhere during a ride. UX.md only asks for S05.1; if a low-battery warning
  mid-ride is ever wanted, the streams already exist.
- `SensorRow.name` is still always nil in the Start sheet even though `BLECSCClient.sensorName(role:)`
  exists and is unused. Out of scope here, but it is a one-line subscription away.
- #67 still owns `PairedSensor` persistence, the 0x2A5C capability read, and the role sheet.
