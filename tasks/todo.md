# #208 — estimatedPassSpeedKph exported a whole-track mean of *closing* speed

Branch: `fix/208-pass-speed-ground-speed-peak`

## Diagnosis (done)
Two defects in one field, both visible in `Cyclometer_2026-09-06_11-55.gpx`.

**A relative speed presented as an absolute one.** The Varia wire byte is closing
speed. Three of that ride's five events exported a "pass speed" at or below the
rider's own (`riderSpeedKph 33.6 / estimatedPassSpeedKph 26.9`).

**Averaging the whole track biases it low.** Radar measures only the radial
component, which decays by cos(theta) as a vehicle draws alongside, so the tail
near the rider drags the mean down — by 13–27 kph on the four genuine overtakes.

PRD §8.7 never said which speed the field carried, so the semantics had to be
settled first. **Decided: the vehicle's ground speed.** Appendix B's own worked
example (62.1 against a rider at 28.4) is only coherent that way, and the issue's
"must exceed riderSpeedKph" criterion is unsatisfiable by a closing speed.

## Plan
- [x] `VehicleTrackingRecord`: replace `positiveSampleCount`/`positiveSampleSum`
      with one `maxPositiveClosingMPS`, clamped at 0 on both the seed and the fold
- [x] Emit `(lastRiderSpeedMPS + maxPositiveClosingMPS) * kphPerMPS` — one multiply,
      so a whole-m/s test input lands on an exact decimal
- [x] PRD §8.7 field table + new prose; PRD §10 and Appendix B comments;
      DataModel.md §3.4 annotation
- [x] Replace `estimatedPassSpeedIsAverageOfPositiveSamples` with peak, decaying-tail
      and constant-speed tests; add three replay tests against the real capture
- [x] Full suite green — 789 cases, every new test confirmed present by name

## Why the peak, not a smarter estimator
Across all five captures, `max` equals the far-field plateau **exactly** (59/54/54/
47/48), and the peak is held for 4–12 consecutive frames with the next distinct
value always 1 kph below — no isolated spikes to reject. A range-gated far-field
mean is *worse* (42.2 vs a 54 plateau on pass1200_09, which decelerated from 135 m).
`max` is also a single Double, preserving the O(1) fold the record exists to defend.

## Verified by reverting, not by reasoning
The change has two independent halves, so each was reverted separately:

| revert | constant-speed test | the other four |
|---|---|---|
| whole-track mean, rider term kept | **passes** | fail |
| peak kept, rider term dropped | fails | fail |

Both halves are load-bearing, and the constant-speed test is genuinely invariant
under the mean→peak switch — which is what this issue's stale AC #4 was asking for.

## AC #4 was stale and is ticked with a correction
It asked that the 16:01:03 capture "stays at constant range and closing speed" and
be "unchanged by the estimator switch". Three things wrong: #207 (9fa2dfd) now
rejects that vehicle at 52 m so it produces **no event at all**; its range is not
constant (93 m → 52 m); and "unchanged" was never literally true even before (max
48 vs mean 47.1). The intent — the switch is a no-op without a decaying tail — is
pinned by `constantClosingSpeedIsUnchangedByTheEstimatorSwitch` instead. Recorded
rather than silently ticked, which is how #172 shipped an inert guard.

**Not done (tracked separately)**
- #209 — `alertLevelAtPass` still snapshots the least severe instant of the encounter.
- `sampleCount` is now write-only: nothing reads it since #207 deleted the majority
  check. Removing it is a clean follow-up, but it churns three test files for a
  reason unrelated to this issue.
- PRD §8.7's "Pass detection logic" block and TCA.md §4.12 still describe the
  majority-positive criterion #207 deleted, and OQ15 is still Open though #207
  settled it at 10 m. #207's debt, left alone here.
- Making `relativeVelocityMPS` non-negative by construction is now *more* attractive:
  after this change, two `max(_, 0)` clamps are the only thing defending the invariant.
