import ComposableArchitecture
import Observation
import SwiftUI
import Testing
@testable import Cyclometer

/// #362 — W9 reads only what its face shows. The map sheet's inputs, the growing track above all,
/// are read when the sheet presents, so a GPS point that leaves the turn and distance alone doesn't
/// re-render the widget.
///
/// Observes the adapter's `body` the way SwiftUI does: whatever store fields it reads are the ones
/// whose change re-runs it.
@MainActor
struct DirectionsDashboardWidgetTests {

    private let turn = Maneuver(
        coordinate: RouteCoordinate(latitude: 0, longitude: 0.01, elevationMeters: nil),
        direction: .right,
        name: "Turn right onto County Road S",
        distanceAlongRouteMeters: 1_000
    )

    /// A rider on the route, 347 m short of the turn, with a track behind them.
    private func onRoute() throws -> ActiveRideFeature.State {
        var state = ActiveRideFeature.State(recordingState: .active)
        state.navigation.activeRoute = try #require(NavigationRoute(
            coordinates: [
                RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
                RouteCoordinate(latitude: 0, longitude: 0.02, elevationMeters: nil)
            ],
            maneuvers: [turn]
        ))
        state.navigation.progressMeters = 653
        state.navigation.snappedIndex = 0
        state.trackSegments = [[Coordinate(latitude: 0, longitude: 0)]]
        return state
    }

    /// Whether `mutation` re-runs the adapter's `body` once it has rendered.
    private func invalidates(_ mutation: @escaping (inout ActiveRideFeature.State) -> Void) throws -> Bool {
        let state = try onRoute()
        let store = Store(initialState: state) {
            Reduce<ActiveRideFeature.State, ActiveRideFeature.Action> { state, _ in
                mutation(&state)
                return .none
            }
        }
        let invalidated = LockIsolated(false)
        withObservationTracking {
            _ = DirectionsDashboardWidget(size: .oneByOne, store: store).body
        } onChange: {
            invalidated.setValue(true)
        }
        store.send(.mapOrientationToggled)
        return invalidated.value
    }

    @Test func aTrackPointDoesNotRerenderTheWidget() throws {
        #expect(try !invalidates { $0.trackSegments[$0.trackSegments.count - 1].append(Coordinate(latitude: 0, longitude: 0.001)) })
    }

    /// The control: the harness does see a change the face shows.
    @Test func aCloserTurnRerendersTheWidget() throws {
        #expect(try invalidates { $0.navigation.progressMeters = 700 })
    }

    /// The sheet is W8's, with the track as it stands when it opens — including points recorded
    /// after the widget last rendered.
    @Test func theSheetShowsTheCurrentTrackAndRoute() throws {
        let point = Coordinate(latitude: 0, longitude: 0.001)
        let state = try onRoute()
        let store = Store(initialState: state) {
            Reduce<ActiveRideFeature.State, ActiveRideFeature.Action> { state, _ in
                state.trackSegments[state.trackSegments.count - 1].append(point)
                return .none
            }
        }
        let widget = try #require(DirectionsDashboardWidget(size: .oneByOne, store: store).body as? DirectionsWidget)
        store.send(.mapOrientationToggled)

        let sheet = widget.detail()
        #expect(sheet.trackSegments == [[Coordinate(latitude: 0, longitude: 0), point]])
        #expect(sheet.route == store.mapSheetRoute)
        #expect(!sheet.route.isEmpty)
        #expect(sheet.orientation == store.preferences.mapOrientation)
    }
}
