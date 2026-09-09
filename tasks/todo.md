# tasks/todo.md — #192 TurnDerivation (cue points with geometric fallback)

Branch: `feat/192-turn-derivation` · Milestone M8 · Plan:
`~/.claude/plans/quirky-waddling-puzzle.md`

## Implementation

- [x] `Models/RouteGeometry.swift` — extract `tangentPlaneOffset(from:to:)` out of `segmentMeters`
      (the same north/east pair is a length and a bearing); add `bearingDegrees(from:to:)`
      returning nil on a zero-length segment, `cumulativeDistances(_:)`,
      `resampled(_:everyMeters:)` and `projection(of:onto:cumulative:)`
- [x] `Models/TurnDerivation.swift` — `enum TurnDerivation` + `struct Maneuver`; six thresholds,
      each with the reasoning for its value; geometric path, cue path, cue-text reading,
      separation filter
- [x] Geometry path: resample → per-sample heading change → runs with reversal hysteresis →
      accumulated turn → magnitude gate + radius gate → place at the half-turn point
- [x] Cue path: perpendicular projection, 50 m snap limit, `type`→`name`→`desc` reading,
      negative word list, geometry fallback for unstated cues, sort by along-route distance
      with an importer-order tie-break

## Tests

- [x] `CyclometerTests/Models/TurnDerivationTests.swift` — 31 tests / 52 cases, one or more per
      acceptance criterion, plus the three properties the first design lacked: density
      independence, drawn-radius independence, and recorded-track scatter tolerance
- [x] Full suite green: **803 tests in 75 suites**, snapshot suites included (locally)

## Review

**The approved plan was wrong and had to be replaced mid-flight.** The first design measured a
*windowed bearing delta* — bearing 20 m before a point against 20 m after — and was validated
against synthetic sharp-vertex fixtures. Those fixtures hid a defect that would have shipped: the
windowed delta measures curvature over the window, not turn angle, so one 90° corner read 85° when
drawn with a 5 m corner radius, 43° at 28 m, and **nothing at all at 30 m or wider**. Whether a real
intersection became a maneuver depended on which planning tool wrote the file. A second defect:
grouping candidates by *array index adjacency* treats index proximity as road proximity, so on a file
decimated to 150–200 m spacing two corners 200 m apart merged into one maneuver.

Replaced with accumulated turn over a uniformly resampled polyline. Summing many small heading
changes gives the true angle whatever the drawn radius, and splits the decision into the two
questions that actually matter — how far the road turns (the sum) and over what distance (the span,
via `maximumTurnRadiusMeters`). Resampling first is what makes index distance *be* road distance, so
the index-adjacency class of bug cannot recur.

**Found while implementing, not planned for.** A bare recorded track is the only thing the geometry
path ever sees (a file with cues never reaches it), and at 1 Hz a bike lays a fix every 5–10 m with a
couple of metres of scatter — 15–30° of heading noise on *every* sample. Ending a turn at the first
sample pointing the other way shattered one corner into seven sub-threshold fragments and reported
none of them. Fixed with reversal hysteresis (`reversalThresholdDegrees`): a counter-turn has to
accumulate past 20° to end a turn, and resets the moment the road resumes its original direction.
This is the same technique, for the same reason, that `RouteGeometry.elevationGainLoss` already uses
against DEM jitter.

**Decisions, and what they cost.** Cue data is exclusive — any cue that *resolves* suppresses the
geometry scan entirely — so a partially-cued file under-navigates rather than inventing turns the
planner deliberately omitted. The test is deliberately "a cue resolved", not "a cue exists": Garmin
Connect and Strava both export routes whose only `<wpt>` is named "Start", and keying off presence
would drop that cue for having no direction and then ship the route with zero maneuvers.
`.slightLeft`/`.slightRight` come only from cue text; a 40° gate has no standing to call anything
slight. Cue text is English-only.

**Left for other issues:** nothing consumes this yet — `NavigationFeature` (#197) owns firing,
distance-to-turn and off-route, #198 the tones, #200 the W9 widget. No spec-doc edits: #202 owns
those, and two staleness items are its, not this issue's — `CLAUDE.md:155` still lists OQ12 as open
where `PRD.md:1272` resolved it, and `DataModel.md:228` still calls `Route` a Phase 2 entity that
#191 shipped.

**Known residual:** `maximumTurnRadiusMeters = 60` is the one constant with no external reference
behind it — it is where a rider stops steering for a corner and starts following the road round, and
that is a judgement, not a measurement. It is covered from both sides by `turnRadiusBoundary` and is
a single edit if real GPX proves it wrong.
