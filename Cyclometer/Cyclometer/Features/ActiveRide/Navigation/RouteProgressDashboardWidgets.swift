import SwiftUI
import ComposableArchitecture

/// W19 Distance Remaining on the dashboard (#461). Its tap opens W8's map sheet, as W9's does.
struct DistanceRemainingDashboardWidget: DashboardWidget {
    static let id = "distanceRemaining"
    static let title = "Distance Remaining"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.route

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        DistanceRemainingWidget(
            remainingMeters: store.navigation.remainingDistanceMeters,
            unit: store.unitSystem,
            detail: { store.liveMapSheet }
        )
    }
}

/// W20 ETA on the dashboard (#461). Its tap opens W8's map sheet, as W9's does.
struct ETADashboardWidget: DashboardWidget {
    static let id = "eta"
    static let title = "ETA"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.route

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        // Stopped, nothing in the store changes — the distance left and the moving average both
        // hold — but the arrival still moves later with the clock. Every second rather than every
        // minute, since the arrival's minute turns over at the clock's seconds plus the time left.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ETAWidget(
                arrival: Self.arrival(
                    now: context.date,
                    remainingMeters: store.navigation.remainingDistanceMeters,
                    averageSpeedMPS: store.averageSpeedMPS
                ),
                detail: { store.liveMapSheet }
            )
        }
    }

    /// Now, plus what is left of the route at the ride's moving average (W2's). Nil with no route
    /// to follow, before the first moving second, and once the route is complete — there is
    /// nothing left to arrive at.
    static func arrival(now: Date, remainingMeters: Double?, averageSpeedMPS: Double) -> Date? {
        guard let remainingMeters, remainingMeters > 0, averageSpeedMPS > 0 else { return nil }
        return now.addingTimeInterval(remainingMeters / averageSpeedMPS)
    }
}

extension Store where State == ActiveRideFeature.State, Action == ActiveRideFeature.Action {
    /// W8's map sheet, built only when it presents, so a track point doesn't re-render the card
    /// that opens it (#362).
    fileprivate var liveMapSheet: LiveMapSheet {
        LiveMapSheet(
            trackSegments: self.trackSegments,
            route: self.mapSheetRoute,
            orientation: self.preferences.mapOrientation,
            onOrientationToggle: { self.send(.mapOrientationToggled) }
        )
    }
}
