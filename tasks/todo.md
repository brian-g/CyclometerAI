# #209 — `alertLevelAtPass` recorded the least severe instant of the encounter

Branch: `fix/209-alert-level-at-peak`

## Diagnosis (done)
`VehicleTrackingRecord.lastAlertLevel` was overwritten on every tick a vehicle was
present and read when the pass was confirmed. Radar measures the *radial* component
of closing speed, so the last tick a vehicle is seen — alongside the rider — is where
that speed, and therefore the derived `AlertLevel`, bottoms out. Every persisted event
carried the least severe instant of its encounter.

`Cyclometer_2026-09-06_11-55.gpx` shows the ordering inverted: the 11:58:48 pass peaked
at **59 kph** closing, nearly 2× `dangerClosingSpeedKPH`, and shipped as `caution` on a
last-seen 25; the 12:00:50 pass peaked at only **47** and shipped as `danger` on a
last-seen 32. Live L1–L3 escalation was correct throughout — `AlertOrchestratorFeature`
reacts to the current tick, as it should. Only the recorded history was wrong.

## Which instant, and whose severity
`processTick` is handed a **ride-level** alert — `AlertLevel.level(for: targets)` over
every current target (`ActiveRideFeature:545`) — and stamps it on every tracked vehicle.
The issue's Scope wording (a running max over the encounter) would have fixed the
wrong-instant bug and added a new one: another vehicle's severity leaks in, and since a
max only rises it is sticky for the rest of the track. `level(for:)`'s
`approaching.count >= 3` clause alone would then stamp `caution` on every pass in
traffic regardless of speed.

