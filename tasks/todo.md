# Navigation fixes from the 2026-09-19 "Home and Around" ride

Plan: /Users/brian/.claude/plans/ticklish-marinating-cocke.md
Branch: `fix/navigation-ride-1-feedback`

- [x] 1. TurnDerivation: `turningNoiseFloorDegrees` 3° -> the radius-equivalent rate (11.46°)
- [x] 2. TurnDerivation: `uTurnThresholdDegrees` 135° -> 165°
- [x] 3. TurnDerivation: trailing gentle samples trimmed from a run's angle and span
- [x] 4. TurnDerivation: `maximumTurnRadiusMeters` 60 m -> 50 m (beyond the plan — see Review)
- [x] 5. NavigationFeature: `lapStartMeters` -> `lapCoveredMeters` (loop never completed)
- [x] 6. NavigationFeature: `minimumAnnounceDistanceMeters` — no announcing a turn 2.5 m out
- [x] 7. NavigationFeature: rejoin at 50 m over 2 consecutive fixes
- [x] 8. NavigationFeature: overlay held until 10 ft from the turn, 2 min GPS fallback
- [x] 9. Tests updated + 6 new; full suite green (1292 passed, 0 failed)
- [x] 10. Harness re-run against the real route: 10 maneuvers, no U-turn

## Review

### What was wrong

Diagnosed from `Cyclometer_2026-09-19_13-05.gpx`, `Home_and_Around.gpx` and
`system_logs.logarchive`. The route carries no cue points (188 trackpoints, zero `<wpt>`), so
every maneuver came from polyline geometry.

**Two U-turns that are not on the road.** `turningNoiseFloorDegrees` was 3°, a third of the
turning rate `maximumTurnRadiusMeters` implies, so a sweeping bend could open a turn run 90 m
before a corner and add its angle to the corner's — the 6560 m turn is a plain 80° right and was
derived at 138°. Trailing gentle samples were also counted into a run, inflating both its angle
and its span. With `uTurnThresholdDegrees` at 135°, the 480 m left (a 90° left, then the road
curves 70° more) came out as "Make a U-turn" too. Log confirms both: `turn tone — uTurn` at
13:07:30 and 13:25:36.

**The loop could never complete.** `lapStartMeters` was reset on every rejoin, so `hasFinished`'s
"half the loop" test measured from the rejoin. After the 4.6 km detour the rider reached the
finish having "ridden" 1.2 km of a 6.9 km loop — there is no `route complete` in the log.

**A turn announced 2.5 m out.** Rejoining clears the announce marker and then announces whatever
is ahead at any distance (13:23:43).

**Rejoin gate.** 30 m against off-route's 50 m — 20 m of riding during which the app said the
rider was off a route they were on.

**Overlay** was a flat 4 s timer, gone with 90 m still to ride at a 100 m lead.

### Not a bug

The two off-route stretches were real: up to 224 m from the route line, 2.0 m accuracy on every
fix, smooth track. The route is drawn over ground that was not ridden. No turn was skipped —
there are no maneuvers between 4600 m and 5380 m.

### Deviations from the plan

1. **`maximumTurnRadiusMeters` 60 -> 50.** Fixing the noise floor exposed an 11th maneuver at
   6720 m: a 72° bend at ~56 m radius, no junction, previously hidden because it was being
   swallowed by the corner before it. 50 m removes it and keeps all 10 real turns. Judgment made
   on one route's evidence; easily revisited.
2. **`lapStartMeters` replaced rather than patched.** The planned fix (don't reset on rejoin)
   broke `rejoiningALoopAtItsStartDoesNotFinishIt`: a rider who bails 200 m into a loop and comes
   back to the start matches at the loop's *end*, and with the lap start left at 0 that reads as a
   finished loop. Root cause is that the test measured span along the route rather than ground
   ridden. `lapCoveredMeters` accumulates only the step between consecutive on-route fixes, so a
   rejoin credits nothing and both cases come out right.

---

## #253 / #254 / #255 — onboarding and Routes copy (2026-09-19)

- [x] #253 — Routes empty state: "Import a route from the Files app to ride it." → "Import a route to ride, or connect a service." (`RoutesView.emptyLibrary`)
- [x] #255 — S02 Add Sensors button: "Next" → "Finish" (last onboarding step), plus the stale "Next button" doc comments in `SensorPairingView`
- [x] #254 — S01 welcome copy truncated instead of wrapping
- [x] Re-record moved snapshot references (SensorPairing ×2, Routes empty ×2), full suite green

### Review

**#254 root cause.** `WelcomeView`'s copy sat in a plain `VStack` that handed it whatever
vertical space was left after the permission rows, guidance text and Next button. `Text`
answers a too-short height proposal by truncating to a single line, so at an accessibility
text size — or on a shorter phone — each paragraph collapsed to "Real-time radar, metrics,
and intelligence —…" and the second paragraph vanished entirely. Reproduced with a throwaway
snapshot at 375×667 and at `.accessibilityLarge`, both of which showed the truncation.

**Fix.** The header/copy/permission-rows column moved into a `ScrollView` with
`.fixedSize(horizontal: false, vertical: true)`, so the copy is always proposed its ideal
height and overflow scrolls instead of being squeezed. The guidance text and Next button stay
pinned below, unchanged. At default type on a full-size phone nothing scrolls — the three
existing Welcome references passed unmodified, which is the proof the layout is untouched
where it was already correct. `testLargeTypeWrapsCopy` pins the regression.

**Follow-up.** S20's route picker carried its own variant of the #253 string. Aligned to
"Import a route in the Routes tab, or connect a service." — that screen has no import button
of its own, so it keeps the "where" and picks up the "or connect a service"; one reference
re-recorded (`StartSheetSnapshotTests.testPickerEmptyLibrary`).
