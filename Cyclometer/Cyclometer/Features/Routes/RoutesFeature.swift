import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "routes")

/// S19 — the Routes tab: saved routes as a list or a map, plus GPX import from the Files app.
///
/// Everything the screen shows comes from `PersistenceClient`; nothing reads the demo data
/// the prototype was built on. Map-as-filter and the filter sheet are #194, and tapping a
/// row does nothing until S20 lands (#195).
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

        /// Nil until a fix arrives, and permanently nil when location is denied — which is
        /// an ordinary state for this screen, not a failure. `RoutesMapCamera` falls back.
        var riderCoordinate: Coordinate?

        @Presents var alert: AlertState<Action.Alert>?

        var unitSystem: UnitSystem { preferences.preferredUnit }
    }

    enum Action: Equatable {
        case task
        case reloadRoutes
        case routesResponse(Result<[RouteSummary], PersistenceFailure>)
        case polylinesResponse([UUID: [RouteCoordinate]])
        case riderCoordinateResponse(Coordinate?)

        case mapToggled
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
                return state.showsMap ? loadMissingPolylines(state) : .none

            case .polylinesResponse(let polylines):
                state.polylines.merge(polylines) { _, loaded in loaded }
                // Anything no longer in the list — deleted while the fetch was in flight —
                // has no business keeping its geometry alive.
                let live = Set(state.routes.map(\.id))
                state.polylines = state.polylines.filter { live.contains($0.key) }
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
                // Deferred to the first time the map is actually opened, so a rider who
                // only ever uses the list never pays to decode a polyline.
                guard state.showsMap else { return .none }
                return loadMissingPolylines(state)

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
