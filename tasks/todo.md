# tasks/todo.md — #193 S19 Routes tab (real list, map and Files import)

Branch: `feat/193-routes-tab` · Milestone M8 · Plan:
`~/.claude/plans/goofy-enchanting-quokka.md`

## Implementation

- [x] `Clients/Location/LocationClient.swift` — add `currentCoordinate: @Sendable () async -> Coordinate?`
- [x] `Clients/Location/LocationManagerState.swift` — one-shot fix: cached `manager.location`
      first, else `requestLocation()` + timeout, resumed by draining a continuation dict under
      the lock. Never call `stopUpdates()` (it kills a recording ride's stream)
- [x] `Models/RouteGeometry.swift` — `RouteBounds.union(_:)`
- [x] `Features/Routes/RoutesMapCamera.swift` — rider fix → route bounds → fallbackCenter,
      50-mile radius (100-mile span)
- [x] `Features/Routes/RoutesFeature.swift` — real state, `RouteImportFailure`, persistence /
      location / permissions dependencies, import + delete effects
- [x] `Features/Routes/RoutesView.swift` — read the store, `fileImporter`, empty state,
      swipe-to-delete, third `topBarTrailing` import item; leave `RouteDetailView` for #195

## Tests

- [x] `CyclometerTests/Features/RoutesFeatureTests.swift`
- [x] `CyclometerTests/Features/RoutesMapCameraTests.swift`
- [x] `CyclometerTests/Features/RoutesSnapshotTests.swift` (list + empty only; no map — see
      the MapKit snapshot lesson) + CI skip-list entry
- [x] `CyclometerTests/Clients/LocationClientTests.swift` — `testValue.currentCoordinate`
- [x] Full local suite green

## Review

**Suite: 892 tests, 0 failures** over two consecutive full runs (26 of them Routes), snapshot suites included locally.

**The issue's "no Info.plist change needed" was wrong, and the failure would have been
silent.** Measured on iOS 26: `UTType("com.topografix.gpx")` is **nil** — iOS does not know
GPX at all — and `UTType(filenameExtension: "gpx")` answers a *dynamic* type
(`dyn.ah62d4rv4ge80s6d2`) that conforms to nothing, not even `public.xml`. A `fileImporter`
filtering on it compiles, runs, opens the picker, and greys out every `.gpx`. The planned
`?? .xml` fallback could never have fired either, because the call returns non-nil. Fixed by
declaring the type in `UTImportedTypeDeclarations`; `RoutesGPXTypeTests` pins it, since
deleting the declaration breaks the picker with no error anywhere. Verified in the running
app: in the picker both `.gpx` files are selectable and both `.json` files are greyed out.

**`isLoading` was a field that existed only to make the screen wrong.** It was in the plan to
stop the empty state flashing before the first read. Two blank snapshot references exposed
what it actually did: a snapshot captures after `.task` sends but before its effect lands, so
`isLoading` was true and the empty branch never rendered — and the same is true of the first
frame the rider sees. For a local SwiftData read there is nothing to spin about, so the field
is gone and the empty state keys off `routes.isEmpty` alone.

**Two spec deviations, both deliberate.** UX.md §S19 asks for polylines on the map, but
`RouteSummary` deliberately carries no geometry — so the map lazily fetches `RouteDetail` per
route the first time it is opened and caches the result, and a rider who only uses the list
never pays to decode a polyline. And the prototype's `spanMeters = 96_560` is a 60-mile
*span*; the spec says a 50-mile *radius*, which is a 100-mile span, so the constant was
replaced rather than kept.

**One AC read literally rather than in spirit.** "No code path reads `RouteStub.sampleRoutes`"
holds for the list and the map. The retained S20 prototype `RouteDetailView` still has one
`#Preview` that feeds it a stub, because that view is what UX.md §S20 points at as its layout
spec until #195 replaces it.

**What the tests do not cover.** Driving the out-of-process Files picker from XCUITest did not
work, so the three-line `fileImporter` callback is the one hop verified by eye rather than by
assertion. Everything on either side of it is covered: `RoutesFeatureTests` runs the reducer
against real `.gpx` files on disk, and `RoutesImportIntegrationTests` runs a picked URL through
the real importer into a real SQLite store, reopens a second container over the same file, and
asserts the route — polyline, cue and all — is still there, which is what surviving a relaunch
actually means.


## Post-review round (`/code-review`, xhigh)

Fourteen of fifteen findings accepted; all fixed.

**Two real bugs in the one-shot location fix, both in the part I claimed to have designed
around.** `requestLocation()` and `startUpdatingLocation()` are mutually exclusive on one
`CLLocationManager` — CoreLocation cancels one when the other starts — so opening the Routes
tab mid-ride could have cancelled the recording ride's stream, and a ride ending could have
stranded the browse waiter for its full timeout. It now returns whatever the live stream has
already delivered instead of requesting, whenever a stream is active. Separately,
`didFailWithError` drained every waiter on *any* error, including `kCLErrorLocationUnknown`,
which is routine indoors and transient — CoreLocation keeps trying after it. Only a denial is
treated as an answer now; everything else waits for the timeout.

**`isLoading` should have been fixed, not deleted** — see `tasks/lessons.md`. Restored as
`hasLoaded`, set only on a successful read, so a failed read no longer renders "No Routes"
behind its own error alert.

**Rest of the accepted findings.** The map now accepts a fix that arrives after it opened (the
tab remembers `showsMap`, so `initialPosition` alone ignored it); a route imported while the
map is showing loads its polyline; the polyline cache is keyed on ids rather than counts (a
failed fetch made counts differ forever, and a delete-plus-import made them match while
holding the wrong routes); `isImporting` now guards a second concurrent import and drives a
`ProgressView` instead of being write-only; `deleteFailed` re-reads via `.reloadRoutes` rather
than re-running the whole appear effect and its location request; row distance uses
`.formatted` rather than `String(format:)`, which was not locale-aware; the region span is
clamped to what `MKCoordinateSpan` accepts; the dead `?? .xml` fallback became `.item`; and
bounding-box centre arithmetic moved to `RouteBounds.center`.

**Declined, with reasoning.** The reviewer wanted `loadMissingPolylines` parallelised and the
polylines decimated for display. `RoutePersistenceActor` is a serial `@ModelActor`, so a task
group buys nothing, and decimation is #194's problem — it needs real geometry for viewport
intersection anyway. Noted rather than built.

**New tests: 11.** Four regression tests on the reducer, two on region clamping (globe-spanning
routes, antimeridian), three on `LocationManagerState`'s one-shot — including that it leaves an
active update stream running, which is the whole reason it exists — plus the import-guard pair.
