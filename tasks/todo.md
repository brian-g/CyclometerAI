# Issue #97 — Radar and HR clients gate on paired records

Branch: `feat/97-radar-hr-paired-gate`, from `main` (#117 merged as `16048c2`). Milestone M10, Wave 2.

`VariaRadarClient` and `BLEHRClient` connect to the first peripheral advertising their service
whenever `targetPeripheralID` is nil — how M2 got data on screen before any pairing UI existed. At a
group start the app adopts a stranger's Varia or a training partner's strap, and there is no record
behind the connection for S11 to show or the rider to unpair. `BLECSCClient` has been correct since
#67 (`pairedAssignments` gates every reconnect). This brings the other two under the same rule so
#98, #99 and #100 have a gate to drive.

Spec: BLE.md §6 "Discovery is not adoption", §5.0 "Write ordering rule"; DataModel.md §3.7; UX.md §S11.

## Decisions (user-approved plan)
- **`setPairedSensor(_:)` is one endpoint that also does the teardown** — no separate `unpair()`. CSC
  needs two calls because its map covers all peripherals and one can lose a role yet stay connected;
  a single-slot client has no such ambiguity. Folding the teardown in makes §5.0's "records before
  teardown" structural rather than caller discipline.
- **One shared `DiscoveredDevice` in `Models/`** for radar and HR. `BLECSCClient.DiscoveredSensor` is
  untouched; #98 folds it in and adds the service-type tag.
- **The interim gap is accepted.** Nothing writes `.radar`/`.heartRate` records until #100, so both
  sensors stop connecting on `main` until the Sensors screen ships. No migration is possible — the
  auto-adopted peripheral was never persisted.
- **AC3 restated.** `BLECentral.connect` no-ops unless the peripheral is already in `discovered`, and
  there is no `retrievePeripherals` / state restoration (M7). The launch push *arms the gate* without
  the Sensors screen being open; the next scan reconnects. Same as CSC today.

## Tasks
- [x] 1. `Models/DiscoveredDevice.swift` — id, name, isPaired, isConnected.
- [x] 2. `VariaRadarClient` — `setPairedSensor` + `discoveredDevices`; `pairedPeripheralID` distinct
      from `targetPeripheralID`; gated `.discovered` with inventory + broadcast; `.stateChanged` keeps
      the gate.
- [x] 3. `BLEHRClient` — same, plus the `pairedPeripheralID != nil` guard on the `.disconnected`
      rescan, and two `disconnect()` fixes (fuse the two lock acquisitions; `stopScanning` outside the
      `guard let id`).
- [x] 4. `AppFeature.task` — push radar and HR records alongside the CSC map, sequentially.
- [x] 5. `assets/BLE.md` §6 — record that a single-slot client satisfies §5.0 structurally.
- [x] 6. Radar tests — interleaved transport call log, `pair`/`devices` harness helpers, 8 new cases,
      3 amended. **Compiles** (`build-for-testing` green); not yet executed.
- [x] 7. HR tests — full spy set on the harness, radar's set mirrored, 5 HR-only cases, 6 amended.
      **Not yet compiled.**
- [x] 8. `CyclometerTests/App/AppPairingTests.swift` — new suite, first `.task` test; one interleaved
      log across all three clients. **Not yet compiled.**
- [x] 9. Build + full local suite green — **484 passed, 0 failed**.

## Review

**Shipped.** Both clients hold a `pairedPeripheralID` gate distinct from `targetPeripheralID`, report
every peripheral they see on a `discoveredDevices` stream, and expose one `setPairedSensor(_:)` that
arms the gate and tears down in a single critical section. `AppFeature.task` pushes all three clients
sequentially at launch. BLE.md §6 records that a single-slot client satisfies §5.0's ordering rule
structurally rather than by caller discipline.

**Two bugs found in HR's `disconnect()` while gating it**, both in the blast radius and both now
fixed: the read-then-clear of `targetPeripheralID` used two lock acquisitions where radar fuses them
on purpose, and `guard let id else { return }` skipped `stopScanning`, so a ride finishing with no
strap connected left the radio scanning forever.

**The A→B swap bug the tests caught.** `setPairedSensor` first shipped with the teardown and the
retroactive connect as either/or — swapping the paired sensor released A and never connected B, which
would have left a rider's newly-paired radar dead until it next advertised. The radar test *hung*
(awaiting a `.connecting` that never came) while the HR twin *failed* (it asserts on a call log), from
the same defect. Both integration suites now carry `.timeLimit(.minutes(1))`, because every assertion
in them awaits a broadcast stream that never finishes, so a missing emission stalls the suite instead
of pointing at the bug.

**Observability gap I introduced and closed.** Before the gate, a discovered radar produced
`connection state → connecting` — the only evidence in the per-sensor log categories that discovery
had happened. Closing the gate with nothing paired made both categories silent, so an ignored radar
looked identical to one that never advertised. Both clients now log the gate's verdict once per
peripheral per scan session.

**Sequencing note for #98.** The interim gap is wider than "no rows in S11": radar and HR are not
*scanned for* outside an active ride, because `DeviceManagementFeature` only calls
`bleCSCClient.beginPairingScan()` and `BLECentral` issues a filtered scan. So there is no route to a
paired record at all until #98 lands the cross-client pairing scan. Recommend **#98 → #100 → #99**;
#99 refines a pairing flow that does not yet exist for these two.
