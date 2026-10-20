import ComposableArchitecture
import SwiftUI

/// What the Rides and Routes tabs can push: S15 and S20, on either stack (#426).
///
/// One type for both tabs because each detail screen links to the other. S20's Previous Rides
/// rows open S15, and S15's Route row opens S20. TCA's `NavigationLink(state:)` reports an issue
/// unless the link's state type is the enclosing stack's element type, so a link built inside
/// `RouteDetailList` can only push on a stack of the same type whichever tab it is shown in.
@Reducer(state: .equatable, action: .equatable)
enum RideRoutePath {
    case ride(RideDetailFeature)
    case route(RouteDetailFeature)
}

/// The `destination:` of both tabs' stacks.
struct RideRoutePathView: View {
    let store: StoreOf<RideRoutePath>
    /// Hides S20's Use Route while a ride records, as every tab hides Start Ride.
    var isUseRouteHidden = false

    var body: some View {
        switch store.case {
        case .ride(let rideStore):
            RideDetailView(store: rideStore)
        case .route(let routeStore):
            RouteDetailView(store: routeStore, isUseRouteHidden: isUseRouteHidden)
        }
    }
}
