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

### Field-verified, and two fixes it prompted (2026-08-15)

**It works end to end.** A ride started at 2288 mm (29 × 2.1) logged window 1 → 2051 mm (11.56%,
"wheel reads long", 1 of 2), window 2 → 2069 mm (10.56%), then committed 2288 → 2069, pushed to the
CSC client, and showed the banner. Settings verified as Custom 2069 mm afterwards.

Six windows across two rides on the same bike: 2057, 2069, 2069, 2055, 2051, 2069 mm — mean 2061.8,
sd 8.4 mm (**0.41%**, against the ~0.49% predicted floor). The estimator behaves as designed, and
the two brief GPS pauses were the sub-2 m/s stop gate working correctly.

**Fix 1 — the commit was discarding half its evidence.** Confirmation needs two windows but `commit`
used only the second one's measurement: it took 2069 where the mean of both was 2060, and the pooled
six-window evidence puts the truth near 2062. `WheelCalibration` was restructured around a
measurement (`measuredCircumferenceMM` → `exceedsThreshold` / `isOverReading` →
`correctedCircumferenceMM`) so the averaging can happen between the raw measurement and the cap, and
`State.pendingMeasurements` now keeps the values instead of just counting them. `confirmedWindows`
became a computed property over that array, so there is one source of truth.

**Fix 2 — suspension transitions were unlogged.** The sensor and GPS gates logged; radar-driven
suspension did not, so a ride whose windows never completed could not say why. The RTL515 was
connected for this ride and was demonstrably not interfering (both windows ran at a steady ~6.3 m/s),
but that was inference rather than evidence. Now logged on change like the other two gates.

328 tests, 327 passing — the one failure remains the pre-existing `HeroNumberSnapshotTests.testCustomColor()`.

Also corrected in the docs: I had asserted this bike rolls ~2105 mm (assuming 700 × 25c) and built two
rides of predictions on it. Measured, it is ~2062. The threshold research was unaffected — it rests on
the preset table and Sheldon Brown, not on this bike — but the field-test predictions derived from
the invented number were worthless.

---

# #72 — M6 unit tests: CSC pipeline wiring, source switching, calibration math

## What the issue asked for vs. what was missing

Three of the issue's four bullets were already covered by tests that shipped with #65–#70, so this was
not the broad sweep the title implies:

| Issue bullet | Status on arrival |
|---|---|
| Role matrix (wheel-only / crank-only / combo) per BLE.md §5.0 | Covered — `DeviceManagementFeatureTests` (18) + `BLECSCClientTests` live state machine (~30) |
| CSC parsing, calculator, backoff, 0x2A5C capabilities | Covered — `BLECSCClientTests` (~70 tests) |
| Calibration trigger, ±10% cap, accuracy gating, suspension | Covered — `WheelCalibrationTests` (15) + `WheelCalibrationFeatureTests` (12) |
| Speed source switching, cadence "--", shared peripheral | Partial — the gaps below |

The issue text also predates two spec revisions: it says "5% trigger", but PRD §8.9.2 moved that to 2%
over a 1,500 m window, and the code and its tests already track the current numbers. No test changed
on account of the wording.

## Tasks

- [x] SpeedFeature: BLE → GPS → BLE round trip (the return leg was untested)
- [x] SpeedFeature: a completed fallback cycle re-arms on the next drop
- [x] ActiveRideFeature: radar-driven calibration suspension (4 tests)
- [x] ActiveRideFeature: shared CSC peripheral disconnect (3 tests)
- [x] Prove each new test fails against an inverted reducer
- [x] Full CI-equivalent run green

## Review

**The real gap was cross-feature wiring, not client or math coverage.** Two holes, both invisible from
inside the child suites:

