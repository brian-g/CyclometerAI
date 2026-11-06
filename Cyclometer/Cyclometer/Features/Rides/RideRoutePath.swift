import ComposableArchitecture
import SwiftUI

/// What the Rides and Routes tabs can push: S15 and S20, on either stack (#426).
///
/// One type for both tabs because each detail screen links to the other. S20's Previous Rides
/// rows open S15, and S15's Route row opens S20. TCA's `NavigationLink(state:)` reports an issue
/// unless the link's state type is the enclosing stack's element type, so a link built inside
/// `RouteDetailList` can only push on a stack of the same type whichever tab it is shown in.
@Reducer
enum RideRoutePath {
    case ride(RideDetailFeature)
    case route(RouteDetailFeature)
}

extension RideRoutePath.State: Equatable {}
extension RideRoutePath.Action: Equatable {}

extension StackState<RideRoutePath.State> {
    /// Carries an S15 edit (#538) to the other copies of the ride on the same stack: another S15
    /// of it further down (S15 → S20 → Previous Rides → the same S15), and the Previous Rides
    /// row an S20 seeds S15 from, which would otherwise open it under the old title.
    mutating func applyRideEdit(id: UUID, title: String, notes: String) {
        for elementID in ids {
            switch self[id: elementID] {
            case .ride(var ride) where ride.summary.id == id:
                ride.summary.title = title
                ride.stats?.notes = notes
                self[id: elementID] = .ride(ride)
            case .route(var route):
                guard let index = route.previousRides.firstIndex(where: { $0.rideId == id }) else { continue }
                route.previousRides[index].title = title
                self[id: elementID] = .route(route)
            default:
                continue
            }
        }
    }
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
