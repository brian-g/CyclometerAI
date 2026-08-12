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
