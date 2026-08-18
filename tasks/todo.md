# Issue #98 — Unified discovery: one device stream across radar, HR and CSC

Branch: `feat/98-unified-discovery`, from `main` (#119 merged as `03ed24a`). Milestone M10, Wave 2.

`DeviceManagementFeature` declared one dependency — `bleCSCClient` — so S11 could only ever show
speed/cadence sensors. Worse than cosmetic: `BLECentral` issues a *filtered* scan, and the only pairing
scan anyone started was `bleCSCClient.beginPairingScan()`, so radar and HR were not scanned for at all
outside a ride. With #97's gates closed there was no route to a `.radar` or `.heartRate` record
whatsoever. This lands the cross-client scan and the merged list that #100 and #99 build on.

Spec: UX.md §S11; BLE.md §5.0 (write ordering), §6 (discovery is not adoption), §8 (service UUID lookup).
Note the "§1.3" in the M10 issue footers is a *document version number*, not a section.

## Decisions (user-approved plan)
- **List only — #100 still owns radar/HR pairing.** BLE.md §6 already assigned writing those records to
  #100, and #100's ACs cover pair/unpair for every kind. All four of #98's ACs stay testable by seeding
  records into `AppPreferences`. Accepted consequence: a row holding only radar or HR roles lists and
  reports status but carries no action, and both gates stay closed for one more PR.
- **One `DiscoveredDevice`.** It absorbed `BLECSCClient.DiscoveredSensor` and gained
  `kinds: Set<SensorKind>`. `ConnectionState` and `Capabilities` moved to `Models/` with typealiases left
  inside the clients, so no existing call site changed.
- **Kept the Paired / Available sections.** #100 owns the flat Sketch layout, title, icons and helper text.

## Tasks
- [x] 1. `Models/SensorKind.swift`, `SensorConnectionState.swift`, `CSCCapabilities.swift`;
      `Clients/BLE/BLEServiceUUIDs.swift`.
- [x] 2. `DiscoveredDevice` merged shape + `merged(with:)`; `SensorRole.kind`; `AppPreferences.pairedRoles`.
- [x] 3. `BLECSCClient` — `DiscoveredSensor` deleted, emits `DiscoveredDevice`, endpoint renamed
      `discoveredSensors` → `discoveredDevices`.
- [x] 4. `VariaRadarClient` — `beginPairingScan`/`endPairingScan` + `isScanning`; guarded `stopScanning`
      **and `disconnect`**; widened discovery row.
- [x] 5. `BLEHRClient` — same four, plus `connectionStateLocked(for:)` projecting its two flags onto the
      shared enum.
- [x] 6. `DeviceManagementFeature` — three deps, `sources: [SensorKind: [DiscoveredDevice]]`, merged
      `devices`, sections widened to `pairedRoles`, `.refreshRequested`.
- [x] 7. `DeviceManagementView` (`.refreshable`, CSC-only action, footer copy) + `SensorDemoData`.
- [x] 8. Client tests — 5 radar + 4 HR pairing-scan cases, `testValue` smoke coverage.
- [x] 9. `DeviceManagementFeatureTests` — one `ScanCall` log across all three clients; 8 new cases.
- [x] 10. `assets/BLE.md` §6 and §8, version → 1.2.
- [x] 11. Build + full local suite green — **503 passed, 0 failed** (484 on `main`).

## Review

**Shipped.** One `DiscoveredDevice` across all three clients, tagged by `SensorKind` derived from the
advertised service UUID, merged and deduped by `peripheralID` in `DeviceManagementFeature`. Each client
carries the #68 refcount, and S11 holds one pairing scan open per client, balanced on appear, disappear
and refresh.

**The bug the plan predicted, and it was real.** `stopScanning` was not the only unconditional release —
`disconnect()` on both single-slot clients also dropped its service UUID from `BLEClient.requestedServices`,
which has no per-caller refcount. Finishing a ride with the Sensors screen open would have silently blinded
it. Both are guarded now, and `disconnectRespectsPairingScan` on each suite is the assertion.

**A second unconditional release the plan didn't predict.** `BLEHRClient`'s reconnect *is* a rescan —
the `.disconnected` handler re-issues `startScanning` directly, bypassing the `startScanning()` endpoint —
so `isScanning` stayed false through it. A strap dropping mid-ride while the Sensors screen was open would
have had its reconnect cancelled the moment the rider closed that screen. The rescan now registers as the
ambient scan it is. `reconnectRescanCountsAsAmbient` was checked against a patched-out fix and does fail
without it.

**A behaviour change worth naming.** #93's `nonCSCPairingDoesNotHideTheDevice` asserted that a CSC-capable
peripheral already paired for heart rate sat under *Available* with a Pair button — correct while the screen
was CSC-only. Now that the list spans all three kinds it sorts into Paired, because it *is* paired. What #93
actually protects survives: the row's button keys on CSC tenancy (`DeviceRow.holdsCSCRole`), not on
`isPaired`, so both CSC roles are still free and it keeps a Pair button rather than an Unpair one that would
silently do nothing. The test was updated to assert the new placement *and* the surviving guarantee.

**A drive-by the unification paid for.** `StartSheetFeature` carried two character-identical `status(from:)`
overloads that existed only because the radar and CSC `ConnectionState` enums were distinct types. One
`SensorConnectionState` collapsed them into one function.

## Follow-up — stale devices never left the list

Reported after the merge: a radar, strap or cadence sensor switched off stayed under Available for the life
of the process. `discoveredIDs` was an inventory all three clients documented as "never pruned".

There is no lost-peripheral callback to hook: `BLECentral` scans without
`CBCentralManagerScanOptionAllowDuplicatesKey`, so CoreBluetooth reports each peripheral **once per scan
session** and a device that goes quiet just stops arriving. Restarting the session is the only way to
re-establish the truth, and `beginPairingScan` already does exactly that.

- Each `beginPairingScan` rotates a **scan generation** (`sightedThisGeneration`); anything that failed to
  re-advertise across the generation just ended is dropped, so a device goes at worst two intervals late.
- `DeviceManagementFeature` runs a `clock.timer` at `sweepInterval` (10s) while S11 is open, sending the same
  `.refreshRequested` the rider's pull sends — one path, not two that could drift.
- **A connected peripheral stops advertising**, so the sweep exempts what each client holds (`slots.keys` for
  CSC, `targetPeripheralID` for the single-slot clients). Without that it would delete the row for the sensor
  in use. Three `…SurvivesSweep` tests pin it.
- Duplicate-allowed scanning was considered and rejected — per-second precision at a battery cost Apple warns
  against, for a screen open seconds at a time.

Two things the tests taught me. `.task` now starts an effect that never finishes, so it took a `CancelID`
cancelled from `.onDisappear` — worth doing regardless, since the three device streams were previously
outliving the screen on nothing but SwiftUI tearing down the view's task scope. And the first drafts of the
sweep tests were racy: `devices { $0.count == 2 }` is already true before a re-advertisement lands, so it
proves nothing as a sync point — they now re-advertise under a changed name and wait for that. Verified by
disabling the sweep: the HR and radar cases fail (60s time limit) without it.

**Sequencing note for #100.** Two things are waiting on it, both deliberate. Radar and HR rows render with
no action, so the gates from #97 are still closed — #100 writes the records that open them. And a peripheral
paired in one role cannot yet claim a second from this screen (`reassignableIDs` is CSC-keyed); that is the
multi-role case #99 owns, and it is unreachable today because nothing writes a non-CSC record.
