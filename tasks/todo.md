# Issue #71 — Spike: CoreBluetooth state restoration + background modes decision

Branch: `spike/71-ble-background-modes`. Milestone M6. Output is a decision note in
`assets/BLE.md` plus the plist change that follows from it.

## Decisions (user-approved plan)
- Adopt `bluetooth-central` background mode — background scanning is gated on it, and
  mid-ride discovery of a sensor that was off at ride start is a real scenario.
- Defer full `CBCentralManager` state restoration to M7 — it only pays off once ride
  state survives termination, and `CoreDataStack` has no checkpointing yet.
- Adopt `audio` background mode; record the `.ambient`-category background-playback gap
  as an M4 constraint rather than fixing it here.
- Correct `BLE.md` §11's deprecated `NSBluetoothPeripheralUsageDescription` requirement.

## Tasks
- [x] 1. `Info.plist` — add `bluetooth-central` + `audio` to `UIBackgroundModes`.
- [x] 2. `assets/BLE.md` §11 — drop the deprecated plist key, match the shipping Info.plist.
- [x] 3. `assets/BLE.md` — new §13 decision note (questions, decisions, rationale, M7
      revisit trigger, M4 audio constraint, restoration cost breakdown).
- [x] 4. `assets/BLE.md` — bump the spec version line (v1.1 → v1.2).
- [x] 5. `BLEClient.swift` — comment at the `CBCentralManager` init recording the deferral.
- [x] 6. Build + full test suite; confirm no regression past the known baseline failure.
- [x] 7. Comment on #63, #67, #68, #69, #70, #71 recording M6 order + shared blockers.

## Review

All seven tasks complete. Four files changed, one of them code — the spike's output is
a decision record, so the diff is deliberately small.

**Decisions recorded in BLE.md §13.** Adopt `bluetooth-central` (background *scanning*
is gated on it regardless of whether location keeps the process alive — without it, a
sensor powered on mid-ride is never discovered while the phone is pocketed). Adopt
`audio`. Defer state restoration to M7, with an explicit revisit trigger: it only pays
off once a terminated ride is recoverable, and `CoreDataStack` has no checkpointing yet.
§13.4 itemizes what adopting restoration would require so the M7 issue can be written
from it — the substantive item is that `BLECentral.connectionOwners` has no CoreBluetooth
equivalent and can only be rebuilt from #67's persisted `PairedSensor` records.

**Evidence quality — stated plainly in §13.1.** No hardware was available, so the three
background-behavior questions are reasoned from documented platform behavior, not
measured. Marked *unverified* in §13.2, each with a `log collect` procedure to run on a
device. The decisions were chosen to stay safe if the reasoning is wrong.

**Finding handed to M4 (#33).** Audio.md specifies `.ambient` for the All Clear and
Warning tones so they respect the silent switch, but `.ambient` neither survives
backgrounding nor plays through the switch — so as specified, a rider with the phone
pocketed and the screen locked hears no Warning tone, which is the exact case Audio.md's
"jersey-pocket audible" requirement targets. The `audio` background mode is necessary but
not sufficient, and iOS exposes no API to read the switch position, so category choice
alone can't satisfy both goals.

**Also corrected:** BLE.md §11 required `NSBluetoothPeripheralUsageDescription`,
deprecated since iOS 13 and applicable only to peripheral-role apps. The shipping
Info.plist was already correct; the spec was wrong.

**Verification.** Build succeeds; `UIBackgroundModes` confirmed in the *built* app bundle
via PlistBuddy, not just the source plist. Full `CyclometerTests` suite run: the only
failure is `HeroNumberSnapshotTests.testCustomColor()`, documented in CLAUDE.md as
pre-existing. Device verification of Q1–Q3 remains outstanding and is the real acceptance
criterion.

**M6 ordering** (posted to the six open issues):
`#71 → BLEClient.readValue → #69 → #68 → #67 → #70 → #63 → #72`. The #67/#68 "circular
dependency" was an artifact of both issues claiming "PairedSensor persisted"; the real
edge is one-directional. Two unnamed prerequisites surfaced: `BLEClient` has no
characteristic read operation (blocks #67 and #63), and no SwiftData plumbing exists
(blocks #69, #67, #70).
