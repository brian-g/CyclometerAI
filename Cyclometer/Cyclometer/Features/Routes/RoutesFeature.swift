import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "routes")

/// S19 — the Routes tab: saved routes as a list or a map, plus GPX import from the Files app.
///
/// Everything the screen shows comes from `PersistenceClient`; nothing reads the demo data
/// the prototype was built on. Tapping a row does nothing until S20 lands (#195).
///
/// Three filters narrow the list and compose: a distance range and an elevation-gain maximum
/// from the sheet (`RouteFilter`), and the map's own viewport, captured when the rider switches
/// back to the list. `routes` always holds everything the store returned — the filters are
/// applied on the way out, never by editing it.
@Reducer
struct RoutesFeature {

    @ObservableState
    struct State: Equatable {
        /// Row distances follow the S12 units picker, the same read-through
        /// `ActiveRideFeature.State.unitSystem` does.
        @Shared(.appPreferences) var preferences

        var routes: [RouteSummary] = []

        /// False until the first read comes back. Distinguishes "nothing saved" from "not
        /// read yet" and from "the read failed" — without it the empty state claims the
        /// rider has no routes during the first frames of every launch, and again behind
        /// the read-failure alert, when the store may be full.
        var hasLoaded = false

        /// Loaded only when the map is shown, and cached after that. `RouteSummary` carries
        /// no geometry on purpose — the list reads far more often than the map does — so the
        /// polylines UX.md §S19 asks for are a second, deliberate read.
        var polylines: [UUID: [RouteCoordinate]] = [:]

        var showsMap = false
        var isImporterPresented = false
        var isImporting = false
        var isFilterSheetPresented = false

        /// The sheet's two filters. `RouteFilter` keeps the rule itself testable without a
        /// `TestStore`; this is only where the rider's current answer lives.
        var filter = RouteFilter()

        /// The viewport the map last settled on, updated as the rider pans. Not itself a
        /// filter — it becomes one only when they switch back to the list.
        var visibleMapBounds: RouteBounds?

        /// The viewport that *is* filtering the list, captured from `visibleMapBounds` on the
        /// way back to the list. Nil when the rider has not narrowed by map.
        var mapFilterBounds: RouteBounds?

        /// The viewport the rider dismissed from the chip, remembered so that returning to the
        /// map and back does not silently re-apply it. Without it the map re-opens on the same
        /// region, reports it, and the next switch to the list captures exactly the filter that
        /// was just cleared — the chip would look like it had done nothing.
        var dismissedMapBounds: RouteBounds?

        /// Which routes survive `mapFilterBounds`, or nil when there is no map filter.
        ///
        /// **Stored rather than computed on read.** The test walks every coordinate of every
        /// route, and a computed property would re-run it on every body pass — twice in the
        /// list branch alone, once for the empty-state check and once for the `List` itself —
        /// and would make the list body observe `polylines`, invalidating it every time a
        /// batch of geometry lands. Stored, the sweep runs once per thing that can change it.
        var mapFilteredRouteIDs: Set<UUID>?

        /// Nil until a fix arrives, and permanently nil when location is denied — which is
        /// an ordinary state for this screen, not a failure. `RoutesMapCamera` falls back.
        var riderCoordinate: Coordinate?

        @Presents var alert: AlertState<Action.Alert>?

        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// The travel of the sheet's sliders, derived from what is actually saved. Nil for an
        /// empty library, which is also when the filter button is hidden.
        var filterDomain: RouteFilterDomain? { RouteFilterDomain.from(routes) }

        /// What the *map* draws: the sheet filters only. Leaving the map's own viewport out is
        /// what stops it ratcheting itself ever narrower — a route panned off-screen has to
        /// still be there to pan back to.
        var sheetFilteredRoutes: [RouteSummary] { routes.filter(filter.matches) }

        /// What the *list* shows: the sheet filters and the map viewport, composed.
        var filteredRoutes: [RouteSummary] {
            guard let mapFilteredRouteIDs else { return sheetFilteredRoutes }
            return sheetFilteredRoutes.filter { mapFilteredRouteIDs.contains($0.id) }
        }

        /// The toolbar badge. Sheet filters only — the map narrowing has its own chip, because
        /// a number in the toolbar cannot explain an exclusion the rider made by panning.
        var activeFilterCount: Int { filter.activeCount }

