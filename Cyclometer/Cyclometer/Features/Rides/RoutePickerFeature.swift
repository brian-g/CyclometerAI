import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "routes")

/// S05.2 — the Route picker: which saved route, if any, the ride about to start follows (#196).
///
/// Pushed on the Start sheet's own stack from its Route row. A choice goes back as a delegate and
/// `StartSheetFeature` pops, so the answer and the navigation land in one reducer pass.
///
/// A list and nothing more. Importing, filtering and the map are S19's — the Start sheet offers no
/// `fileImporter`. Nothing hangs off `onDisappear` (`tasks/lessons.md`): the one read runs from
/// `.task`, and `.forEach` cancels a popped element's effects, as `.ifLet` does the whole stack's
/// when the sheet goes.
@Reducer
struct RoutePickerFeature {

    @ObservableState
    struct State: Equatable {
        /// Row distances follow the S12 units picker, the same read-through `RoutesFeature` does.
        @Shared(.appPreferences) var preferences

        /// The sheet's current answer, nil for a free ride — the row that carries the checkmark.
        var selection: RouteReference?

        var routes: [RouteSummary] = []

        /// Set only by a read that succeeded. With `loadFailed` it keeps three screens apart — not
        /// read yet, nothing saved, and the read failed — so a failure never tells the rider their
        /// routes are gone (`tasks/lessons.md`, #193).
        var hasLoaded = false
        var loadFailed = false

        init(selection: RouteReference? = nil) {
            self.selection = selection
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }
    }

    enum Action: Equatable {
        case task
        case routesResponse(Result<[RouteSummary], PersistenceFailure>)
        /// Nil is the None row.
        case routeTapped(RouteSummary?)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// The rider's choice, nil for None, on its way to `StartSheetFeature`, which owns it.
            case routeSelected(RouteReference?)
        }
    }

    @Dependency(\.persistenceClient) var persistenceClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .task:
                // Summaries only: a row needs a name, a terrain line and a distance, never the
                // polyline (`Route.swift:138-140`).
                return .run { [persistenceClient] send in
                    do {
                        await send(.routesResponse(.success(try await persistenceClient.fetchRoutes())))
                    } catch {
                        logger.error("fetchRoutes failed: \(error.localizedDescription, privacy: .public)")
                        await send(.routesResponse(.failure(PersistenceFailure())))
                    }
                }

            case .routesResponse(.success(let routes)):
                state.routes = routes
                state.hasLoaded = true
                return .none

            case .routesResponse(.failure):
                state.loadFailed = true
                return .none

            case .routeTapped(let route):
                // Checked here as well as handed back, so the mark moves to the tapped row while the
                // pop animates rather than sitting on the old answer.
                state.selection = route?.reference
                return .send(.delegate(.routeSelected(route?.reference)))

            case .delegate:
                return .none
            }
        }
    }
}
