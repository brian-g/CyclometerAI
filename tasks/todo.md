# tasks/todo.md — #194 S19 map-as-filter, filter sheet, shared route-map component

Branch: `feat/194-routes-filters` · Milestone M8 · Plan:
`~/.claude/plans/nested-discovering-toucan.md`

## Geometry & pure values

- [x] `Models/RouteGeometry.swift` — `RouteBounds.intersects(_:)`, `.contains(latitude:longitude:)`,
      `RouteGeometry.segment(from:to:intersects:)` (own function — Liang–Barsky),
      `RouteGeometry.polyline(_:intersects:)` (bbox pre-reject, count==1 branch)
- [x] `Features/Routes/RoutesMapCamera.swift` — `RouteBounds(region:)`, clamp not wrap,
      `longitudeDelta >= 360` → full range, viewport-contains-everything → nil
- [x] `Features/Routes/RouteFilter.swift` — `RouteFilter.matches`, `RouteFilterDomain.from`
      (metres only, 1/2/5×10ᵏ step, `upper >= lower + step`, optional gain domain)
- [x] `Models/RouteDirectionMarkers.swift` — viewport-derived spacing, cull, limit
- [x] `Models/UnitSystem.swift` — `elevationUnit` / `elevationLabel` / `elevation(fromMeters:)`

## UI components

- [x] `UI/Components/RouteMap/RouteMapContent.swift` — polyline + chevrons + start/finish,
      loop collapses to one flag, `coordinate2D` bridge moved here
- [x] `UI/Components/RangeSlider/RangeSlider.swift` — two thumbs / one thumb, per-thumb a11y,
      coincident-thumb rule, RTL, Dynamic Type, ≥44pt target

## Feature

- [x] `Features/Routes/RoutesFeature.swift` — filter state (declaration-site defaults),
      stored `mapFilteredRouteIDs`, bbox fallback for missing geometry, unset normalization
- [x] `Features/Routes/RoutesView.swift` — toolbar filter button + badge, status bar + chip,
      third empty state, `interactionModes: [.pan, .zoom]`, camera survives toggle, sheet
- [x] `PreviewContent/RoutePreviewData.swift` — `RouteDetail.previewRouteDetails` incl. a loop

## Tests

- [x] `Models/RouteGeometryTests.swift` — incl. loop-viewport and empty-corner fixtures,
      and first-segment-outside (the P1 regression)
- [x] `Models/RouteDirectionMarkersTests.swift`
- [x] `Features/RouteFilterTests.swift`
- [x] `Features/RoutesMapCameraTests.swift` — region → bounds edges
- [x] `Features/RoutesFeatureTests.swift` — harness `bounds:`/`elevationGainMeters:` params
- [x] `Models/UnitSystemTests.swift`
- [x] `Features/RoutesSnapshotTests.swift` — re-record the four existing PNGs
- [x] Full local suite green, twice

## Review

**Suite: 961 tests, 0 failures** over three full local runs, snapshot suites included.
Baseline before this work was 892. The app builds, installs and launches clean on an
iOS 26.5 simulator.

**The plan was wrong about the snapshot references needing re-recording.** It predicted the
new toolbar filter button would change `testPopulatedList` and `testEmptyState`; all four PNGs
were untouched. The reason is worth knowing: a `UIHostingController` renders *no* navigation-bar
items in this harness at all — the existing references show a title and a list with no Import
and no Map/List button either. So the toolbar was never covered here, and the filter button and
its badge are pinned by `RoutesFeatureTests` and by the running app instead. Three new
references were added for what does render: the filtered list with its status bar and chip,
"No Matching Routes", and the filter sheet body.

**A test caught the chevron fallback placing two, not one.** A route shorter than one chevron
spacing resampled to a single point, and the short-route fallback then fell through to the
general loop, which emitted a chevron at the midpoint *and* one on the final coordinate —
directly under the finish flag, which is what anchoring on the later sample of each pair exists
to avoid. Fixed in `RouteDirectionMarkers` rather than by relaxing the expectation.

**Four reducer tests asserted filter values the sliders cannot produce.** They sent ranges
outside the derived domain (10 km when the domain floor was 20 km) and expected them stored
verbatim; `normalizing` correctly clamped them. The behaviour was right and the fixtures were
wrong — `RouteFilterTests.normalizingClampsIntoTheDomain` already pinned it. Corrected the
fixtures.

**One-thumb sliders left a sliver of unfilled track.** The gain slider anchored its fill at the
domain minimum's *position*, which sits half a thumb in from the edge, so ~13pt of grey showed
to its left and read as a rendering fault rather than as "no minimum". The fill now anchors on
the track's leading edge in one-thumb mode, mirrored for right-to-left.

**The map itself could not be verified automatically, and no attempt is committed.** A
throwaway harness rendering `RouteMapContent` through `drawHierarchy` produced a blank image —
exactly the MapKit behaviour `tasks/lessons.md` and `RoutesSnapshotTests` already document — and
the simulator cannot be driven to import a GPX and pan a map without UI automation. The
placement arithmetic is fully unit-tested (`RouteDirectionMarkersTests`, 10 tests), but
**chevrons, flags and the loop-collapse rule on a real map still want a human eye**; the
`Routes — Map` preview now feeds real geometry so that check takes one Xcode preview.

**Two decisions the critique changed before any code was written.** Failing a route whose
polyline has not loaded would have silently removed rows from the *list* on three real paths —
import-from-list, the `deleteFailed` re-read, and a permanently unreadable polyline — since
`loadMissingPolylines` only runs while the map is open. It falls back to the stored bounding box
instead, which is also the honest answer, because such a route still draws a pin on the map.
And the slider domain is a function of the routes alone, never of `UnitSystem`: deriving round
*mile* endpoints would have moved the domain when S12's units picker changed and flipped the
badge 0 → 1 with no rider action.

**Unrelated flakiness, confirmed not ours.** `LocationOneShotTests.timeoutResolvesNil` and
`oneShotDoesNotDisturbAnActiveStream` failed on one run while Simulator.app was open. They fail
identically on a clean baseline with these changes stashed, and pass in every run with the
simulator UI closed. Left alone.

**Deliberate deviations, both noted in the plan and both approved.** The Routes map drops pitch
and rotation (`interactionModes: [.pan, .zoom]`) — a pitched camera's `region` reaches the
horizon and would match nearly every route while showing a narrow wedge, and screen-space
`Annotation` content does not counter-rotate, so chevrons would point wrong. And the polyline
stroke went from 4pt to 5pt on S19, matching UX.md §S20 now that both screens share one
component. `cyMapRoute` (purple) was deliberately *not* adopted: it belongs to the active-ride
map, where #199 needs it distinct from `cyMapTravelPath`.