        var isFiltered: Bool { !filter.isEmpty || mapFilterBounds != nil }
    }

    enum Action: Equatable {
        case task
        case reloadRoutes
        case routesResponse(Result<[RouteSummary], PersistenceFailure>)
        case polylinesResponse([UUID: [RouteCoordinate]])
        case riderCoordinateResponse(Coordinate?)

        case mapToggled
        case mapRegionChanged(RouteBounds?)
        case mapFilterCleared

        case filterButtonTapped
        case filterSheetPresentationChanged(Bool)
        case distanceFilterChanged(ClosedRange<Double>?)
        case elevationGainFilterChanged(Double?)
        case filtersCleared

        case importButtonTapped
        case importerPresentationChanged(Bool)
        case fileSelected(URL)
        case filePickerFailed
        case importResponse(Result<RouteSummary, RouteImportFailure>)

        case deleteButtonTapped(UUID)
        case deleteFailed

        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {}
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.permissionsClient) var permissionsClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .task:
                return .merge(
                    .send(.reloadRoutes),
                    // Status, never `request`. Browsing saved routes must not raise a
                    // location prompt — S01 owns that conversation — and skipping the
                    // fix entirely when it is denied is what makes "the map still opens
                    // with location denied" true by construction.
                    .run { send in
                        guard await permissionsClient.status(.locationWhenInUse).isGranted else { return }
                        await send(.riderCoordinateResponse(await locationClient.currentCoordinate()))
                    }
                )

            // Separate from `.task` so a recovery re-read cannot also re-run the permission
            // check and a second location request.
            case .reloadRoutes:
                return .run { send in
                    do {
                        await send(.routesResponse(.success(try await persistenceClient.fetchRoutes())))
                    } catch {
                        logger.error("fetchRoutes failed: \(error.localizedDescription, privacy: .public)")
                        await send(.routesResponse(.failure(PersistenceFailure())))
                    }
                }

            case .routesResponse(.success(let routes)):
                state.hasLoaded = true
                state.routes = routes
                Self.refreshFilters(&state)
                return state.showsMap ? loadMissingPolylines(state) : .none

            case .polylinesResponse(let polylines):
                state.polylines.merge(polylines) { _, loaded in loaded }
                // Anything no longer in the list — deleted while the fetch was in flight —
                // has no business keeping its geometry alive.
                let live = Set(state.routes.map(\.id))
                state.polylines = state.polylines.filter { live.contains($0.key) }
                // Geometry that has just landed upgrades those routes from the bounding-box
                // approximation to the exact test, so the map filter is re-evaluated here.
                Self.refreshMapFilter(&state)
                return .none

            case .routesResponse(.failure):
                state.alert = Self.alert("Couldn't Load Routes",
                                         "Your saved routes couldn't be read. Try again in a moment.")
                return .none

            case .riderCoordinateResponse(let coordinate):
                state.riderCoordinate = coordinate
                return .none

            case .mapToggled:
                state.showsMap.toggle()
                guard state.showsMap else {
                    // UX.md §S19: "When switching back to the list will show only those routes
                    // displayed on the map." This is that moment — the viewport the rider left
                    // the map on becomes the filter, unless it is the very one they dismissed
                    // from the chip and have not moved since.
                    guard state.visibleMapBounds != state.dismissedMapBounds else { return .none }
                    state.dismissedMapBounds = nil
                    state.mapFilterBounds = state.visibleMapBounds
                    Self.refreshMapFilter(&state)
                    return .none
                }
                // Deferred to the first time the map is actually opened, so a rider who
                // only ever uses the list never pays to decode a polyline.
                return loadMissingPolylines(state)

            case .mapRegionChanged(let bounds):
                // Recorded, not applied. Panning the map must not reorder the list underneath
                // it; only the switch back to the list captures.
                state.visibleMapBounds = bounds
                return .none

            case .mapFilterCleared:
                state.dismissedMapBounds = state.mapFilterBounds
                state.mapFilterBounds = nil
                state.mapFilteredRouteIDs = nil
                return .none

            case .filterButtonTapped:
                state.isFilterSheetPresented = true
                return .none

