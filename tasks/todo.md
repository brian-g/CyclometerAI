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

---

# #258 — Direction-of-travel arrows on the live ride map

Plan: /Users/brian/.claude/plans/velvety-snuggling-whistle.md
Branch: `fix/route-direction-arrows-live-map`

- [x] 1. RouteDirectionMarkers: spacing-as-input overload
- [x] 2. RouteDirectionMarkers: `spacingMeters(forCameraDistanceMeters:)`
- [x] 3. RouteDirectionMarkers: `screenAngleDegrees(bearing:heading:pitch:)`
- [x] 4. Extract `RouteDirectionChevrons` MapContent; RouteMapContent delegates to it
- [x] 5. ActiveRideMapView: chevron state, continuous camera capture, draw in cyMapRoute
- [x] 6. Tests: 10 new, full suite green (1302 passed, 0 failed)
- [x] 7. Simulator run against a simulated ride — chevrons on both legs, pointing the right way

## Review

### What was wrong

The chevron machinery from #194/#195 was only ever wired to the route-browsing maps. S19 and S20
draw direction of travel; the live ride map — `ActiveRideMapView`, which is both the W8 dashboard
widget and its full-screen sheet — drew the loaded route as a bare `MapPolyline`. That is the map
the rider actually reads mid-ride, and it is where a route doubling back over the same road is
ambiguous.

### What it took

Reusing the placement arithmetic was most of it. The live map differs from S19/S20 in two ways
that made the reuse more than a call:

1. **It turns.** `Annotation` content is screen-space and does not counter-rotate, which is why
   S19 disables rotation outright rather than solving it. Heading-up follow is the live map's whole
   point, so the angle is now computed: `RouteDirectionMarkers.screenAngleDegrees`.
2. **It tilts.** A pitched camera's `region` is the box around the frustum and runs to the horizon,
   so it is useless as a spacing input — `spacingMeters(forCameraDistanceMeters:)` uses
   `MapCamera.distance`, which the tilt does not touch. The region still culls.

The tilt also foreshortens the screen's vertical axis, so the drawn angle is
`atan2(sin d, cos d · cos pitch)` rather than `d` — a few degrees at the ~35° MapKit allows at the
follow distance, but free to get right once the heading correction had to exist anyway.

Placement resamples the whole route, so it runs when the camera settles (and when the rider leaves
the viewport the current chevrons were placed for — a following widget can go a long way without
the camera ever settling). Only the rotation follows the camera continuously.

### Verification

Full suite green, 1302 passed. S19/S20 snapshots are unchanged, which is the evidence that the
extraction of `RouteDirectionChevrons` and the spacing refactor changed nothing for them: both
defaults are zero, which is a north-up flat map.

Driven on the simulator through a temporary harness view (since importing a route and starting a
ride through the UI is a much longer road than the thing being checked): a two-leg route, east then
north, with `simctl location start` riding it at 8 m/s. Chevrons sit on the line, the east leg's
point east and the north leg's point north, on both the widget and the sheet surface, and they
re-place as the camera follows.

**Not verified on the simulator:** the heading correction itself. The simulator supplies no compass
heading, so `followsHeading` never rotates the map there (known — same limitation that shaped #199).
The correction is covered by unit tests instead, and wants a look on a real ride.

### Judgment call

`minimumSpacingMeters` stays at 300 m. At the widget's follow zoom that is one or two chevrons on
screen — enough to read the direction, and deliberately not enough to read as the line itself,
which is what the constant was lowered to 4-across-viewport for in the first place. Easily revisited
if it reads too sparse on a real ride.

### Review round two (#258 review — "the arrow is horrible")

Two defects and a glyph, all on S20 as well as the live map:

1. **Arrows pointed up to 90° off the line.** The bearing was taken between arrow *positions* —
   hundreds of metres apart at a browsing zoom — so on a curving road it described a chord across
   the bend rather than the stretch of line the arrow sat on. Bearings now come from
   `RouteGeometry.tangentBearingDegrees`: the line's direction ±15 m of the arrow itself.
2. **Arrows moved when zooming.** Spacing was a continuous function of the viewport, so every
   pinch re-placed every arrow. `quantized(_:)` snaps it to a doubling ladder above
   `baseSpacingMeters`, so a coarse spacing is a multiple of a fine one: zooming in only adds
   arrows *between* the ones already there.
3. **Chevron → filled triangle**, at 26 pt (14 first, then raised — see below). An open V on a line its own colour reads
   as a kink in the line, which is what it looked like.

`minimumSpacingMeters` (300 m) is gone; `baseSpacingMeters` is 100 m, and the ladder means the
old floor's job — stopping a tight zoom from asking for an arrow every few metres — is done by the
base rung instead.

Placement no longer resamples the whole route into an array; it walks the distances it wants, and
`RouteGeometry.coordinate(_:atMeters:cumulative:)` binary-searches the segment, since a long route
at a fine spacing asks a few hundred times per camera settle.

Tint stays matched to the line (`cyPrimary` on S19/S20, `cyMapRoute` on the live map) — asked and
confirmed against a white-triangle variant.

Verified with a temporary harness rendering S20's own `RouteMapContent` over a real 1,157-point
route, at the review screenshot's zoom and at whole-route zoom: triangles sit on the line and point
along it at both. Full suite green, 1305 passed.

### Arrow size (#258 review, second pass)

14 pt was too small to see. Rendered 14, 20 and 26 pt over the same real route at a street-level
zoom: the arrow is drawn in the line's own colour, so its size is the only thing separating it from
the line, and below ~20 pt it reads as a thickening rather than as an arrowhead.

But no single size works, because the map's own features shrink as the camera pulls back — what
sits well against a street is a speck against a county (semantic zoom, Brian). The size is now a
ramp: `arrowPoints(forSpacingMeters:)`, 20 pt at the base rung and one point per rung of the
spacing ladder, capped at 28.

Taking the *rung* rather than the raw viewport is the point: the size changes at exactly the zooms
the density changes at, so a pinch never smoothly grows the arrows. `Font.cyMapAnnotation(points:)`
became a function; the numbers and the reasoning live in `RouteDirectionMarkers`.

Read at four zooms over a real route: 400 m spacing · 22 pt, 1600 · 24, 6400 · 26, 12800 · 27.

### Nesting under the cap (#258 review, third pass)

"At higher zoom levels there should be more arrows, but arrows should only be added and subtracted
on the line, never moved" (Brian). The ladder gave that — except through the `limit`, which thinned
an over-long list to 24 evenly spaced *entries*. Every survivor was still on the lattice, but a
different subset of it survived at each zoom, so arrows appeared to wander as the rider pinched.

Too many in view now climbs a rung — double the spacing and place again — until the count fits.
That keeps the nesting exactly: every arrow at a coarse zoom is also an arrow at every finer one.
`thinned(_:to:)` is gone.

`placements(...)` became `arrows(...)`, returning `Arrows { placements, spacingMeters }`: the
spacing it settled at is what sizes the glyph, so density and size are two readings of one number
and cannot disagree.

Pinned by `zoomingInOnlyAddsArrows`, which walks five halvings of one viewport and asserts every
arrow still on screen is in the same place, and by `limitKeepsTheNesting` for the cap path.
Read on the simulator over four zooms of a real route: arrows hold position, counts change around
them. Full suite green, 1309 passed.
