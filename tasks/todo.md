# #433 — Absolute barometric altitude steps ~300 m mid-ride

Branch: `fix/433-altitude-step`
Approach (revised after review): **check against the relative barometer.** The first approach (a 10 m/s
rate gate) assumed 1 Hz readings through pauses. The CMAltimeter header says absolute updates arrive "whenever a
change in elevation is detected", and `CMLogItem.timestamp` is Mach time, which stops in sleep. A return step after a
gap passed the gate, so the ride stayed 97 m high for good. PR #434 is reworked on the same branch.

Now: on a phone with absolute altitude, the client also runs relative updates and attaches the barometer's latest
relative altitude to each absolute reading. The resolver compares Core Motion's change with the barometer's since
the last absolute reading. A disagreement of more than `reanchorToleranceMeters` (30 m, about 3.6 hPa, more than
weather moves a barometer in a ride stop) is a re-anchor and goes into the offset. Only the disagreement is taken
out, so real climb across a gap is kept. Timing and sleep don't matter, and slow re-anchors are caught.

- [x] 1. `AltimeterReading.absolute(meters:accuracy:barometerMeters:)`, defaulting to nil; drop `timestamp`
- [x] 2. `AltimeterSession`: relative updates alongside absolute on the same serial queue; latest attached
- [x] 3. `AltitudeResolver`: tolerance check replaces the rate gate; no barometer → pass through as on main
- [x] 4. Tests: step carried; step back after a gap cancels; lift passes; small drift passes; no barometer
      passes; ended drops offset (1473.9 m, from review)
- [x] 5. Replay without pause filling; barometer = the ride's own per-point changes minus Core Motion's jumps
- [ ] 6. UX.md §W14, doc comments; elevation suites; full suite; push to #434 and update its description

## Review

- **Client.** With absolute altitude available, relative updates run too, on the same serial queue, and the latest
  is attached to each absolute reading as `barometerMeters`. If the relative stream errors, it logs and the check
  switches off; absolute carries on as on main.
- **Resolver.** `reanchor = Δabsolute − Δbarometer` since the last absolute reading. Past 30 m it goes into
  `reanchorOffset`. Only the disagreement comes out, so real climb across a gap is kept. With no barometer value
  either side, it passes through unchanged (main's behaviour).
- **Tests** (`AltitudeResolverTests`, 6 new): step carried across (exact); step back after a 111 s gap cancels
  (the review's case); lift passes; a 5 m disagreement passes; no barometer passes; ended drops offset (1473.9 m,
  which fails if either reset is removed).
- **Replay** (no invented readings): Core Motion sends only the recorded points. The barometer is synthesized
  from the track's own changes minus Core Motion's four jumps, and the test says so. Ends within 10 m of Core
  Motion's final reading; the old rate gate would end 97 m high.
- **Mutation.** With the tolerance set to infinity (main's behaviour), `reanchorIsCarriedAcross` and
  `replayKeepsTheClimb` fail.
- **Open (not changed):** a ride killed mid-fault resumes on the wrong value and then absorbs the step back; a real
  >30 m correction after trust is rejected. Two concurrent CMAltimeter streams are device-only.
- **Full suite.** `CyclometerTests`: 2069 passed, 0 failed (TEST SUCCEEDED).
