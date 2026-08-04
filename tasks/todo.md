# Issue #69 — Wheel circumference presets + manual entry

Branch: `feat/69-wheel-circumference`. Milestone M6.

`BLECSCClient.setWheelCircumference` had zero production callers, so every ride ran on the
hardcoded 2096 mm default while `SettingsFeature.selectedWheelSize` was a cosmetic String. This
connects the three pieces: a persisted circumference, an mm-valued picker, and a push into the CSC
client — and carries M6's persistence prerequisite for #67 and #70.

## Decisions (user-approved plan)
- **AppPreferences is not a SwiftData `@Model`** — a `Codable` struct persisted via
  `@Shared(.fileStorage)`. One record, nothing to query, no relationship worth traversing; SwiftData
  would force an async load in front of the Settings screen for one `Int`. swift-sharing 2.8.0 is
  already in the resolved graph via TCA, so no package change. DataModel.md §3.6 updated to match.
- **In-place picker**, not a detail screen — the existing `Picker("Wheel Size")` row keeps its
  position; only its values change, plus a conditional mm field when Custom is selected.
- **Scope is wheel circumference only.** Units and the three toggles stay in-memory as they were.

## Tasks
- [x] 1. `Models/WheelPreset.swift` — 8 PRD §8.9 presets, mm as raw value, bounds 1,500–3,000.
- [x] 2. `Models/AppPreferences.swift` — Codable struct + type-safe `.appPreferences` shared key.
- [x] 3. `SettingsFeature` — `@Shared` preferences, `WheelSelection`, draft + validation, single
      `apply(_:to:)` funnel that persists and pushes to `bleCSCClient` together.
- [x] 4. `SettingsView` — preset picker + conditional Custom row, bounds footer, focus-loss commit.
- [x] 5. `SpeedFeature` — `@SharedReader`; `setWheelCircumference` before `startScanning()`.
- [x] 6. Drop the now-dead `SettingsDemoData.wheelSizes`.
- [x] 7. Tests — `SettingsFeatureTests`, `WheelPresetTests`, one new `SpeedFeatureTests` case.
- [x] 8. `assets/DataModel.md` — §1, §2, §3.6, §3.7, §3.8, §9; version 1.1 → 1.2.
- [x] 9. Build + full test suite; confirm no regression past the known baseline failure.
- [x] 10. Document the Phase 2 multi-bike model — new DataModel.md §3.9 (bikes own wheelsets and
      sensors), cross-referenced from PRD §8.9 + Phase 2 roadmap, UX S05.1/S05.2/S12, and the
      `AppPreferences.wheelCircumferenceMM` doc comment.

## Review

**The number pad has no return key.** `.onSubmit` would never fire on a `.numberPad` TextField, so
the manual entry commits on focus loss (`@FocusState` + `.onChange`), with a keyboard Done button
to give the rider a way out of the field. This was the one thing the plan got wrong.

**No lifecycle action — the manual field needs neither `.onAppear` nor `.task`.** The first cut
seeded a `String` draft from an `.onAppear` action, which put `String(preferences.wheelCircumferenceMM)`
in four places and re-clobbered the draft on every tab switch. The draft is now
`customCircumferenceDraft: String?`, where `nil` means "not editing" and the displayed text falls
through to the persisted value. That deletes the action, the seeding at `.wheelSelectionChanged(.custom)`,
and the seeding in `apply` — and reverting a rejected entry becomes `draft = nil` rather than
re-deriving the string. `.task` would have been the wrong replacement regardless: it exists to bind
a cancellable *async* effect to view lifetime, and this work is a synchronous state read.

**Presets are labelled as printed on the sidewall, without the circumference.** "700 x 25c",
"650b x 47", "29 x 2.1" — riders pick by tire size, and showing the mm value alongside made the
collapsed row wrap to two lines for the longest label. The millimetre value now appears only under
Custom, where it is the thing being edited. PRD §8.9's acceptance criterion said presets show "tire
label and circumference in mm", so that line was updated rather than left contradicting the build.

**Custom-vs-preset is derived, not stored.** `wheelSelection` reads the persisted value through
`WheelPreset(rawValue:)` — every circumference in the spec table is distinct, so that lookup is
unambiguous, and a manual (or, once #70 lands, auto-calibrated) value still reads as Custom after a
relaunch with no extra persisted flag. `userChoseCustom` is ephemeral UI state covering the one case
the derivation can't: picking Custom while the current value happens to equal a preset.

**Both write paths funnel through `apply(_:to:)`** so the persisted value and the value driving the
speed derivation cannot drift apart. Rejected entries never reach it — the reducer drops the draft
and returns `.none`, so no BLE call is made. Committing an *unchanged* value is
also a no-op: picking a preset while the manual field has focus tears the field down, which fires a
focus-loss commit for the value the preset just wrote, and without the guard that pushed twice.

**Applied before scanning, not after.** In `SpeedFeature.startListening` the circumference is set
ahead of `startScanning()` so it is in place before the first measurement can arrive.
`startListeningAppliesPersistedCircumference` asserts the call *sequence*, not just the value.

**Tests: 10 new cases, all green.** `WheelPresetTests` guards the eight presets against the PRD
table (values, labels, spec order) and asserts uniqueness, which the `rawValue` lookup depends on.
Full suite passes except the known pre-existing `HeroNumberSnapshotTests.testCustomColor()`.

**One flake caught and fixed during verification.** `customEntryWithinBoundsIsApplied` passed on one
suite pass and failed on the other: swift-sharing's `defaultFileStorage` is a single process-wide
in-memory instance in tests, so a circumference persisted by one test was still there for the next.
`FileStorage.inMemory` builds a *fresh* file system per access, so each store now takes its own, with
seeding inside the same dependency scope — otherwise the seed and the store read different storage.
Three consecutive suite runs, zero failures.

**MVP assumes one bike with one wheelset, and that is now written down.** A single global
`wheelCircumferenceMM` and role-keyed sensor pairing are scoping decisions, not the end state —
riders own several bikes, and a bike carries several wheelsets. DataModel.md §3.9 specifies the
Phase 2 shape (Bike owns Wheelsets and per-bike sensors; heart rate stays rider-scoped) and names
the two limitations that follow from the MVP model: swapping wheelsets loses the calibration learned
for the other set, and swapping bikes means re-pairing. Both are accepted, not bugs. This matters
most for #67 (role-keyed pairing needs to grow a bike dimension) and #70 (calibration will need to
write per wheelset, not globally).

**Left alone deliberately:** `SwiftDataStack` (still an empty schema), `CoreDataStack`,
`CyclometerApp`'s inline `Item` container, `BLECSCClient`, `ActiveRideFeature`. Also untouched: the
Settings units picker is still a disconnected `String` and `ActiveRideFeature.unitSystem` is still
seeded from `Locale` — out of scope here, noted in DataModel.md §3.6 as follow-up.