**Decided: the ride-level alert at the tick where *this vehicle's* closing speed peaked.**
Not sticky, and it lands on the same sample `estimatedPassSpeedKph` already uses (#208),
so the two exported fields finally describe one moment. Cross-vehicle influence at that
single tick is kept deliberately — it is the level the rider was actually alerted at —
and is pinned by a test rather than left accidental.

## Plan
- [x] `VehicleTrackingRecord`: `lastAlertLevel` → `alertLevelAtPeakClosing`, moved out of
      the at-pass doc block that still covers `lastKnownCoordinate`/`lastRiderSpeedMPS`
- [x] Fold the two peak-derived fields together under one strict `>`, which also subsumes
      the clamp the plain `max` carried — a negative sample cannot beat a non-negative store
- [x] Document the deliberate three-field asymmetry at the emission site (AC3), so
      `riderSpeedKph` is not later "fixed" into agreement with the other two
- [x] PRD §8.7 field table + new prose; PRD §10 comment; Appendix B worked example;
      DataModel.md §3.4 annotations
- [x] Five new tests; two existing expectations flip and become regression pins
- [x] Full suite green — 794 cases (789 + 5), exit 0

## Why `>` and not `>=`
Peaks in the capture are held for 4–12 consecutive frames, so a tie has to resolve
somewhere. `>` keeps the *first* frame of the plateau — the acquisition frame at
87–135 m, where theta is near zero and the radial component is the true speed
difference. `>=` would walk the level forward across the plateau and settle on the frame
nearest the rider, which is the geometry this issue exists to get away from.
`plateauKeepsTheFirstFrameAtThePeak` pins it.

## Verified by reverting, not by reasoning
Moving `alertLevelAtPeakClosing = alertLevel` back out of the `if` (restoring
last-sighting semantics) fails exactly eight tests and no others:

| suite | failing under revert |
|---|---|
| `VehiclePassDetectorTests` | `alertLevelIsTakenFromThePeakNotTheDecayingTail`, `plateauKeepsTheFirstFrameAtThePeak`, `recordedLevelIsTheRideLevelAlertAtThePeakTick`, `overtakeProducesOnePassEvent`, `trackingIsIndependentPerVehicle` |
| `VehiclePassDetectorReplayTests` | `overtakesRecordThePeakAlertLevel`, `theSeverityInversionIsGone`, `genuineOvertakesProduceAWellFormedEvent` |

Every #208 pass-speed test stays green across that revert, so the two changes are
independently load-bearing.

## All four captured passes now read `danger`
Peaks are 59 / 54 / 54 / 47 kph, every one past the 30 kph threshold, against last-seen
values of 25 / 24 / 23 / 32. The shipped GPX's `caution, caution, caution, danger`
becomes uniformly `danger`. That is correct — all four cars overtook at well over the
danger threshold — but it means this ride is **not** evidence that the field
discriminates well between passes in general.

**Not done (tracked separately)**
- `sampleCount` is still write-only: nothing has read it since #207 deleted the majority
  check. Removing it is a clean follow-up that churns three test files for an unrelated
  reason.
- PRD §8.7's "Pass detection logic" block and TCA.md §4.12 still describe the
  majority-positive criterion #207 deleted, and OQ15 is still Open though #207 settled it
  at 10 m. #207's debt, left alone here.
- Making `relativeVelocityMPS` non-negative by construction: after #208 and this change,
  one seed clamp and one strict comparison are all that defend the invariant.

---

# CI test reliability — `CyclometerTests` failing intermittently on GitHub

**Branch:** `fix/ci-test-reliability`

## The premise was wrong

These were not flaky tests to be quarantined. They are correct tests catching real
async races, and they surface only under contention. Two facts settle it:

- The whole suite is **~8 seconds** of execution (712 tests, 69 suites). Every minute
  of the 16-minute CI run is build and simulator boot, not tests.
- **Six consecutive local runs on an idle machine: all green**, on a commit CI failed.
  "It passes locally" was never evidence of anything for these tests.

## Root causes

1. **False sync points in the BLE suites.** A test awaits the client's *state* stream,
   then reads a value the client writes on the line *after* publishing that state.
   `BLECSCClient.swift:807` sets `connectionState = .connected` — waking the test — and
   only at `:813` calls `discoverServices`. Nothing orders the two. Five sites; one
   carried the comment `// sync point: discoverServices has run`, which was false.

2. **`reconnectRescanCountsAsAmbient` waited for the wrong call.** It waited for the
   last transport call to be *a* `startScanning`, which `beginPairingScan`'s own opening
   call already satisfies before the disconnect is handled at all. The wait returned
   instantly, `endPairingScan` released a radio the reconnect still needed, and the
   assertion failed. Fixing (1) made this deterministic — it had been passing by luck.

3. **Simulator-clone launch flake.** The 2026-09-04 and 2026-09-07 failures both carry
   `FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch"`.
   xcodebuild was cloning simulators to parallelize 8 seconds of work.

4. **CI failures were undiagnosable — the worst of the four.** Cloned-destination runs
   switch xcodebuild to the terse legacy reporter: `Test case 'X' failed` and nothing
   else. The 2026-09-07 log had **zero** expectation text or line numbers for its three
   failures, so a real bug and an infra flake looked identical. That is why this kept
   recurring. Same setting as (3): disabling parallel testing fixes both.

5. **Wall-clock drain deadlines.** `TestStore.finish(timeout:)` counts real nanoseconds,
   not `TestClock` time, so it couples to machine load — the same coupling that got
   `.timeLimit` traits reverted twice. `RideRecordingTests` and `RideEndFailureTests`
   were the only two files using it, at 5 seconds, and were exactly the two that failed
   on CI. Correlation, not proof; see "Not verified" below.

## Changes

- [x] `tests.yml` — `-parallel-testing-enabled NO`, `-resultBundlePath`
- [x] `.github/scripts/summarize-xcresult.py` — assertion text + source location into the
      job summary; verified against a real failing bundle and end-to-end on a probe
- [x] `.xcresult` uploaded as an artifact on failure (14-day retention)
- [x] `CyclometerTests/TestSupport.swift` — `expectEventually` (bounded wait for values
      the harness records out of band) and `effectDrainTimeout`
- [x] five BLE race sites rewritten to wait rather than read
- [x] seven `finish(timeout: .seconds(5))` / one `.seconds(1)` → `effectDrainTimeout`
- [x] `scripts/stress-tests.sh` — run the suite N times under CPU load

## Verified

- Serial suite green: 712 tests, ~8s.
- 8/8 runs green under load (serial), 6/6 under load in clone mode.
- `expectEventually`'s timeout path reports at the **call site**, carries its comment,
  and honours its deadline (300 ms budget → 0.310 s).

## 6 — `skipInFlightEffects` cancels; it does not drain

Found only because the diagnostics landed first. The Ride suites did:

    await store.skipInFlightEffects(strict: false)
    await store.finish(timeout: ...)

with the comment "draining in-flight effects is the only way to know it's actually
done". But `skipInFlightEffects` **cancels** in-flight effects rather than awaiting
them. The flush → GPX → finalizeRide pipeline is an unreceived `.run` effect, so on an
idle machine it finishes before the cancel lands and the test passes; on a loaded one
the cancel kills it mid-flight. CI's first readable run said exactly that:

    RideRecordingTests/killAndRelaunchResumesRide()
        RideRecordingTests.swift:182: Expectation failed: (ride.recordingState → .paused) == .ended
        RideRecordingTests.swift:183: Expectation failed: (ride.endedAt → nil) != nil
        RideRecordingTests.swift:188: Expectation failed: (ride).gpxFileURL → nil → nil

Fixed by observing the pipeline's own end state before tearing the store down.
`runRideToEnd` now takes an `until:` predicate, because each failure-injection test
has a different end state (`.ended` for the two whose finalize succeeds; a recorded
intent carrying the GPX for the one whose finalize fails).

Note this supersedes (5) as the explanation for those two suites. Raising the drain
deadline was treating a symptom that was not the cause — a longer timeout cannot help
when the work is being cancelled rather than waited for. The wider deadline is kept
because it is correct on its own terms, not because it fixed this.

## 7 — Hardcoded simulator name

`-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` requires that device to
already exist. Twice it didn't (2026-08-30, and this PR's own first run), the second on
a runner reimaged to Xcode 26.6 listing no concrete simulators at all. Now resolved at
runtime, preferring `iPhone 17 Pro` so local snapshot references stay valid.

## Still not reproduced

`AlertOrchestratorFeatureTests` — seen failing once locally as a whole suite, never
since, and never on CI with diagnostics available. Left alone.

## Left alone

- Snapshot suites stay skipped in CI (locally-recorded references — separate problem).
- Bare `await Task.yield()` sync points remain at `BLECSCClientTests` 659/769/841 and
  `VariaRadarClientTests` 515/536/717. Same family as (1), but none of them has failed;
  changing tests that pass, on a theory, is what causes churn.
- Test count 715 → 712 is not a regression: the three cadence-zero tests belong to the
  unmerged `fix/211` branch, and this branch is off `main`.