1. **Promotion back to BLE had no test.** `SpeedFeatureTests` covered the outbound leg five ways but
   never the return. `.bleSpeedReceived` sets `activeSpeedSource = .bleWheel` with no dedicated
   action — the arrival of data *is* the promotion — so deleting that line broke nothing that was
   asserted. It now fails `bleToGPSToBLERoundTrip`. `activeSpeedSource` is also the badge input, so
   this doubles as the badge-transition coverage DataModel.md §10 asks for.

2. **Radar-driven suspension had no test.** `suspensionChanged` was asserted only incidentally, and
   only on the pause/resume half of `isCalibrationSuspended`. The radar half was unreachable from
   `ActiveRideFeatureRadarTests`, whose stores start from `ActiveRideFeature.State()` — `recordingState`
   defaults to `.idle`, so suspension is already on before a target ever lands, and adding a `.danger`
   target changes nothing. The new suite starts recording, which is what makes the transition
   observable. Dropping the `radarTargets.contains` clause now fails all four of its tests.

**One test was wrong on the first run, for a reason worth keeping.** `fallbackTimerRearmsAfterACompletedCycle`
drove `.reconnecting` → data → `.reconnecting`, and the second send asserted a `connectionState` change
that never happened — it was already `.reconnecting`. A real reconnection passes through `.active`
first. Adding that step both fixed the test and made it exercise the optimistic cancel on `.active`
that the original sequence skipped.

**Deviation from the approved plan.** The plan called for the `FileStorage.inMemory` quarantine on the
new `ActiveRideFeature` suites. Dropped: neither suite reads or asserts on `wheelCircumferenceMM`, no
window reaches 1,500 m so `evaluateWindow` is never entered, and nothing writes preferences. Adding the
idiom would have been ceremony that implies a hazard that isn't there, and it would have diverged from
the four sibling suites in the same file, none of which use it.

**Verification.** Every new test was proved to bite by temporarily inverting the reducer it guards —
dropping the radar clause from `isCalibrationSuspended`, removing `activeSpeedSource = .bleWheel` from
`.bleSpeedReceived`, removing the cadence clear on `.disconnected`, and swapping `resetWindow` for
`resetMeasurements` on sensor loss. Each failed exactly the intended tests and nothing unrelated; all
four reverted. 317 tests pass under the CI selection (the four snapshot suites CI skips, skipped).

## Left for the follow-ups

**The combined disconnect banner is specified but not built.** BLE.md §6.2 and the §12 acceptance table
require one notice for a shared peripheral — "Speed sensor disconnected — using GPS speed; cadence
unavailable." Today `CadenceFeature` has no banner state at all, and neither feature knows the two roles
share a device: they watch separate `connectionState(role:)` streams. Per the decision on this issue the
new tests pin shipping behaviour and carry a comment naming the gap at the assertion.

Folded into the same follow-up:
- §12 also asks for a cadence-disconnection banner; §6.2's own table says only "no fallback source
  available". The two rows disagree — resolve which is intended before building either.
- `SpeedFeature.State.pairedPeripheralId` and `CadenceFeature.State.pairedPeripheralId` are never
  written or read. They are the natural hook for detecting the shared-peripheral case: populate or delete.
- PRD §8.4 specifies a third string ("Switched to GPS speed — BLE sensor disconnected"). Three specs,
  three strings.
- `WheelCalibration.swift:7,13,23` still frames 1,500 m / 2% as deliberate deviations from a PRD that
  "specifies" 500 m / 5%. PRD §8.9.2 has since adopted both, so the values agree and only the prose is
  stale. Same framing in this file at the #70 entry above.

## Also in this change — the long-standing snapshot failure

`HeroNumberSnapshotTests.testCustomColor()` was documented in CLAUDE.md as a known pre-existing
failure. It was a real bug in the test, not simulator drift.

The test rendered `HeroNumber(...).valueColor(.accentColor)`. `.accentColor` resolves against the host
bundle's asset catalog, and `Assets.xcassets/AccentColor.colorset` is pure white in both appearances —
so the view drew a white number on `systemBackground`, i.e. an invisible one. The reference PNG showed
SwiftUI's default blue, recorded before that asset existed. The test had therefore been asserting the
ambient accent rather than the modifier, and would have been worthless even had the pixels matched.

