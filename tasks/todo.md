# Issue #100 — S11 flat device list per Design.sketch

Branch `feat/100`, from `main` (#121 merged as `3ed86f1`). Milestone M10, Wave 2.

Two things, not one. The issue body describes only the layout, but `DeviceManagementFeature.swift:15-17`,
`DeviceManagementView.swift:4-6` and BLE.md §6 all name #100 as the issue that also adds radar and heart
rate pairing — "pairing is still CSC-only … until #100". Acceptance criterion 2 (a paired sensor out of
range can still be unpaired) only holds once that write path exists.

Spec: UX.md §S11, `assets/design/Design.sketch` — S11, BLE.md §5.0 / §6.
Note the "§1.3" in the M10 issue footers is a *document version number*, not a section.

## Decisions (user-approved plan)

- **Scan stays filtered to radar / HR / CSC**, resolving the open question at UX.md:824. The Sketch's Quarq
  power meter and ENGO 3 glasses illustrate the layout, not a requirement. `BLECentral` already scans
  filtered by `ServiceUUIDs.allMVP`; listing everything needs a new unfiltered transport path and a fourth
  discovery source with no owning client.
- **Row icon is an SF Symbol per `SensorKind`.** The `assets/icons/` SVGs are FontAwesome exports, not SF
  Symbol templates; the Sketch's leading images are embedded product photos.
- **Helper text is the section header**, `.textCase(nil)` at `.body`, scrolling with the list. Large
  navigation title, matching the Sketch's spacing (helper text at y=168 from the frame top).
- Snapshot breadth and the full behavioural matrix belong to **#108** (Wave 5); this issue carries only
  tests for what it changes, and does not build S02 (#107).

## Tasks

- [x] 1. `SensorKind+Presentation.swift` — per-kind SF Symbol table
- [x] 2. Reducer: `listedDevices`, `pairedIDs`, `unambiguousRoles(of:)`
- [x] 3. Reducer: `.pairButtonTapped` branches on kind; combo unions into the CSC commit
- [x] 4. Reducer: `apply` record removal kind-scoped, pushes to all three clients
- [x] 5. Reducer: `.unpairButtonTapped` releases every role the peripheral holds
- [x] 6. View: `DeviceListView` / `DeviceManagementView` split, flat section, helper header
- [x] 7. View: `DeviceRow` icon + Pair/Unpair on durable tenancy; scanning row and empty footer
- [x] 8. `SensorRowButton` restyled to a trailing text button (`.borderless`)
- [x] 9. Reducer tests — radar/HR pair, unpair, collision, combo, ordering log
- [x] 10. `DeviceManagementSnapshotTests` at 402pt, light + dark; CI skip entry
- [x] 11. UX.md §S11, BLE.md §5.0/§6, stale `#100` code comments
- [x] 12. Build + full local suite green

## Review

**The reducer was mostly there; the layout was the smaller half.** #98 had already unified discovery and
#99 the collision gate, so the work split into a view rewrite and one real behavioural gap — radar and
heart rate had no write path at all. The clients made that gap cheap to close:
`VariaRadarClient.setPairedSensor` and its HR twin move the gate and the connection identity inside one
critical section, so a radar pairing is a single call, displacing an incumbent radar is a single call, and
records-before-teardown holds without anything to order. Radar Pair therefore needs no `pendingPairing`
and no interrogation — it goes straight to the collision check.

**Three decisions that were not in the issue.**

- **A Pair tap claims every profile the peripheral advertises, in one write.** A flat list gives a device
  one row and one button, so "pair the CSC half now and the HR half later" no longer has a control to sit
  on. The role prompt still covers only speed and cadence; the unambiguous roles are unioned into the same
  commit, so one collision check runs over the whole claim.
- **Unpair therefore releases everything.** This reverses the M6 comment on `unpairButtonTapped` ("CSC
  records only … the radar pairing was made elsewhere"), which described a screen on which radar could not
  be paired at all. Claiming one profile of an already-paired device is now unpair-then-pair.
- **`apply` scopes by `SensorKind`, not by `isCSC`.** That is #93's rule generalised: a claim removes a
  peripheral's records only within the kinds it is claiming, so a CSC reassignment cannot delete the radar
  record behind the same UUID.

**`SensorRowButton` gained a style rather than being restyled.** UX.md §S11 asks for a trailing *text*
button, but the capsule has a second call site in the Start sheet (S05.1), whose design was not this
issue's to change. `.buttonStyle(.borderless)` on the text style is load-bearing rather than cosmetic —
the default style in a `List` claims the whole row, which would swallow the tap role reassignment needs.

**A contract change the tests had to absorb.** `.pairButtonTapped` now reads the row's `kinds`, so a
peripheral the store has never seen is a no-op. Eighteen tests were sending a Pair tap against a device
delivered only by the *following* `.devicesUpdated` — a shortcut, since the button only exists because
discovery put the row on screen. They now seed the row (`rowToPair`). The alternative, falling back to the
CSC path for an unknown peripheral, would have meant opening a connection on the chance it speaks 0x1816.

**Snapshots needed a device config, not a fixed canvas.** The first references had the large title flush
at x=0: a `NavigationStack` takes its title's leading margin from the window's layout margins, and a bare
`.fixed` canvas has no window. Recorded against a `ViewImageConfig` at 402x874 with the iPhone 17 Pro's
safe areas instead, so the reference pins the layout the app actually shows. Verified stable across two
runs — the scanning spinner renders deterministically.

**Not done here, deliberately:** S02 — Add Sensors (#107) reuses `DeviceListView`, but building that
screen is its own issue; #108 owns the full behavioural matrix and the S01/S02/S12 snapshots.

---

## Follow-on — S05.1 Start sheet shows paired sensors (part of #90)

Asked for after #100 landed: the Start sheet must show paired-but-not-connected sensors, and a disconnected
sensor must show its status rather than "Tap to Pair".

**The sheet was keyed on live client status, not on the records.** `status(from:)` mapped `.disconnected` to
`.notPaired`, and the view filtered `.notPaired` out — so a paired sensor that was merely out of range
vanished from the sheet entirely. Worse, `.scanning`/`.connecting`/`.reconnecting` mapped to `.searching`,
which rendered "Tap to Pair" on a sensor that was *already paired*. Both fall out of the same fix: rows now
come from `preferences.pairedSensor(for:)`, and the name comes from `PairedSensor.displayName`, which is the
only source that survives being out of range.

**The finding that set the copy.** `startScanning` is only called once a ride is active (`ActiveRideFeature`,
`SpeedFeature`, `CadenceFeature`), and ride finish calls `disconnect()`. So *nothing scans while the Start
sheet is open* and almost every row reads not-connected on every ride setup. "Searching" — what UX.md §S05.1
specified and the old badge said — would have been a claim about a search that isn't running. Brian's call:
show **Disconnected**, and do not make the sheet scan. §S05.1 is updated to two states with the reason, and
the open question (should the sheet hold a pairing scan so the status means something during setup?) is
recorded against #90.

**Two removals fall out of it.** `pairButtonTapped` is gone: with rows keyed on the records, the state that
reached the button is unreachable, and offering it would need discovery this sheet does not run. That left
`SensorRowButton.Style.capsule` with no callers, so the enum #100 added to keep the Start sheet's capsule
intact is collapsed back to the plain text button S11 wanted in the first place.

**Corrected same day, after Brian pushed back.** The version above showed every row as Disconnected because
nothing scans while the sheet is open — technically honest, useless in practice. The sheet now holds a
pairing scan open per client while it is up (`beginPairingScan` on `.task`, balanced on `.onDisappear`),
which is the S11 pattern: refcounted, independent of the ride's scan, and the clients connect only what the
rider has paired. Status is live, the badge is back to UX.md §S05.1's **Connected / Searching**, and the ride
now starts with its sensors already connected because a connection outlives the scan that found it.

**A real bug behind the other half of the complaint.** Battery never appeared on S11 for radar or HR.
`DiscoveredDevice.batteryPercent` is read from a client field, and 0x180F answers well *after* the
connection that carried it — but `VariaRadarClient.setBattery` and `BLEHRClient.setBattery` told only their
`batteryLevel()` subscribers and never re-broadcast the device list, so the row kept the `nil` it was built
with, permanently. `BLECSCClient` never had the bug: its level lands in the slot and
`recomputeRoleStatesLocked` broadcasts from there. Both now call `broadcastDiscoveredLocked()`.
`batteryReadRefreshesTheDeviceList` in each client suite is the regression test, and it was **verified to
hang with the fix reverted** rather than assumed to cover it — the first attempt at that check ran zero
tests, because `-only-testing` with a Swift Testing function name matches nothing and exits 0.

**Still open in #90:** the empty state is plain text ("No paired sensors"), not the progress indicator and
quick-pair affordance that issue asks for.

---

## Review pass (`/code-review`, 2026-08-21)

Four findings, all verified in the code before acting and all fixed. Each fix was checked by reverting it
and watching the new test fail.

1. **The Start sheet's pairing scan was never released.** `.onDisappear` cannot reach a `@Presents` child's
   reducer — see `lessons.md`. Ownership moved to `AppFeature`, around the presentation.
   `StartSheetPresentationTests` covers all three exit paths and the two-opens-balance case.
2. **A second Pair tap clobbered a pairing in flight.** `rowTapped` had guarded this since #99 and
   documented exactly the hazard; the radar/HR branch I added did not. Both the CSC and the non-CSC path are
   now behind the same `pendingPairing == nil` guard — the CSC half was a pre-existing hole.
3. **A CSC answer could displace a strap the rider never mentioned.** Folding unambiguous roles into the
   role prompt's answer raised a replace-or-cancel alert about heart rate when the rider had been asked
   about wheel and crank data — and cancelling it, the natural response, ran the in-flight release and threw
   away the speed pairing they *had* chosen. Unambiguous roles now ride along only where free.
4. **Empty-state copy** — the spec followed the view rather than the reverse ("No paired sensors").

Not acted on: the `.sketch` → Git LFS migration has no `lfs: true` on `actions/checkout`. CI never reads the
file, so nothing is broken there, but a fresh clone without `git lfs install` gets a pointer — Brian's
commit and Brian's call.

**A snapshot that recorded nothing.** The first attempt pinned the whole sheet and produced six blank white
references — `StartSheetView`'s toolbar renders empty inside a `UIHostingController`, verified by ladder
(plain `NavigationStack`+`List` renders; adding the sheet's toolbar items blanks it). Two runs had passed
against those blanks. `StartSheetSnapshotTests` now pins `SensorStatusRow` instead, which is the thing that
changed, and `lessons.md` carries the rule.

**Verification.** Full local suite green in parallel — **500 passed, 0 failed**. Five BLE *integration* tests
(`BLECSCClientTests`, `BLEHRClientTests`, `VariaRadarClientTests`) fail under
`-parallel-testing-enabled NO`; that is pre-existing and unrelated — they are the timing-sensitive harnesses
`lessons.md` already flags, none of the files in this change is theirs, and `main` fails the same five the
same way.

**Verification.** Full local suite green — **491 passed, 0 failed**, all 48 suites present including the
new `DeviceManagementSnapshotTests`. `DeviceManagementFeatureTests` is 53 cases. App builds, installs and
launches clean on the simulator. In-app navigation to S11 was not driven by hand — there is no tap
affordance from `simctl` — but the snapshot suite renders the real view, store and reducer at device size,
which is the stronger check.
