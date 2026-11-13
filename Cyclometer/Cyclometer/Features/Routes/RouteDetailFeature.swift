import ComposableArchitecture
import Foundation
import os

private let logger = Logger.cyclometer(.routes)

/// S20 — Route Detail: one saved route's map, elevation, the weather at its start, and the rides
/// ridden on it.
///
/// Seeded with the `RouteSummary` S19's row already holds, so the name, distance and climb are on
/// screen from the first frame. The polyline and the previous rides are a second read, because
/// `RouteSummary` deliberately carries no geometry (`Route.swift:138-140`).
///
/// An element of `RoutesFeature`'s navigation stack (#195). Nothing here hangs off
/// `onDisappear` — a popped element's state is gone before SwiftUI runs it (`tasks/lessons.md`) —
/// and nothing needs tearing down: every read runs from `.task`, and `.forEach` cancels a popped
/// element's effects.
@Reducer
struct RouteDetailFeature {

    /// Points in the elevation chart. `RouteGeometry.elevationProfile` spaces them evenly by
    /// distance; this many draws a smooth line at any phone width without handing Swift Charts
    /// the tens of thousands of points a route exported from a recorded ride can carry.
    static let elevationProfileSampleCount = 200

    @ObservableState
    struct State: Equatable {
        /// Units follow the S12 picker — the same read-through `RoutesFeature` does.
        @Shared(.appPreferences) var preferences

        var summary: RouteSummary

        /// Empty until `fetchRoute` lands, and empty for good if the polyline could not be
        /// decoded (`Route.coordinates` coalesces to `[]`) — the map then shows the route's
        /// framed region with nothing drawn on it.
        var coordinates: [RouteCoordinate] = []

        /// Nil until the route loads, and nil for a route with no `<ele>`.
        ///
        /// Deliberately separate from `summary.elevationGainMeters`, which gates the *section*:
        /// a polyline that failed to decode leaves stored gain and loss still worth showing, with
        /// no chart beside them.
        var elevationProfileMeters: [Double]?

        /// Newest first. Empty hides the section — UX.md §S20 answers "hidden" for a route that
        /// has never been ridden.
        var previousRides: [RouteRideSummary] = []

        /// The weather at the route's start (#204), fetched live each time S20 appears: this is a
        /// planning screen, so a value cached at import would defeat it (UX.md §S20).
        var weather: RouteWeather = .loading

        init(summary: RouteSummary) {
            self.summary = summary
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// The strip's hours at `now`: the hour under way, then each that starts before a ride of
        /// this route would end, estimated from the rides already ridden on it as S05.1 does.
        /// Read against the clock, not the fetch, so the strip moves on while S20 stays up.
        func forecastHours(at now: Date) -> [WeatherReading] {
            guard case let .loaded(forecast) = weather else { return [] }
            let estimate = RideDurationEstimate.fromRouteRides(
                routeDistanceMeters: summary.distanceMeters, rides: previousRides
            )
            return forecast.rideHours(estimate: estimate, from: now)
        }
    }

    enum Action: Equatable {
        case task
        case routeLoaded(coordinates: [RouteCoordinate], elevationProfile: [Double]?)
        case previousRidesLoaded([RouteRideSummary])
        case weatherLoaded(AttributedForecast)
        case weatherUnavailable(RouteWeather.Unavailable)
        case useRouteButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// UX.md §S20: "sets active route in Start Sheet and navigates to S05.1". Both halves
            /// belong to `AppFeature`, which owns the sheet.
            case useRoute(RouteReference)
        }
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.weatherClient) var weatherClient
    @Dependency(\.networkStatus) var networkStatus
    @Dependency(\.date) var date

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .task:
                let id = state.summary.id
                // Two independent reads against two different actors, so merged rather than
                // queued. A failure in either leaves the screen on what it already shows: the
                // summary it was seeded with, and a Previous Rides section that stays hidden —
                // which is also what a never-ridden route looks like.
                //
                // The weather follows the route's read, because its start is in the geometry. It
                // stays in the same effect, so leaving S20 cancels it and coming back fetches it
                // again: the "live at view time" UX.md §S20 asks for.
                return .merge(
                    .run { [persistenceClient, weatherClient, networkStatus] send in
                        let coordinates: [RouteCoordinate]
                        do {
                            guard let detail = try await persistenceClient.fetchRoute(id) else {
                                // Only a route deleted out from under this screen resolves to nil,
                                // and S20 offers no way to do that.
                                logger.error("fetchRoute found no route \(id, privacy: .public)")
                                await send(.weatherUnavailable(.failed))
                                return
                            }
                            // Derived here, once per load, rather than by the view on every body pass.
                            let profile = RouteGeometry.elevationProfile(
                                detail.coordinates, sampleCount: Self.elevationProfileSampleCount
                            )
                            await send(.routeLoaded(coordinates: detail.coordinates, elevationProfile: profile))
                            coordinates = detail.coordinates
                        } catch {
                            logger.error("fetchRoute failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            await send(.weatherUnavailable(.failed))
                            return
                        }
                        // A polyline that could not be decoded has no start to ask about.
                        guard let start = coordinates.first else {
                            await send(.weatherUnavailable(.failed))
                            return
                        }
                        do {
                            // `date` is read only once the forecast lands, never in the capture
                            // list, so a test of a failed read needn't provide it.
                            await send(.weatherLoaded(try await weatherClient.attributedForecast(start, now: { date.now })))
                        } catch {
                            // Logged in WeatherClient. WeatherKit's error can't say whether the
                            // device is offline, so the network path is asked, and only now.
                            await send(.weatherUnavailable(await networkStatus.isOffline() ? .offline : .failed))
                        }
                    },
                    .run { [persistenceClient] send in
                        do {
                            await send(.previousRidesLoaded(try await persistenceClient.fetchRouteRides(id)))
                        } catch {
                            logger.error("fetchRouteRides failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                )

            case let .routeLoaded(coordinates, elevationProfile):
                state.coordinates = coordinates
                state.elevationProfileMeters = elevationProfile
                return .none

            case .previousRidesLoaded(let rides):
                state.previousRides = rides
                return .none

            case .weatherLoaded(let forecast):
                state.weather = .loaded(forecast)
                return .none

            case .weatherUnavailable(let reason):
                state.weather = .unavailable(reason)
                return .none

            case .useRouteButtonTapped:
                return .send(.delegate(.useRoute(state.summary.reference)))

            case .delegate:
                return .none
            }
        }
    }
}

/// S20's Weather section (#204).
enum RouteWeather: Equatable {
    case loading
    /// The route's start is a fixed coordinate, so unlike S05.1 there is no location permission
    /// to ask for.
    case unavailable(Unavailable)
    case loaded(AttributedForecast)

    enum Unavailable: Equatable {
        /// WeatherKit failed with no usable network: the one case the rider can fix.
        case offline
        /// Anything else: WeatherKit failed online (or the App ID lacks its App Service), or the
        /// route has no start to ask about.
        case failed
    }
}
