# tasks/todo.md — #191 Route @Model (SwiftData route persistence)

Branch: `feat/191-route-model` · Milestone M8 · Plan:
`~/.claude/plans/cached-marinating-parasol.md`

## Implementation

- [x] `Models/Route.swift` — `@Model final class Route` + `RouteSummary` / `RouteDetail` /
      `RouteReference` Sendable DTOs; two `@Attribute(.externalStorage)` blobs (polyline, cues)
      behind computed Codable accessors
- [x] `Models/RouteGeometry.swift` — pure statics: `distanceMeters`, `elevationGainLoss`
      (hysteresis, `elevationNoiseThresholdMeters = 3.0`), `boundingBox`
- [x] `Models/RouteRideSummary.swift` — DTO for S20's Previous Rides
- [x] `Clients/Persistence/RoutePersistenceActor.swift` — `@ModelActor`; import / fetchRoutes /
      fetchRoute / deleteRoute
- [x] `SwiftDataStack.swift` — `Route.self` into the schema
- [x] `Ride.swift` — add `routeId: UUID?`, keep `routeName` as the denormalized copy
- [x] `RidePersistenceActor.swift` — `createRide` takes `RouteReference?`; add `fetchRides(routeId:)`
- [x] `PersistenceClient.swift` + `+Mock.swift` — five new closures, `createRide` signature,
      `testValue` stubs, mock spies
