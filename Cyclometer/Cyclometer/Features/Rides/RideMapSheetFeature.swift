import ComposableArchitecture
import Foundation

/// S15's full-screen map (#538): the route with pan and zoom, opened by tapping the map header.
///
/// Holds what the map draws, copied from `RideDetailFeature` when the sheet opens. No actions
/// yet: the basemap, layer and route-coloring controls that will need them are #537.
@Reducer
struct RideMapSheetFeature {
    @ObservableState
    struct State: Equatable {
        var segments: [[RouteCoordinate]]
        var passes: [VehiclePassEventDTO]
        var unitSystem: UnitSystem
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

/// S15's vehicle-pass sheet (#538): each pass's time and the vehicle's speed. Rows aren't
/// tappable, so there is nothing to act on.
@Reducer
struct RidePassesFeature {
    @ObservableState
    struct State: Equatable {
        /// Oldest first, as `RideDetailFeature` holds them.
        var passes: [VehiclePassEventDTO]
        var unitSystem: UnitSystem
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
