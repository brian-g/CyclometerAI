# #177 — Capture + persist a static map thumbnail at ride end

Plan: /Users/brian/.claude/plans/nifty-petting-boole.md
Branch: `feat/177-ride-map-thumbnail`

- [x] 1. `Ride.mapThumbnailLight` / `mapThumbnailDark` (externalStorage PNG)
- [x] 2. Move `GPXExporter.segments(of:)` to `TrackPointDTO.segments(of:)`
- [x] 3. `RideMapThumbnail` pure enum: drawable segments, region, path, `capture(rideId:)`
- [x] 4. `MapSnapshotClient` (live: MKMapSnapshotter muted + POIs off, cyMapTravelPath resolved per variant)
- [x] 5. `PersistenceClient.saveRideMapThumbnail` + actor + mock
- [x] 6. Ride end: capture after finalize (no Task shield — mutation test showed ifLet's cancel never reaches this effect)
- [x] 7. AppFeature recovery paths capture after finalize
- [x] 8. Docs: DataModel §3.1, UX §S10/§S14, RideListSummary comment
- [x] 8b. Issue #177 edited; route thumbnails filed as #273 (M9)
- [x] 9. Tests (thumbnail, persistence, migration, ride end, AppFeature teardown + recovery); mutation checks both ways
- [x] 10. Full local suite green (1193 Swift Testing + 91 XCTest, 0 failures; the 2 known issues are
      NavigationPipelineTests' existing `withKnownIssue`). Real MKMapSnapshotter render on the simulator
      via a throwaway test, both PNGs inspected (168×168, trace per appearance, no chord across the pause)

## Review

- Trace colour changed from the plan's `cyPrimary` to `cyMapTravelPath` (Brian's call): colors.md defines
  it as the recorded-track token and the live ride map already uses it. UX §S14 updated; S10's own trace
  colour is left to #249.
- Dropped the plan's unstructured-`Task` shield. Reading `_IfLetReducer` said the ride-end effect is
  cancelled when AppFeature nils `activeRide`; a mutation test proved the cancel never reaches it. The
  AppFeature test now guards that behaviour instead (it fails if cancellation ever reaches the render).
- Labels: POIs are hidden, but city names and road shields still render (Madison + US-12 in the sample).
  Rendering larger at lower scale made it worse: full label, plus MapKit's "Maps" attribution mark,
  which it omits at 56 pt. 56 pt @3x kept.
- For #248: the thumbnail lands after `finalizeRide`, so `rideFinished`'s poll can load the row before
  its image exists. The row will need a refresh once the capture is saved.
- Not done: a full UI drive of a real recorded ride (the render and the pipeline were each verified
  separately).
- `/code-review xhigh` (14 findings). Fixed: capture was one-shot → `RideMapThumbnail.backfill()` is the
  single mechanism (after Finish, at launch, after each close-out; stops at first failure; reloads
  Rides when anything landed); teardown test waits on the save instead of draining (it was silently
  sitting out the timeout on `rideFinished`'s TestClock poll); `#require` the ride id; finalize-failure
  test counts renders at the end instead of reading 0 too early; redundant renderer scale; segments doc.
  Declined: inline external storage (#248's list design owns what it fetches), next-ride cancelling a
  previous ride-end effect (seconds-long window; guarded by the teardown test), double track fetch
  (one-off, decoupled), antimeridian (RouteBounds' documented limit), temp-dir leak (not real: the mock's
  `fetchRide` throws before the exporter writes). Full suite: 1196 + 91, 0 failures.

---

# #252 — Cycling-focused route analysis + 80-char summary

Plan: /Users/brian/.claude/plans/polished-knitting-elephant.md
Branch: `feat/252-route-analysis`

- [x] 1. `RouteTerrain`: 10 m resample, 50 m smoothing, 100 m grade window, climbs Cat 4–HC, FIETS per climb, character
- [x] 2. `RouteSurface` + `OverpassClient`: OSM surface/tracktype classes, nearest-way matching, chunked `around` query
- [x] 3. `Route.terrainData` / `surfaceData` (optional JSON), `RouteSummary.terrain` / `.surface`, persistence `saveRouteSurface` + `backfillRouteTerrain`
- [x] 4. `RoutesFeature`: surface lookup after every read and import (retry = next visit), terrain backfill on `.task`
- [x] 5. `RouteSummaryLine` (≤ 80 chars, priority drop order), S19 row subtitle, S20 Summary section, monospaced digits
- [x] 6. Specs: PRD §8.6/§14 + changelog 0.6.1, UX S19/S20, DataModel §3.10
- [x] 7. Tests: terrain, surface, Overpass, summary line, reducer, persistence, schema migration; 6 snapshot refs re-recorded + 1 new
- [x] 8. Full local suite green (1404 passed, 0 failed); live Overpass response shape checked
- [x] 8b. `/code-review high` findings fixed (10): Overpass `remark` throws; lookup detached from the view's
      `.task` (TCA chains effect-sent actions' tasks onto the originating send); once per route per launch,
      no restarts, stale reads keep known surfaces; first failure ends the batch; sidewalks/steps/unbuilt
      ways ignored; punchy excludes any categorized climb; kicks found on the unsmoothed profile with a 3 m
      tolerance and grade-based end trim; max grade floored at 0; backfill marks unanalysable routes; point-
      to-segment distance reuses `RouteGeometry.projection`. Full suite: 1412 passed, 0 failed
- [ ] 9. Simulator end-to-end import with a real GPX (not done)
- [ ] 10. #252 descoping comment (FIT, NP) — drafted, awaiting approval to post

## Review

- Out of scope, per PRD: FIT import (§15), estimated power/NP (Phase 3, no weight/FTP/CdA exist).
- Deviations from the plan: `OverpassClient` is a plain struct with a throwing `testValue`, matching the
  repo's other clients rather than `@DependencyClient`; climb dip tolerance is 10 m, not the 3 m noise
  floor, so false flats don't split climbs; climb ends are trimmed to within 1 m of the low/high.
- `NavigationPipelineTests.noRouteRideNeverTouchesNavigation` counted every route read; it now
  baselines after the import's own surface-lookup read.
- Finding: in OSM much of the US road network has no `surface` tag (30 of 47 ways on a Cupertino
  sample), so many routes will show no surface word — the rule is "never assume paved".

---

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

### Density (#258 review, fourth pass)

Two arrows on a 7 km loop. The spacing was the viewport's width over four, which is only right
where the route crosses the screen once — a loop that meanders puts far more line on screen than
the screen is wide, so a 5 km-wide view of a 7 km loop asked for arrows 3.2 km apart.

The density is now a count of what is actually drawn: start at the finest rung and climb until no
more than `targetArrowsInView` (12) arrows are on screen. `arrowsAcrossViewport`,
`spacingMeters(for:)`, `spacingMeters(forCameraDistanceMeters:)` and `quantized(_:)` are all gone —
the climb expresses the ladder by itself, and nothing has to guess how much line a viewport holds.

The live map needed a viewport it could count against, since a pitched camera's region runs to the
horizon and would count most of the route as in view. `LiveMapCamera.visibleBounds(for:)` builds a
box one camera distance square about where the camera looks, which the tilt does not touch.

Read over a real route at three zooms: 1600 m · 10 arrows · 24 pt, 400 m · 7 · 22, 100 m · 5 · 20.
Full suite green, 1308 passed.

**What the failing tests taught me.** `zoomingInOnlyAddsArrows` asserted "zooming in never draws
fewer", which is wrong under any correct rule: a tighter viewport holds less line. The requirement
is only that arrows still on screen have not moved, plus that the spacing never coarsens on the way
in. Both are now asserted.

### Review round (/code-review high)

Seven findings, all taken. Three were behaviour, and all three sat in zooms or motions my tests
never entered.

1. **Stacking on a distant route.** Density counted arrows on the visible line with no floor on
   their separation *on screen*. S19 opens ~160 km wide, where a 5 km route is a dot — counting
   alone put a dozen arrows on that dot. `spacingFloor(for:)` says two arrows are never closer
   than a twelfth of the screen, snapped up to a rung so the nesting survives. The climb starts
   there.
2. **The live map ran out of arrows ahead of the rider.** The box arrows were culled to and the
   box that triggered re-placement were the same box, so the supply ahead hit zero exactly as the
   re-placement fired. Arrows are now *drawn* over a 3× box (`LiveMapCamera.arrowBounds`) and
   *counted* against the screen-sized one, and `needsArrowRefresh` fires once the rider is half a
   screen in.
3. **A camera write per frame.** The continuous handler stored the whole camera, which rebuilt the
   track polyline — thousands of points on a long ride — at the camera's update rate, on a free
   ride too. It now stores only heading and pitch, rounded to the degree, and only while a route
   is loaded.
4. **Per-route arrow sizes on S19.** Each route ran its own climb and the glyph was sized from the
   rung it settled at, so two routes on one screen drew different arrows. `Arrows.pointSize` comes
   from the viewport's floor instead: same screen, same arrow, whatever each route's density.
5. **The live map's box is north-aligned and square** while the map is heading-up and tilted. The
   3× drawing margin covers it; both approximations are now written down where the box is built.
6. A size-stability test compared the same value three times. Distinct spacings on one rung now.
7. A doc comment for `cyTurnGlyph` had been clipped by an earlier hunk. Restored.

Full suite green, 1314 passed. Read at three zooms including S19's opening one, where the route is
a blob: 25600 m · 2 arrows, 6400 m · 10 arrows, and no stack.

### #261 — done (branch `fix/delete-ride-cascade`)

`PersistenceClient.deleteRide` removes the GPX file, batch-deletes the CoreData `TrackPoint`
rows, then deletes the `VehiclePassEvent` rows and the `Ride` in one save.

The ordering inverts the plan's, deliberately. The plan removed the file last; the `Ride` row
goes last instead, because it is the only thing that knows the file's path and the only thing a
screen can reach the other three from. Interrupted anywhere earlier, the rider still sees a ride
they can delete again, rather than the unreachable leftovers this issue is about. File removal
stays non-fatal, which was the plan's own reason for its ordering.

`RidesView` no longer touches `modelContext`; the swipe sends `.deleteRecordedRide(id)` through
`RidesFeature`. `RidePersistenceActor` gains `gpxFileURL(id:)` and `deleteRide(id:)`, the latter
fetching and deleting the pass events itself — there is no `@Relationship` to cascade, which is
why they were being left behind.

Tests: 6 in `RideDeletionTests` against real in-memory CoreData + SwiftData stacks, 3 in
`RidesFeatureTests`.

**Not verified end to end.** The list is an `@Query`, and the delete now happens on the
persistence actor's context rather than the view's. A unit test pins the half that is testable —
the container's main context no longer finds the ride — but whether SwiftUI re-runs the query is
SwiftData's own contract and needs a running app. An attempt to drive it on the simulator failed
on its own terms: seeding the real store from a host test does not survive the UI run, because
launching XCUIApplication reinstalls the app and wipes its container. Worth a manual check on
device before this merges.

### #263 — done (branch `fix/pause-track-segments`)

The track is now segmented end to end. `TrackPointDTO` carries a `segmentIndex`, the CoreData
`TrackPoint` entity carries a matching `Integer 16`, `ActiveRideFeature` opens a new segment on
both resumes (the manual `.resumeTapped` and the auto-resume in `.speed`), `GPXExporter` emits one
`<trkseg>` per run of equal index, and the live map draws one `MapPolyline` per segment. The index
is persisted on `Ride`/`RideSummaryUpdate` and restored by `State(resuming:)`, so a kill mid-ride
doesn't restart the numbering and merge two stretches back into one.

`ActiveRideFeature.State.trackCoordinates: [Coordinate]` became `trackSegments: [[Coordinate]]`,
and the view chain (`RideDashboardView` → `MapWidget`/`DirectionsWidget` → `liveMapSheet` →
`ActiveRideMapView`) takes segments rather than a flat list.

**Deviation from the plan: a second CoreData model version.** The plan said an added attribute
with a default is an inferrable lightweight migration and `CoreDataStack.load` needs no change.
The second half is true; the first is only true across model *versions*. Adding an attribute
changes the entity's version hash, and editing the single `.xcdatamodel` in place would have left
no old model in the bundle to migrate from — `CoreDataStack.load` calls `fatalError`, so that is a
launch crash for every rider with existing ride history. `CyclometerTimeSeries 2.xcdatamodel` now
holds the new attribute, v1 is back to exactly what shipped, and `.xccurrentversion` names v2.
(#211 got away with an in-place edit because default values are not part of the version hash.)
`TimeSeriesMigrationTests` writes a store with the shipped model and reopens it with the current
one, which is the migration a device performs on update.

`GPXParsing` gained `trackSegmentPointCounts` — the flat `trackPoints` list deliberately drops
segment boundaries, and the boundary is the whole assertion here. Nothing else reads it.

Tests: 5 in `GPXExporterTests`' new "Track segments" section, 6 in `TrackSegmentTests`, 1
migration test. Three existing resume tests gained the new state mutation.

### #263 — review round (/code-review high)

One finding, taken. A ride killed while `.active` came back `.active` with its segment index
restored but nothing opening a new one, so the points recorded after the relaunch carried the same
index as the points before it and the export drew a chord across the whole kill gap — #263's own
defect, triggered by a kill instead of a pause. `State(resuming:)` now bumps the index on the
`.active` path only; a ride restored `.paused` records nothing until the resume that opens its own
segment. My doc comment had claimed the restore already covered this, which it did not. Covered by
`aKillWhileActiveOpensANewSegment`.

Cleared without change: the migration (v2 differs from v1 by exactly the new attribute), the
auto-resume writing no checkpoint (points and summary always flush from the same 30 s branch), the
consecutive-run grouping, `ForEach(id: \.offset)` stability, and `RidesView`'s flat polyline (still
`PreviewContent` sample data, #251's).

**Not verified end to end.** No ride was recorded on a device or simulator for this. What the
tests prove is the data path — reducer to DTO to CoreData to XML — and the migration. What they
do not prove is the drawn result: that the live map shows a visible break rather than two
polylines that happen to abut.
