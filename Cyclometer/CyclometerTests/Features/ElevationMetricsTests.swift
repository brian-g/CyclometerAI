import ComposableArchitecture
import Foundation
import Observation
import SwiftUI
import Testing
@testable import Cyclometer

/// What the Elevation sheet's rows read (#387).
struct ElevationMetricsTests {

    @Test func readsInTheRidersUnits() {
        let metric = ElevationMetrics.sample(.metric)
        #expect(metric.current == MetricReading(shown: "284 m", spoken: "284 meters"))
        #expect(metric.ascent.shown == "412 m")
        let imperial = ElevationMetrics.sample(.imperial)
        #expect(imperial.ascent == MetricReading(shown: "1,352 ft", spoken: "1,352 feet"))
    }

    @Test func gradesAreSigned() {
        let metrics = ElevationMetrics.sample()
        #expect(metrics.grade == MetricReading(shown: "+4%", spoken: "4 percent"))
        #expect(metrics.steepestDescent == MetricReading(shown: "-8%", spoken: "-8 percent"))
    }

    @Test func noReadingIsADashNotAZero() {
        let empty = ElevationMetrics()
        #expect(empty.current == .missing)
        #expect(empty.grade == .missing)
        #expect(empty.highest == .missing)
        // Totals are real at zero, as distance is.
        #expect(empty.ascent.shown == "0 m")
    }
}

/// W14–W18 read only what their faces show: the sheet's inputs are read when it presents. Observes
/// each adapter's `body` the way SwiftUI does (pattern: `DirectionsDashboardWidgetTests`).
@MainActor
struct ElevationDashboardWidgetTests {

    private func withRoute() throws -> ActiveRideFeature.State {
        var state = ActiveRideFeature.State(recordingState: .active)
        state.navigation.activeRoute = try #require(NavigationRoute(
            coordinates: [
                RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: 250),
                RouteCoordinate(latitude: 0, longitude: 0.02, elevationMeters: 300)
            ],
            maneuvers: []
        ))
        return state
    }

    /// Whether `mutation` re-runs `widget`'s `body` once it has rendered.
    private func invalidates(
        _ widget: @escaping (StoreOf<ActiveRideFeature>) -> any View,
        _ mutation: @escaping (inout ActiveRideFeature.State) -> Void
    ) throws -> Bool {
        let state = try withRoute()
        let store = Store(initialState: state) {
            Reduce<ActiveRideFeature.State, ActiveRideFeature.Action> { state, _ in
                mutation(&state)
                return .none
            }
        }
        let invalidated = LockIsolated(false)
        withObservationTracking {
            _ = widget(store).body
        } onChange: {
            invalidated.setValue(true)
        }
        store.send(.mapOrientationToggled)
        return invalidated.value
    }

    private let newSample: (inout ActiveRideFeature.State) -> Void = {
        $0.altitudeSamples.append(AltitudeSample(time: .now, meters: 280))
    }

    @Test func aNewSampleDoesNotRerenderTheTotals() throws {
        #expect(try !invalidates({ AscentDashboardWidget(size: .oneByOne, store: $0) }, newSample))
        #expect(try !invalidates({ GradeDashboardWidget(size: .oneByOne, store: $0) }, newSample))
    }

    /// With a route profile in hand, the ride's own history is W17's, not W18's.
    @Test func aNewSampleDoesNotRerenderRouteElevationOnARoute() throws {
        #expect(try !invalidates({ RouteElevationDashboardWidget(size: .twoByOne, store: $0) }, newSample))
        #expect(try invalidates({ ElevationDashboardWidget(size: .twoByOne, store: $0) }, newSample))
    }
}
