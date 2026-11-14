import ComposableArchitecture
import Foundation

/// The wind along a route, for the wind map (#561): S20's route map, and W10's sheet while a route
/// is being ridden. One reducer for both, so they sample, fetch and cancel the same way.
///
/// The parent decides where and when to sample (`WindSampling.points`), because it holds the route,
/// the clock and the speed. It hands over the first sample already answered: the screen's own
/// forecast, fetched at the route's start (S20) or where the rider is (W10). Only the points ahead
/// cost requests.
@Reducer
struct RouteWindFeature {
    @Dependency(\.weatherClient) var weatherClient
    @Dependency(\.date) var date

    private enum CancelID { case fetch }

    @ObservableState
    struct State: Equatable {
        /// In route order, the known sample first. Kept through a refetch, so the arrows don't
        /// blink out while the next ones load.
        var samples: [WindSample] = []
        /// When the last load began, whether or not its requests answered.
        var requestedAt: Date?
        var isFetching = false

        /// Whether a load began less than `RideWeatherFeature.refreshInterval` ago: W10's sheet
        /// doesn't ask again each time it opens. Two-sided, so a clock set back doesn't hold it.
        func isFresh(at now: Date) -> Bool {
            guard let requestedAt else { return false }
            return abs(now.timeIntervalSince(requestedAt)) < RideWeatherFeature.refreshInterval
        }
    }

    enum Action: Equatable {
        /// Sample `ahead`, with `known` already answered. Replaces a load still in flight.
        case load(known: WindSample, ahead: [WindSamplePoint])
        case loaded([WindSample])
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(known, ahead):
                state.requestedAt = date.now
                state.isFetching = true
                if state.samples.isEmpty {
                    state.samples = [known]
                }
                return .run { [weatherClient] send in
                    // Every request failing leaves the known sample: the map still shows the wind
                    // the screen already has.
                    await send(.loaded([known] + (await weatherClient.wind(at: ahead))))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case .loaded(let samples):
                state.samples = samples
                state.isFetching = false
                return .none
            }
        }
    }
}