Fixed by pinning the case to `.cyPrimary`, which is what the modifier is actually for — overriding the
default `.primary` — and re-recording the reference. The whole local suite now passes: 348 tests, no
failures, snapshot suites included.

CI still skips the four snapshot suites. That skip is about SwiftUI pixel output varying across runner
images, which this fix does not address; the workflow comment no longer cites `testCustomColor` as its
example, and needs its own issue (record-on-CI or a per-pixel tolerance).

**Not touched:** the white `AccentColor` asset itself. Any stock SwiftUI control tinting off the accent
renders white today, and `HeroNumber.swift:225`'s own `#Preview` uses `.valueColor(.accentColor)`, so it
previews invisibly too. That looks like an unfilled placeholder rather than a decision, but it is a
production asset and outside a test-only change.

## #110 — Screen wake lock + idle auto-dim (2026-08-15)

- [x] `ScreenClient` dependency — idle timer + backlight, resolved via `connectedScenes`
- [x] `AppFeature` screen state, 30 s countdown, brightness capture/restore
- [x] `AppView` — scene-phase wiring, interaction gesture, dim blocker overlay
- [x] Tests: wake lock, pill carve-out, dim, restart-on-touch, wake, backgrounding, clamp

### Review

A bicycle computer that blanks mid-ride is useless, and nothing in the app touched the idle
timer before this. Two behaviours: hold the screen awake while the dashboard is the visible
surface and the app is foregrounded, and dim after 30 s of no interaction.

**iOS exposes no public API for the system Auto-Lock interval**, which the issue had assumed
was readable — so the timeout is a fixed `AppFeature.dimAfterSeconds = 30`, paired with
`dimBrightness = 0.1`. Both are single constants destined for `AppPreferences` once they
become rider settings.

Everything hangs off one derived condition, `State.isDashboardVisible`
(`isDashboardPresented && activeRide != nil && isForeground`), forwarded on the transition via
`.onChange(of:)` — the same idiom `ActiveRideFeature` uses for `isCalibrationSuspended`. That
gives exactly one place where the wake lock, the countdown, and the brightness restore are kept
consistent, instead of five call sites each remembering to clean up. Minimizing to the accessory
pill releases everything, per the issue's explicit carve-out.

**The dim commits in two steps, not one.** Reading the backlight is async, so the first draft set
`isDimmed = true` immediately and filled `preDimBrightness` when the read returned. That admits a
state — dimmed, with nothing to restore to — where the wake path silently gives up and strands the
rider's phone at 10% brightness. `dimTimerFired` now only kicks off the read; `preDimBrightnessCaptured`
re-checks visibility and sets both fields together, so the two are inseparable by construction.

**Dimming clamps rather than sets**: `min(current, dimBrightness)`, so a rider already at 5% in the
dark is never *brightened* by the dim.

Lowering the backlight does not block touches, so an invisible `Color.clear` blocker at `zIndex(2)`
is what makes the dim modal. It uses `DragGesture(minimumDistance: 0)` rather than `onTapGesture` so
swipes are swallowed too, and it swallows the wake touch so that touch can't also fire whatever sits
under it.

**Accepted risk, stated plainly**: `UIScreen.brightness` is a user-visible system setting. Restore
fires on backgrounding, which covers app-switcher kills (`.active → .inactive → .background`). A hard
crash while dimmed will not restore.

