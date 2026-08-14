# Issue #67 — CSC role assignment at pairing (0x2A5C, role sheet, PairedSensor)

Branch: `feat/67-csc-role-assignment`, from `main` (#63 merged as `f8bc0d4`). Milestone M6.

#68 shipped a pairing screen, but everything behind it is a guess that evaporates on relaunch.
`BLECSCClient` claims both roles speculatively on Pair and narrows them only once the rider starts
pedalling and a measurement's flags byte reveals what the sensor actually reports. Nothing is
persisted, so `unpairedThisSession` exists purely to stop the auto-adopt heuristic re-claiming a
sensor the rider just rejected.

Three things wait on this: #70 must not write a persistent wheel circumference from a sensor the
rider never chose; BLE.md §13.4 records that M7 state restoration cannot rebuild
`BLECentral.connectionOwners` without persisted pairings; and BLE.md §5.0's "role reassignable
without re-pairing" has nowhere to live. The transport prerequisite landed in #85 (`readValue`), and
#63's `BatteryService` is a worked example of the same read handshake.

## Decisions (user-approved plan)
- **`PairedSensor` is a `Codable` struct inside the `AppPreferences` JSON document**, not a SwiftData
  `@Model`. DataModel.md §3.6 defers the choice to this issue. #69 proved the `@Shared(.fileStorage)`
  pattern; SwiftData would mean building a `ModelContainer` test fixture from nothing and putting an
  async load in front of 3–5 records nobody queries.
- **Speculative auto-adoption is removed.** `.discovered` connects only peripherals with a persisted
  record, which deletes `claimUnfilledRoles`, `pendingPeripherals` and `unpairedThisSession` —
  durable unpair falls out rather than needing its own mechanism.
- **The role prompt is a `ConfirmationDialogState`**, matching `ActiveRideFeature.finishAlert`. No
  child reducer, no new files, and it renders as the bottom sheet BLE.md §5.0 describes.

## Tasks
- [x] 1. Model layer — `PairedSensor`; `AppPreferences.pairedSensors` + `pairedSensor(for:)` +
      `sensorAssignments`; `SensorRole` gains `String` raw values and `Codable`.
- [x] 2. `BLECSCClient.Capabilities` — 0x2A5C parser, 16-bit LE, failable like `Measurement`.
- [x] 3. Client discovery — 0x2A5C in `discoverCharacteristics`, the read on
      `.characteristicsDiscovered`, and the `.characteristicValueUpdated` branch.
- [x] 4. Client roles — `Slot.isInterrogating`, `connect` → `setRoles` with assignment semantics,
      capability narrowing demoted to a fallback.
- [x] 5. Client pairing source of truth — `setPairedSensors`, `.discovered` gated on it, and the
      deletion of the auto-adopt machinery.
- [x] 6. `DeviceManagementFeature` — role dialog, `pendingPairing`, the `apply` write funnel,
      sections built from persisted records.
- [x] 7. `DeviceManagementView` — `@Bindable`, `.confirmationDialog`, tappable paired rows.
- [x] 8. `AppFeature.task` + `AppView` root task — push persisted pairings at launch.
- [x] 9. Tests — new `AppPreferencesTests`; `Capabilities` and client cases in `BLECSCClientTests`;
      `DeviceManagementFeatureTests`; rewrote `pairKeepsCapabilityNarrowing`, `unpairSticks`,
      `pairClearsExclusion`, `batteryLevelReadAndCleared` and the `Harness` helpers.
- [x] 10. Specs — DataModel.md §1/§3.6/§3.7/§9, BLE.md §5.0/§12/§13.4, UX.md S11, and the stale
      0x2A5C comment.
- [x] 11. Build + full suite; no regression past the known baseline failure.

## Review

**Persistence went into the AppPreferences document, not SwiftData.** DataModel.md §3.6 left the
choice to this issue. The deciding factor was not the entity shape but what exists to build on: #69
shipped `@Shared(.fileStorage)` with a working test-quarantine idiom, while SwiftData has no `@Model`
in the app but the Xcode template's `Item`, no `ModelContainer` test fixture, and a `SwiftDataStack`
that is unreferenced with an empty schema. Three to five records that are never queried and always
read whole do not justify building that. `DeviceManagementFeature.State` now derives its sections
synchronously, the way `SettingsFeature.wheelSelection` does.

**Auto-adoption is gone, which is most of the issue's value.** `.discovered` now connects a
peripheral only if `setPairedSensors` has named it. That deleted `claimUnfilledRoles`,
`pendingPeripherals` and `unpairedThisSession` — durable unpair falls out rather than needing its own
mechanism, and #70 can trust that the sensor driving auto-calibration is one the rider chose.

**Two bugs found while building, neither in the plan.**

*Pairing a second sensor knocked the first one offline.* `pair` claimed both roles speculatively, and
`connect` strips requested roles from every other peripheral, disconnecting one left holding none. So
interrogating a new sensor tore down a working one before the rider had chosen anything — and since
the old slot was gone, it did not come back. `Slot.isInterrogating` fixes it: `pair` now connects with
an empty role set, exempt from the "no roles means gone" rule, and the rider's answer commits via
`setRoles`. Covered by `pairInterrogatesWithoutClaimingRoles`.

*`AppPreferences` could not survive gaining a field.* DataModel.md §9 claimed "adding a field is free
— decoding an older document falls back to the property's default." It does not: the synthesised
`Decodable` throws `keyNotFound`, `.fileStorage` swallows that and substitutes a default-constructed
value, so an upgrading rider would have silently lost their wheel circumference the moment
`pairedSensors` was added. `AppPreferences` now has a hand-written `init(from:)` using
`decodeIfPresent`, and §9 says what is actually true. `decodesDocumentWithoutPairedSensors` pins it.

**`connect` became `setRoles` and now assigns rather than unions.** The old upsert was
`slot.roles.formUnion(roles)`, so moving a combo device from Both to Cadence would have left Speed
attached — "reassignable without re-pairing" (BLE.md §5.0) was not actually expressible. No
feature-layer caller existed, so the rename and the semantic change were free.

**Capability narrowing survives as a fallback rather than being deleted.** 0x2A5C is authoritative
and arrives at connect time, but a failed read produces *no event at all* — a non-compliant sensor
would otherwise never reach role assignment. The measurement-flags path stays, gated on no
authoritative capabilities having arrived. `pairKeepsCapabilityNarrowing` inverted into
`measurementFlagsNarrowWhenNoFeatureCharacteristic`, which is the same behaviour in its new position.

**A third bug surfaced from that fallback**: narrowing via measurement flags released the role but
never called `recomputeRoleStatesLocked`, so the cadence tile stayed stuck on `.active` after the
sensor gave the role up. Caught by the new test hanging rather than failing.

**Test sync points.** Several new client tests raced the client's event-processing task — yielding an
event and reading the device list on the next line. Connection-state assertions get a sync point for
free from the state stream; the device list did not, so `Harness.devices(matching:)` waits for a
predicate. `malformedCapabilitiesIgnored` needed particular care: its assertion is that *nothing*
changed, which passes vacuously if the event has not been processed yet, so it uses a well-formed
report from a second peripheral as the sync point.

**Verification.** Full suite: 296 passing, one failure — the known pre-existing
`HeroNumberSnapshotTests.testCustomColor()`. Baseline before this work was 261 passing with the same
single failure.

**Not verifiable in the simulator.** There is no BLE radio, so the 0x2A5C read has still never run
against hardware — #85 shipped the transport without a caller, and this is its first one. On-device
checklist for the PR:
- [ ] Wheel-only sensor auto-assigns Speed with no prompt
- [ ] Combo sensor prompts, and all three choices produce the right roles
- [ ] A paired sensor reconnects after force-quit with no rider action
- [ ] Reassigning Both → Cadence actually releases the speed role
- [ ] Pairing a second sensor leaves the first connected and working

## Review feedback (PR #89)

Three comments, all valid, all fixed on the branch.

**Two write-ordering races.** `pairedAssignments` is the gate `.discovered` consults before
reconnecting, and `CSCClientState` is a lock-guarded class, not an actor — the lock is dropped across
every `connect`/`disconnect`, so the event loop really does interleave with a feature effect. Both
call sites tore down before pushing the narrowed map:

- `unpairButtonTapped` — the sensor's next advertisement reconnected it holding roles, with no record
  behind it.
- `apply` — worse. `setRoles` strips an incumbent's last role and disconnects it; the incumbent then
  advertised, reconnected under the stale map, and took the role straight back off the sensor the
  rider had just chosen. The reassignment silently reversed itself.

Both now push `setPairedSensors` first. The window is one advertising interval with the pairing scan
running, so this was routine, not theoretical.

*Why the tests missed it:* they used one `LockIsolated` spy per endpoint, which can only assert that
both were called. `unpairSticks` in the client suite even drives the safe order by hand. Added
`ClientCall` — a single interleaved log across `setPairedSensors` / `setRoles` / `unpair` — and two
tests that pin the sequence.

**Capability narrowing did not reach persistence.** The client narrowed its own slot and stopped
there, so a pairing that outlived a firmware change would reconnect, re-narrow and re-claim on every
launch, with the paired row advertising a role the hardware refuses. Fixed in the feature, not with a
new client endpoint: `recomputeRoleStatesLocked` already ends in `broadcastDiscoveredLocked`, so the
narrowed capabilities arrive on `.devicesUpdated` — `reconcileCapabilities` drops the contradicted
records through the existing `apply` funnel and unpairs a peripheral left holding nothing (`setRoles`
rejects an empty set). It converges on the second pass. Capabilities that were never read correct
nothing.

`.devicesUpdated` uses `.concatenate` rather than `.merge` where reconciliation and a pending pairing
coincide: both effects push an assignment map, and the one built last has to land last.

Suite: 302 passing, same single pre-existing `HeroNumberSnapshotTests.testCustomColor()` failure.
BLE.md §5.0 gained the ordering rule as a table, §12 five test rows.

## Left for the follow-ups
- `ConnectedService` ownership is still open — its Keychain-identifier pattern is a different problem
  and nothing consumes it yet (DataModel.md §3.6).
- `SwiftDataStack` / `CoreDataStack` remain dead code. Deleting them is M7's call; this issue no
  longer needs SwiftData at all.
- UX.md S11 says "Unpaired sensors sorted to the top" while the screen sorts paired first. Left
  alone — a pre-existing contradiction, and which one is right is a product decision.
- #70 (wheel auto-calibration) is unblocked: its gate is
  `bleCSCClient.connectionState(.speed) == .active`, which is now only ever true for a sensor the
  rider deliberately paired.

---

# #70 — WheelCalibrationFeature: GPS auto-calibration (M6)

PRD §8.9's third way to set wheel circumference: compare BLE wheel distance against GPS distance
while riding and correct the stored value when they disagree materially.

- [x] `BLECSCClient.wheelRevolutions()` — per-measurement revolution deltas for the speed role
- [x] `CSCCalculator.lastCountedRevolutions` — counts travel on paths that emit no rate
- [x] `WheelCalibration` — thresholds + correction arithmetic, pure and standalone
- [x] `WheelCalibrationFeature` — windowing, gates, confirmation, commit
- [x] `ActiveRideFeature` wiring — scope, GPS forward, suspension via `onChange`
- [x] `SourceSwitchBanner` → `RideBanner` with an `icon` parameter; one resolved banner slot
- [x] Tests: 11 math, 11 reducer, 7 revolution-counting, 2 client-stream, plus parent updates

## Review

**Three findings changed the design mid-plan.**

1. **GPS distance is `Σ speed × Δt`, not summed coordinate hops.** Summing `CLLocation.distance(from:)`
   between ~1 Hz fixes measures `|true + noise|`, which is biased *upward* by roughly the size of the
   5% trigger threshold itself at realistic fix noise — it would have inflated the circumference on
   every window under tree cover. Doppler speed error is zero-mean and averages out. This also
   deleted the last-coordinate anchor entirely.
2. **Revolutions must be counted where `update` returns nil.** The calculator drops the first moving
   sample after a stop because the 16-bit event time wrapped and the *rate* is unknowable — but the
   revolution *count* is exact. Losing it costs ~10 m per stop; three stops in a 500 m window is a 6%
   fabricated discrepancy, biased the same way as (1). Split via a `lastCountedRevolutions`
   companion property rather than changing `update`'s return type, which also left all 14 existing
   calculator assertions untouched.
3. **A reconnect gap voids the window.** The client resets the wheel calculator on disconnect while
   GPS keeps flowing; a 20 s dropout at 25 km/h is a 28% phantom discrepancy.

**The invariant worth remembering:** every gate suppresses *both* accumulators. Rejecting a
poor-accuracy fix while revolutions keep accruing is bug (2) wearing a different hat. Gates are
sticky flags read at sample time, not per-sample filters.

**Two things the tests forced.** `TestStore.state` is get-only, so a parent-written flag can't be
exercised from the child's own store — suspension became a real action with a change-guard
(`Reducer.onChange`) in the parent. And an explicit `stopListening` at ride end *raced* `AppFeature`'s
`ifLet` teardown, which already cancels child effects; the action arrived after child state was nil.
Removing it fixed a genuine ordering bug rather than a test artifact.

**Deliberately not built:** no `AlertLevel`/`Comparable` ordering on `ThreatLevel` (only `.allClear` is
non-alerting, so `contains` is the whole requirement — and inventing an ordering would collide with
M4); no new `AppPreferences` field, since `lastCalibrationAt` and the commit counter are ride-scoped;
turn-alert suspension deferred until `NavigationFeature` exists.

**Verification:** 325 unit tests, 324 passing — the one failure is the documented pre-existing
`HeroNumberSnapshotTests.testCustomColor()`, confirmed still failing with the branch stashed.
Not verified on hardware: no rider, no paired CSC sensor, no GPS. The commit path, the ±10% cap and
the accuracy/gap gates are exercised only against synthetic fixes.

## Left for the follow-ups
- #72 (M6 unit tests) should add the source-switching cases; the calibration math and wiring are
  covered here.
- Residual accepted error: BLE notifications and GPS fixes land on independent ~1 Hz phases, so up to
  ~1 s of revolutions (≈7 m, ~1.4% of a window) can fall on the wrong side of a boundary. Under the
  threshold, and the two-window confirmation covers the rest.
- A store constructed directly at `.paused`/`.idle` (tests only) starts with the child's
  `isSuspended` default rather than the parent's derived value; the app always transitions through
  `.task`, so this never happens in practice.

### Field test 1 (2026-08-14) — both rides correct, but unobservable

Rode 1 mi at 700 x 25c (no correction), then 1 mi at 26 x 2.0 (no correction, distance under-reported).
**Both outcomes were right.** 26 x 2.0 is 2051 mm against a ~2105 mm wheel — a 2.57% discrepancy,
under the 5% trigger. The ~2.6% distance error observed is the same number seen from the other side.

The real defect the test exposed is that **a correctly-silent ride and a broken one looked identical**:
the only log line was on commit. Added `.notice` logging for each completed window (GPS metres,
revolutions, measured vs stored mm, discrepancy against threshold), for the confirmation streak, and
for every gate transition (sensor, GPS accuracy/speed). A ride that never accumulates now says so.

To actually exercise the trigger, a preset >5% off is needed — **29 x 2.1 (2288 mm) is 8.69% against a
700 x 25c wheel**, inside the ±10% cap, so one correction lands it. Needs ~1 km for two windows.

### Threshold research (2026-08-14) — 5% → 2%, window 500 m → 1500 m

**5% excluded everything the feature exists for.** PRD §8.9 justifies auto-calibration as correcting
tread wear (0.3–0.8%), inflation (0.3–1%) and rider weight (0.3–0.5%) — all an order of magnitude
under the trigger. Sheldon Brown puts the target population, riders on a default or charted wheel
size, at "2% or more". A real Edge 830 field report was 60 mm ≈ 2.85%. None of it was reachable.

The preset table is the clearest evidence: of 28 pairs, only 8 were catchable at 5%, **and every one
involved 29×2.1 or 26×2.0**. The whole 700c range spans 3.44%, so no road rider who picked the wrong
700c preset could ever be corrected. At 2% it is 18/28 pairs, 5 of them road-only.

Headroom was never the constraint — GPS speed error is zero-mean and averages down as √N, so the
floor is far below 5%. At 1500 m: boundary sd 0.27%, GPS sd 0.41%, combined **0.49%**. 2% is 4.1σ,
and it must hold across two consecutive windows in the same direction.

**A boundary "fix" was proposed, approved, implemented — and then reverted, because it was wrong.**
The reasoning was that the delta straddling a window start hands the wheel a free head start, so it
should be discarded. It does — but the riding *after* the last delta before the window closes is
symmetrically uncounted, and the two truncations cancel. A Monte Carlo of the two boundaries settled
it: counting the straddling delta gives mean −0.001 s (sd 0.41 s); discarding it gives mean
**−1.000 s**, i.e. a systematic −0.67% at 1500 m, biasing every correction toward a larger wheel.
The original code already had the property being paid for. Reverted; the reasoning is now a comment
on `wheelRevolutionsReceived` so nobody re-proposes it.

Sources: [Sheldon Brown on cyclecomputer accuracy](https://sheldonbrown.com/cyclecomputer-accuracy.html),
[calibration](https://sheldonbrown.com/cyclecomputer-calibration.html),
[Garmin forum — auto-calibration is a slow moving average, no threshold](https://forums.garmin.com/sports-fitness/cycling/f/accessories-sensors/157669/re-calibration-of-the-speed-sensor).
Per-factor magnitudes are from corroborating cycling-calculator sites, not instrumented measurement.
PRD §8.9 still documents 5% / 500 m — **the spec needs updating to match.**

### PRD updated to match (2026-08-14) — v0.4.3

`assets/PRD.md` §8.9 now documents 2% / 1,500 m, the two-window confirmation, the 3-per-ride cap,
out-of-range rejection, Doppler-speed integration, and pause-vs-discard suspension semantics.
New **§8.9.2** research note records the evidence, the Garmin contrast, and the rejected boundary
"fix" so it is not re-proposed. Acceptance criteria ticked except hardware verification. OQ13
resolution line, revision history (0.4.3) and version header updated; `TCA.md` §4.11 and
`DataModel.md` §10 test table brought in line.

One claim was corrected while writing it up: the preset-pair count is over **56 ordered
(stored, actual) combinations**, not 28 unordered ones — the discrepancy divides by the *true*
circumference, so it is not symmetric. 17/56 catchable at 5% (none road-only) vs 36/56 at 2%
(10 road-only).