            case .filterSheetPresentationChanged(let isPresented):
                state.isFilterSheetPresented = isPresented
                return .none

            case .distanceFilterChanged(let range):
                state.filter.distanceMeters = range
                Self.normalizeFilter(&state)
                return .none

            case .elevationGainFilterChanged(let maximum):
                state.filter.maxElevationGainMeters = maximum
                Self.normalizeFilter(&state)
                return .none

            case .filtersCleared:
                // The sheet's filters only. The map narrowing has its own chip and its own
                // clear, which is what keeps the badge count honest about what it covers.
                state.filter = RouteFilter()
                return .none

            case .importButtonTapped:
                state.isImporterPresented = true
                return .none

            case .importerPresentationChanged(let isPresented):
                state.isImporterPresented = isPresented
                return .none

            case .filePickerFailed:
                state.isImporterPresented = false
                state.alert = Self.alert("Couldn't Open File",
                                         "That file couldn't be opened. Try picking it again.")
                return .none

            case .fileSelected(let url):
                state.isImporterPresented = false
                // A 16 MB file is seconds of parsing. Without this a rider who taps Import
                // again mid-parse gets the same route saved twice.
                guard !state.isImporting else { return .none }
                state.isImporting = true
                return .run { send in
                    // The picker vends a security-scoped URL and this is the only place
                    // that owns its lifetime (GPXRouteImporter.swift:23-25). Held across
                    // the save as well as the parse: `Data(contentsOf:options:.mappedIfSafe)`
                    // memory-maps the file, so releasing early is releasing under the read.
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

                    do {
                        var imported = try GPXRouteImporter.route(contentsOf: url)
                        // The filename is a better name than "Imported Route", and
                        // `ImportedRoute.name` is a `var` for exactly this (Route.swift:24-26).
                        if imported.name?.isEmpty ?? true {
                            imported.name = url.deletingPathExtension().lastPathComponent
                        }
                        let summary = try await persistenceClient.importRoute(imported)
                        await send(.importResponse(.success(summary)))
                    } catch {
                        logger.error("route import failed: \(error.localizedDescription, privacy: .public)")
                        await send(.importResponse(.failure(RouteImportFailure(error))))
                    }
                }

            case .importResponse(.success(let summary)):
                state.isImporting = false
                // `fetchRoutes` sorts newest first and this route was just imported, so one
                // insert preserves that order without a second round trip to the store.
                state.routes.insert(summary, at: 0)
                Self.refreshFilters(&state)
                // Nothing else loads this one's geometry: the two other loaders run on the
                // map toggle and on a re-read, and importing from the map does neither.
                return state.showsMap ? loadMissingPolylines(state) : .none

            case .importResponse(.failure(let failure)):
                state.isImporting = false
                state.alert = Self.alert("Couldn't Import Route", failure.message)
                return .none