- [x] `ActiveRideFeature.swift:368` — pass `nil` (#196 owns supplying a real route)

## Tests

- [x] `CyclometerTests/Models/RouteGeometryTests.swift` — 9 tests (distance, nil-vs-zero
      elevation, hysteresis boundaries, bounding box)
- [x] `CyclometerTests/Clients/RoutePersistenceTests.swift` — 12 tests, one per acceptance
      criterion, incl. the on-disk cold-open proving `routeId` survives relaunch
- [x] `RideSchemaMigrationTests.swift` — assert a pre-`Route` store takes a `Route` after migration
- [x] `PersistenceClientTests.swift` — `createRide` arity, `testValue`/`mock` coverage
- [x] `ActiveRideFeatureTests.swift` — `createRide` arity

## Verification

- [x] `xcodebuild test -only-testing:CyclometerTests` green from `Cyclometer/`
- [x] Confirm the `$0.routeId == routeId` `#Predicate` does not fault at runtime (the #171 trap)

## Review

**Result:** 878 tests pass, 0 failures. 30 new tests across `RouteGeometryTests` (13),
`RoutePersistenceTests` (16) and `RideSchemaMigrationTests` (1). The new suites also ran green
three consecutive times under saturated CPU, per the `lessons.md` rule that a green idle run is
not evidence.

**Three refinements on the issue as written, all deliberate:**

1. **Two external-storage blobs, not three.** The issue asked for polyline, cues *and* elevation
   samples. `RouteCoordinate.elevationMeters` already carries elevation per point, and
   `ElevationProfileView(samples:)` plots array index against value on a hidden axis — so
   `coordinates.compactMap(\.elevationMeters)` is exactly what S20 wants. A third blob would be a
   duplicate that can drift from the polyline it came from.
2. **`createRide` takes a `RouteReference`, not a bare route id.** The issue said `createRide`
   "gains the route id", but nothing in production has ever written `Ride.routeName` — so with the
   id alone, the "deleting a route leaves `routeName` intact" criterion would have been vacuous in
   production and only assertable by hand-poking a row. Passing the (id, name) pair as one value
   writes both together, makes a mismatched pair unrepresentable, and keeps `RidePersistenceActor`
   off the `Route` table (see below).
3. **`fetchRoute(id:)` returns `nil` rather than throwing**, unlike `fetchRide`'s `.rideNotFound`.
   A ride id is always live; a `Ride.routeId` is *designed* to dangle once its route is deleted, so
   absence is an expected outcome rather than an error.

**Two additions beyond the issue's field list:** a stored bounding box (4 `Double` columns), so
#194's map-as-filter can test viewport intersection without decoding every polyline — and deriving
it later would mean backfilling from blobs, since there is no migration machinery in the target; and
a hysteresis floor on elevation gain (`elevationNoiseThresholdMeters = 3.0`), because a raw
positive-delta sum over DEM-sampled `<ele>` reports far more climbing than the tool the rider
planned in, which would read as a bug on S20 and make #194's gain filter useless.

**Actor topology.** Two `@ModelActor`s now share one `ModelContainer`, so two long-lived
`ModelContext`s exist. That is safe only because each owns exactly one table and neither reads the
other's: `RoutePersistenceActor` touches only `Route`; `RidePersistenceActor` only `Ride` and
`VehiclePassEvent`. That is why `fetchRides(routeId:)` lives on the *ride* actor despite being a
route-shaped query, and why `createRide` is handed the route's name instead of looking it up. The
rule is enforced by discipline and comments, not by the type system — noted in
`RoutePersistenceActor`'s doc comment.

**Risk that did not materialise.** `fetchRides(routeId:)` compares a `UUID?` property against a
captured value in a `#Predicate` — the same shape that compiled and then faulted at fetch time for
`recordingState` (#171). `fetchRidesForARouteReturnsOnlyEndedRidesNewestFirst` is the canary and it
passes, so the `AppView`-style Swift-side filter fallback was not needed.

**Left for other issues:** no spec-doc edits (#202 owns `DataModel.md` / `PRD.md` / `TCA.md` /
`CLAUDE.md`); `ActiveRideFeature` passes `nil` for the route because #196 owns carrying a selection
through `StartSheetFeature`; `RoutesView`/`RouteDetailView` still read `RouteStub` until #193/#195;
no import de-duplication, no retained `.gpx`, no persisted maneuvers (#192), no thumbnails (#51).

**Known residual:** if a polyline blob ever failed to decode, `coordinates` would silently read as
`[]` rather than surfacing an error — the `Ride.syncRecords` precedent this follows. A stored route
can never legitimately have an empty polyline, so that is arguably corruption worth throwing on; it
is not a case #191 creates and #197 will need to guard the navigation path regardless.


---

## Code review follow-up (`/code-review`, xhigh)

15 findings. Nine adopted, six rejected with reasons.

### Adopted

- **Non-finite coordinates (the serious one).** `Double("nan")` parses, `Double("1e999")`
  overflows to `.infinity`, and nothing checked. One such point made NaN of all four stored
  bounding-box columns (`Swift.min(.nan, x)` is `.nan`) *and* made `JSONEncoder` throw, which
  `try?` turned into a nil polyline stored beside a `coordinateCount` still claiming every
  point — a route that looks fine in the list and opens empty. Fixed at the parse boundary
  with an `isFinite` + range guard in `GPXRouteImporter`, so every downstream consumer is
  covered at once. A non-finite `<ele>` drops the elevation, not the point.
- **`CLLocation.distance(from:)` replaced with deterministic ellipsoidal arithmetic.** Not a
  review finding — the new "mock and live must agree" test caught it: the same polyline
  measured 5709.9076 m and 5709.8369 m in one process. Reproducibility is not optional for a
  number that is stored, displayed and filtered on. The replacement matches `CLLocation` to
  0.04 m over 100 km and hits the WGS84 meridian-degree reference exactly.
- `coordinates` / `cuePoints` are get-only; nothing mutates a stored route, and the setters
  baked in the same silent-nil failure.
- Derivation moved to `RouteSummary.init(imported:id:importedAt:)`, so the mock no longer
  allocates an uninserted `@Model` to reuse `Route.init`'s arithmetic.
- `PersistenceClient.fetchRides` → `fetchRouteRides` (and `mock(ridesByRoute:)`): the old name
  gave no signal the id had to be a *route* id, and S15's own ride-history read wants it.
- `mock(importResult:)`, so a #193 TestStore test can get a known id back — the live path mints
  one below the dependency boundary where `$0.uuid` cannot reach.
- `savingChanges` hoisted to one shared free function; the two copies were byte-identical.
- Test store helpers hoisted into `TestSupport.swift`, and the temp-store cleanup now removes
  the `_SUPPORT` directory — the version this was copied from had leaked 68 orphaned
  directories into the simulator container.
- `rideRouteLinkSurvivesAColdReopen` no longer holds two `ModelContainer`s open on one store
  file, which is unsupported and the exact flake shape 31edca0 was landed to remove.
- The no-de-duplication decision is now recorded next to `importRoute`, not only in the PR.

### Rejected

- **Fusing the three geometry passes into one.** Import is one-shot and user-initiated;
  three O(n) passes over even the 100k-point ceiling is milliseconds. Three separately
  testable pure functions are worth more than the cycles.
- **`propertiesToFetch` on `fetchRoutes`.** The finding's premise is wrong: SwiftData's
  identity map means re-fetching the same rows reuses the same registered objects, so the
  registry is bounded by row count, not by refresh count. The doc comment's claim that no
  polyline is decoded is accurate — the accessor is never called.
- **Lazy `RoutePersistenceActor`.** A `ModelContext` on an already-open container is cheap,
  and `RidePersistenceActor` is constructed the same way; deferring one and not the other
  buys nothing and breaks the symmetry.
- **`@Attribute(.unique)` on `Route.id`.** `Ride.id` does not have it either.
- **Import de-duplication.** Still out of scope; recorded as a decision instead.
- **Collapsing the two elevation optionals into one value.** They are written together from a
  single optional tuple at the one write site, and flat columns are what `#Predicate` can
  filter on for #194.