All tests passing (written pre-rebase, when `testCustomColor` was still red; #111 has since fixed it).

**Not verifiable in the simulator**: it neither auto-locks nor honours brightness writes, so nothing
about the wake lock or the dim is observable there — the automated suite only reaches reducer level.
**Brian verified both on device (2026-08-15)**, which is the only evidence either behaviour actually
works. Treat that as a required step for future screen-power changes, not a formality.

### Follow-up — auto-dim honours the Settings toggle (2026-08-15)

The "Auto-dim" toggle already existed in S12, but it was backed by ephemeral
`SettingsFeature.State.isAutoDimEnabled`: nothing read it and it reset on every relaunch.
So the toggle looked implemented and did nothing.

- `AppPreferences.isAutoDimEnabled` (default `true`), decoded with `decodeIfPresent` like
  every other field, so a document written before #110 still decodes and starts with
  auto-dim on.
- `SettingsFeature.State.isAutoDimEnabled` became a computed read-through to `preferences`,
  and `autoDimToggled` writes via `$preferences.withLock` — the same funnel the wheel
  circumference uses.
- `AppFeature.armDimTimer` is gated on the preference.

**The wake lock is deliberately not gated.** Turning auto-dim off means "stop dimming", not
"let the phone sleep mid-ride" — those are different requests, and only one of them is a
preference. A bicycle computer that blanks mid-ride is broken, not configurable.

Also fixed while here: `AppScreenPowerTests` were reading the developer's real
`app-preferences.json`. They now use `FileStorage.inMemory` per store, matching
`SettingsFeatureTests`.

### Follow-up — the white AccentColor asset itself (2026-08-15)

#111 fixed `testCustomColor` the right way — by pinning the case to `.cyPrimary` instead of
asserting the ambient accent — and explicitly left the asset alone as "outside a test-only
change". This is that follow-up.

`Assets.xcassets/AccentColor.colorset` held explicit white `(1,1,1)` in both appearances. It was
empty (→ system blue) until `88bd65c` "Feat/custom sf pro icon (#57)" on 2026-06-26 added 27
lines writing white into it — a commit whose message is entirely about SF Symbols and SVG bike
icons. Xcode's asset editor wrote it as a byproduct of the icon work, which is why it read as an
unfilled placeholder rather than a decision.

AccentColor now carries the same values as `cyPrimary` (`#60BD10` light / `#6FD11E` dark, per
`assets/design/colors.md`). The app-wide default tint is brand green instead of white, so the
scattered explicit `.tint(.cyPrimary)` calls become redundant reinforcement rather than the only
thing holding the tint up — anything outside `AppView`'s TabView hierarchy previously fell back to
white, including `HeroNumber.swift`'s own `#Preview`, which previewed invisibly.

No snapshot churn: #111's re-recorded reference already renders `#60BD10`, so the PNG this change
produces is byte-identical to the one on main.

## #94 — AppPreferences: preferredUnit + isAutoPauseEnabled (2026-08-16)

Two of the four fields the issue names actually needed adding. Corrections found while planning:

**`isAutoDimEnabled` had already landed** in `e759d22` (#110) — field, `decodeIfPresent` shim
and consumer all present — so the issue was one field stale.

**`mapOrientation` was deferred.** It has no consumer and none planned in M10: PRD §8.6 puts the
heading-up/north-up choice on the map's own compass, not in Settings, and UX.md §S12 has no row
for it. Persisting a value nothing writes and nothing reads is not foundation, it is dead weight.
It lands with the issue that makes `ActiveRideMapView`'s camera orientation survive a relaunch.

**There is no "strict decode", and the issue's third acceptance criterion asked us to build one.**
It wanted a document containing `shouldSetDoNotDisturb` to be *rejected*. `init(from:)` is lenient
by construction — every field is `decodeIfPresent` with an explicit default, and unknown keys are
ignored by `KeyedDecodingContainer`. That leniency is the entire reason the initializer is
hand-written (DataModel.md §9): the synthesised one throws `keyNotFound`, `.fileStorage` swallows
the throw and returns a fresh `AppPreferences()`, and the rider silently loses every *other*
preference. Adding unknown-key rejection would have made one stray key — including one written by
a newer build after a downgrade — wipe the whole document. The criterion was dropped rather than
implemented, and DataModel.md §3.6's note claiming such a rule exists was corrected.

### The locale seam

`preferredUnit` defaults to the device locale, so the default needed to be assertable against
something other than the test machine's region. `UnitSystem.system` read `Locale.current` inline;
the mapping is now a pure `init(_ locale: Locale)` and `system` is a one-line delegation to it.
`UnitSystemTests` pins eight named locales — including Liberia (`ussystem`) and Myanmar
(`uksystem`), which are what make it a measurement-system test rather than a "US or GB" test.

**`@Dependency(\.locale)` was rejected.** swift-dependencies' `LocaleKey` declares only
`liveValue`, so the default `testValue` calls `reportIssue` from a test context. `AppPreferences()`
is the `.fileStorage` default and is constructed across six test suites; every one would have
needed a `withDependencies` override. Too viral for one default value.

### Also removed

`shouldSetDoNotDisturb` was still live in `SettingsFeature` and `SettingsView` despite UX.md §S12
recording the row as removed on 2026-08-14. Deleted — state, action, reducer case and `Toggle`.
It never reached `AppPreferences`, so there was nothing to migrate.

### Not done here

No consumer wiring, per the issue. `SettingsFeature.State.isAutoPauseEnabled` stays ephemeral and
the units picker stays a disconnected `String` — #102 owns both, alongside the sensor-count row in
the same section. Until then `isAutoPauseEnabled` exists in two places with two meanings; whoever
takes #102 should collapse it the way `isAutoDimEnabled` already is (a read-through computed
property plus `withLock` in the reducer).

### Verification

376 tests pass, 0 fail, including all five snapshot suites locally. `SettingsView` was rendered
through a throwaway `assertSnapshot` harness to confirm the General section is exactly the five
rows UX.md §S12 specifies — Units, Wheel Size, Auto-pause, Auto-dim, Sensors — with Do Not Disturb
gone; the harness was deleted afterwards. (`ImageRenderer` is no use here: it cannot render `Form`
or `NavigationStack` and emits a placeholder glyph.)

---

## #95 — PermissionsClient: CoreBluetooth, CoreLocation, CoreMotion, HealthKit (2026-08-16)

Wave 1 of M10. A single `@Dependency` over the four authorization domains S01 presents, so no
feature has to know which framework backs which row. No UI — that is #106.

### Tasks

- [x] `PermissionDomain` / `PermissionState` / `PermissionChange` in `Models/`
- [x] `PermissionsClient` with `status` / `request` / `statuses`, plus pure per-framework mappers
- [x] `PermissionsClient+Mock` — scriptable per domain, models the short-circuit
- [x] `BLEClient` gains `authorization` / `requestAuthorization`
- [x] Location authorization consolidated out of `LocationClient`
- [x] `NSMotionUsageDescription` + `NSHealthUpdateUsageDescription`
- [x] 29 new tests; five of them drive the live client against real frameworks
- [x] Spec corrections in PRD, UX and CLAUDE.md

### Four decisions the issue did not settle

**`.unavailable` is a sixth state, and it earns its place.** `CMMotionActivityManager.isActivityAvailable()`
is false on the Simulator — verified, not assumed — so motion authorization never leaves
`notDetermined` there however often it is asked. With only the four states the issue lists, S01's
"Motion denied blocks Next" would have deadlocked every Simulator run. `.unavailable` says *no such
hardware*, which is not a refusal, and #106 must treat it as non-blocking.

**Bluetooth authorization went onto `BLEClient`, not into `PermissionsClient`.** The prompt is fired
by a `CBCentralManager` existing at all, and `BLECentral` owns the app's only one. A second central
raised for permissions would have been a second scan budget and a second delegate bridge for nothing.
`PermissionsClient` delegates through the injected transport, matching `BLEHRClient.live(bleClient:)`.

**Location authorization left `LocationClient` entirely.** It is now data-only; `LocationManagerState`
moved to its own file as a `shared` singleton, mirroring `BLECentral.shared`, so there is still exactly
one `CLLocationManager`. `ActiveRideFeature` asks `permissionsClient.request(.locationWhenInUse)` — same
When In Use request at the same moment, so behaviour is unchanged.

**HealthKit asks for the workout write now.** UX.md §S10 has an `HKWorkout` written at ride end in MVP,
while PRD §11 called HealthKit read-only and §9.4 called the write Phase 2. Requesting read and share
together means one sheet in the rider's lifetime rather than a second one months later at the end of
their first ride. All three docs corrected.

### The honesty requirement, and why it is structural

`.health` **cannot** return `.denied`. HealthKit deliberately will not tell an app that a read was
refused — `authorizationStatus(for:)` reports `notDetermined` both before the sheet and after a
refusal, and an empty query means the same thing. So the client reads
`getRequestStatusForAuthorization(toShare:read:)` instead and maps `.unnecessary` to `.granted`
("we asked; iOS will not say more"). #106's "HealthKit does not render as a red X" is therefore true
by construction rather than by the view remembering to special-case it.

### One bug found in review

The first cut of `BLECentral.requestAuthorization` read authorization, then parked a continuation.
If the rider answered in between, the delegate ran, found no waiter, and never fired again — the
caller hung forever. Now the re-read happens *inside* the same lock acquisition that parks the
continuation, and a status that resolved meanwhile resumes immediately.

### Second bug, found in PR review

`statuses()` promised "every authorization transition, including changes made in iOS Settings" and
delivered that for **no** domain: the live implementation only replayed current values and broadcast
what `request(_:)` itself returned. `makeAuthorizationStream()` was written and then never consumed.
A rider who denied location, went to Settings and granted it would have seen S01 sit unchanged — the
documented recovery path, broken.

Now observed properly, from three sources, because the four domains do not report alike:

- **Location** — `LocationManagerState.shared.makeAuthorizationStream()`, now actually consumed.
- **Bluetooth** — `BLEClient.events()` `.stateChanged`, re-reading authorization rather than mapping
  `CBManagerState`, which is the radio and not the permission.
- **Motion and HealthKit** — no framework callback exists for either, so the only way to honour the
  contract is a re-read on `UIApplication.didBecomeActiveNotification`, which is exactly when a rider
  returning from Settings arrives. The re-poll covers all four, since the transition filter makes a
  redundant read free.

`broadcastIfChanged` keeps it a state feed rather than an event storm — `centralManagerDidUpdateState`
fires on every radio toggle and the foreground re-poll on every activation. Observation is started on
the first subscriber and cancelled on the last, so it costs nothing when no one is listening.

Two regression tests cover this, driven through an injected `BLEClient` with a scriptable
authorization answer and a test-driven event stream. `externalChangeIsBroadcast` was confirmed to
**fail** against the unwired version and pass against the fix; `unchangedCallbackIsNotRebroadcast`
pins the transition filter. Both assert on a collected log rather than arrival order, because the
replay and the location observer's opening yield interleave freely.

### Not done here

S01 and `OnboardingFeature` (#106, #105). Always-escalation at first ride start. Any real HealthKit
read — `HealthKitClient` is still the M5 stub, so `.health` is a prompt with no consumer until then,
and `.motion` has no consumer at all yet.

### Verification

407 tests pass, 0 fail, including all five snapshot suites locally. Five of the new tests run the
live client against the real frameworks — the main-actor hop into CoreLocation, the CoreMotion
availability probe, the HealthKit request-status query — asserting agreement with the framework
rather than a fixed value, so they hold on Simulator and device alike. The app was installed and
launched on the Simulator to confirm no startup regression from the `LocationManagerState` move.
A throwaway probe confirmed the Simulator really does report motion unavailable, and the live client
really does map it to `.unavailable`; the probe was deleted afterwards.
