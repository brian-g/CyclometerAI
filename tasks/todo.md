# #433 — Absolute barometric altitude steps ~300 m mid-ride

Branch: `fix/433-altitude-step`
Approach (chosen): rate gate + offset in `AltitudeResolver`. Once absolute altitude is live, a change between
consecutive Core Motion readings faster than `maxVerticalSpeedMPS` (10 m/s) is a re-anchor, not motion: it goes
into a running offset so the ride's altitude stays continuous; when Core Motion steps back, the offset returns.
Readings keep arriving while paused (the altimeter effect runs the whole ride), so a real lift across a pause is
still a plausible rate and passes through.

- [x] 1. Tests first (`AltitudeResolverTests`): −300 m step in 1 s while climbing → no step; step back → offset
      returns; 300 m over 60 s (a lift) passes through; `barometerEnded` clears the offset
- [x] 2. `AltimeterReading.absolute` gains `timestamp` (Core Motion's `CMLogItem.timestamp`, not delivery time,
      so readings bunched in the queue aren't read as instant jumps); fix existing call sites
- [x] 3. `AltitudeResolver`: `maxVerticalSpeedMPS`, offset, last raw reading; reset in `barometerEnded`
- [x] 4. `AltimeterSession`: log `accuracy` and `precision` per reading (debug); resolver logs (notice) each step
      it absorbs, with size and accuracy
- [x] 5. Replay test: the 2026-10-16 13:33 track, miles 11.2–11.9 (pauses filled with held readings at 1 Hz)
      through resolver + `ElevationTracker` → no ~300 m descent, lowest within the true range
- [x] 6. UX.md §W14 altitude bullet; `AltitudeResolver` doc comment
- [x] 7. Build; `ElevationTrackerTests` + `ActiveRideElevationTests`; full `CyclometerTests`

## Review

- **Resolver.** Once absolute altitude is live, a change between consecutive Core Motion readings faster than
  `maxVerticalSpeedMPS` (10 m/s, rated on Core Motion's own `timestamp`) goes into `reanchorOffset`, which is
  subtracted from every later reading. `barometerEnded` clears it. Each absorbed step logs a notice (size, seconds,
  accuracy, running offset); every absolute reading logs `accuracy` and `precision` at debug.
- **Red first.** Before the fix the replay gave 297.1 m of false descent and a 1178 m low, and the 1 s step test
  was 296.7 m out.
- **Replay after.** Ascent 57.5 m, descent 0.0 m, range 1457.9–1520.7 m. Residual offset −5.9 m is the fixture:
  the pause is filled with held readings, but the rider rode ~26 m uphill before auto-resume, which live readings
  would have shown gradually. Real residual ≈ the climb during the two recovery seconds (~0.6 m).
- **Guards.** A lift (300 m in 60 s, 5 m/s) passes through; the existing pause/lift feature test still passes.
- **Known limit.** A re-anchor that ramps slower than 10 m/s passes through (the risk accepted with this approach).
- **Not verifiable in the simulator** (no barometer): confirmed on a real ride only.
- **Full suite.** `CyclometerTests`: 2068 passed, 0 failed (TEST SUCCEEDED).
