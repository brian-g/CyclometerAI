# #207 — Vehicle pass detector never checks approach distance

Branch: `fix/207-vehicle-pass-approach-distance`

## Diagnosis (done)
Found by analysing a real ride (`system_logs.logarchive` + `Cyclometer_2026-09-06_11-55.gpx`).

`VehiclePassDetector` confirmed a pass on two criteria — tracked >= 2s, and
majority-positive closing speed — neither of which involves range. A vehicle
acquired at 93 m and tracked to **52 m at a constant 46–48 kph closing speed**
before vanishing was recorded as a completed `danger` pass at the rider's
position 52 m early. The other four encounters that ride all closed to 0 m.

The guard meant to catch this could never fire. `parseAlert` decodes closing
speed from an **unsigned** wire byte (`VariaRadarClient.swift:145`), so
`relativeVelocityMPS` is never negative; across 565 target-bearing frames not
one carried even a zero. `positiveSampleCount == sampleCount` always held.

Both specs already required the missing check — PRD §8.7 ("distance decreasing",
"distance reached minimum threshold") and TCA.md §4.12 (`minimumDistance`) — and
both were dropped when #172 shipped.

## Plan
- [x] Add `minimumRangeMetres` to `VehicleTrackingRecord`, folded per tick
- [x] Add `passProximityMetres = 10`, calibrated against the capture
- [x] Replace the majority-positive guard with the proximity check
- [x] Keep `positiveSampleCount`/`Sum` — the pass-speed estimator still uses them (#208)
- [x] Replace the two tests feeding wire-impossible inputs (`mps: -3`, `mps: 0`)
- [x] Add `RadarPassFixtures` + `VehiclePassDetectorReplayTests` over the real capture
- [x] Rework `RideRecordingTests`' end-to-end pair to discriminate by range
- [x] Full suite, then revert-the-fix verification

## Review

**Changed**
- `Features/ActiveRide/VehiclePassDetector.swift` — `minimumRangeMetres` on the
  tracking record, `passProximityMetres = 10`, and the guard swap. Comments
  record why the old guard was inert, why TCA.md's `lastDistance` is deliberately
  omitted, and that the pass-speed estimator's whole-track average is #208's
  problem, not this change's.
- `CyclometerTests/Features/VehiclePassDetectorTests.swift` — `target()` gains a
  `range:` defaulting to 4 m, so existing tracks still read as genuine passes.
  Dropped `turnOffOrSlowdownProducesNoEvent` and `zeroClosingSpeedIsNotApproaching`
  (both fed velocities the wire cannot emit); added five: lost-beyond-threshold,
  exactly-at-threshold, one-metre-short, minimum-retained-after-moving-away, and
  a nil pass-speed estimate for an all-zero track.
- `CyclometerTests/Features/RadarPassFixtures.swift` — **new**. The five real
  radar tracks from 2026-09-06 as `(ms, range, kph)` triples, in source rather
  than a binary capture so they stay diffable in review.
- `CyclometerTests/Features/VehiclePassDetectorReplayTests.swift` — **new**.
  Replays those tracks at their own frame spacing. Also pins that nothing in the
  capture sits between 0 m and 52 m, so the threshold is demonstrably not
  finely tuned — if a future capture narrows that gap, this fails loudly.
- `CyclometerTests/Features/ActiveRideFeatureTests.swift` — `singleSighting`
  gains `range:`; the persistence suite's `vehicle()` moves to 4 m so its
  overtakes still confirm.
- `CyclometerTests/Features/RideRecordingTests.swift` — the end-to-end pair now
  differs by range (4 m vs 60 m) instead of closing-speed sign. `recedingVehicle`
  renamed `lostVehicle`, since a receding vehicle is not something the hardware
  can report.

**Verification**
- Full `CyclometerTests` (snapshot suites skipped, as CI does): **739 passed, 0
  failed**. Baseline on `main` was 732; net +7 (five new unit tests, four replay
  tests, two removed).
- Reverted the guard to `positiveSampleCount * 2 > sampleCount` and re-ran the
  three affected suites: 40 cases ran (count checked, not just the exit code),
  **7 failed** — including `vehicleLostBeyondThresholdProducesNoEvent`,
  `capturedTracksAreClassifiedCorrectly`, and the end-to-end
  `vehiclePassesAgreeAcrossPersistenceAndGPX`. Restored and re-confirmed green,
  with every new test verified present by name.

**Guard against recurrence**
The replay suite pins real hardware output, so the criteria can no longer be
"verified" by inputs the wire cannot produce — which is exactly how #172 shipped
with an inert guard and a ticked acceptance criterion.

**Not done (tracked separately)**
- #208 — `estimatedPassSpeedKph` still exports a whole-track mean of *closing*
  speed, understating genuine passes by 13–27 kph on four of the five captures.
- #209 — `alertLevelAtPass` still snapshots the least severe instant of the
  encounter.
- Making `relativeVelocityMPS` non-negative by construction would make the
  impossible test inputs unrepresentable. It is the deeper fix and touches every
  radar consumer, so it stayed out of scope here.