            case .deleteButtonTapped(let id):
                // Optimistic: a swiped row that lingers while SwiftData saves reads as a
                // gesture that didn't take. `.deleteFailed` puts the list back.
                state.routes.removeAll { $0.id == id }
                state.polylines[id] = nil
                Self.refreshFilters(&state)
                return .run { send in
                    do {
                        try await persistenceClient.deleteRoute(id)
                    } catch {
                        logger.error("deleteRoute failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        await send(.deleteFailed)
                    }
                }

            case .deleteFailed:
                state.alert = Self.alert("Couldn't Delete Route",
                                         "The route is still saved. Try again in a moment.")
                // Re-read rather than re-insert the row we dropped: the store, not this
                // reducer, is the authority on what survived the failed write.
                return .send(.reloadRoutes)

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// Fetches only the polylines state does not already hold, gathered into one action
    /// rather than one per route so the map redraws once when they all land.
    ///
    /// Keyed on ids, never on counts: `loadPolylines` omits any route whose fetch failed, so
    /// a count comparison would re-fetch all N on every toggle forever — and a delete plus an
    /// import balance the counts while leaving the cache holding the wrong routes entirely.
    ///
    /// A route that fails to load is simply absent from the map. The row is still in the
    /// list, and one unreadable polyline must not take the whole map down with it.
    private func loadMissingPolylines(_ state: State) -> Effect<Action> {
        let missing = state.routes.filter { state.polylines[$0.id] == nil }
        guard !missing.isEmpty else { return .none }
        return .run { [persistenceClient] send in
            var polylines: [UUID: [RouteCoordinate]] = [:]
            for route in missing {
                do {
                    if let detail = try await persistenceClient.fetchRoute(route.id) {
                        polylines[route.id] = detail.coordinates
                    }
                } catch {
                    logger.error("fetchRoute failed for \(route.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            await send(.polylinesResponse(polylines))
        }
    }

    // MARK: - Filters

    /// The route set changed: bring any active filter back into the domain it now implies, and
    /// re-decide what the map viewport holds.
    private static func refreshFilters(_ state: inout State) {
        normalizeFilter(&state)
        refreshMapFilter(&state)
    }

    /// Clamp the filter into the current domain and drop anything that now covers all of it.
    ///
    /// Run on every change to `routes`, not only when a thumb moves. Import a 200 km route while
    /// the upper thumb sits at what *was* the longest route — which the rider read as "no upper
    /// limit" — and without this the new route is filtered out the instant it arrives, badge
    /// reading 1, with nothing on screen to explain it.
    private static func normalizeFilter(_ state: inout State) {
        guard let domain = RouteFilterDomain.from(state.routes) else {
            // Nothing saved. The filter button is hidden in this state, so a filter left set
            // would be unreachable.
            state.filter = RouteFilter()
            return
        }
        state.filter = domain.normalizing(state.filter)
    }

    /// Which routes the captured viewport holds.
    ///
    /// The stored bounding box rejects in O(1), and only the survivors pay for the exact
    /// segment-by-segment test — which is what makes "any part of the line is on screen" cheap
    /// enough to be the rule rather than "the start marker is on screen".
    ///
    /// **A route whose polyline has not loaded is kept on its bounding box, not dropped.**
    /// Dropping it looks defensible — it is not drawn on the map either — but `polylines` is
    /// populated only when the map is open (`loadMissingPolylines` runs on the map toggle, on a
    /// re-read and on an import *while the map shows*), so a route imported from the list, or
    /// restored by `deleteFailed`, or whose geometry failed to load at all, would silently
    /// vanish from the list with no way back. The map still draws such a route as a pin at its
    /// bounds centre, so the box is also the honest answer to "displayed on the map"; and
    /// erring toward showing a route the rider owns is the safe direction to be wrong in.
    private static func refreshMapFilter(_ state: inout State) {
        guard let bounds = state.mapFilterBounds else {
            state.mapFilteredRouteIDs = nil
            return
        }
        let polylines = state.polylines
        state.mapFilteredRouteIDs = Set(
            state.routes.lazy
                .filter { route in
                    guard route.bounds.intersects(bounds) else { return false }
                    guard let polyline = polylines[route.id] else { return true }
                    return RouteGeometry.polyline(polyline, intersects: bounds)
                }
                .map(\.id)
        )
    }

    private static func alert(_ title: String, _ message: String) -> AlertState<Action.Alert> {
        AlertState {
            TextState(title)
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState(message)
        }
    }
}

// MARK: - Failures

/// A read that didn't come back. Carries nothing — the rider-facing message is the same
/// whatever SwiftData's reason was — but it is a distinct `Equatable` type so `Action`
/// stays comparable in a `TestStore`, which `any Error` would not be.
struct PersistenceFailure: Error, Equatable {}

/// Why an import didn't produce a route, in the rider's terms.
///
/// A separate type from `GPXImportError` because the failure set is wider than parsing:
/// the save can fail too. `Equatable` for the same `TestStore` reason as above.
struct RouteImportFailure: Error, Equatable {
    enum Reason: Equatable {
        case parse(GPXImportError)
        case save
    }

    var reason: Reason

    init(_ error: any Error) {
        reason = (error as? GPXImportError).map(Reason.parse) ?? .save
    }

    var message: String {
        switch reason {
        case .parse(.malformed):
            "That file isn't valid GPX."
        case .parse(.noCoordinates):
            "That file has no route in it."
        case .parse(.fileTooLarge):
            "That file is too large to import."
        case .parse(.tooManyPoints):
            "That route has too many points to import."
        case .parse(.unreadableFile):
            "That file couldn't be read."
        case .save:
            "The route was read but couldn't be saved."
        }
    }
}
