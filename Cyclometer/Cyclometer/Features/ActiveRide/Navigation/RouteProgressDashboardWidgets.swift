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
            hasRoute: store.navigation.activeRoute != nil,
            isTurnByTurnEnabled: store.navigation.preferences.isTurnByTurnEnabled,
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

    /// Moving seconds before the average is trusted for an arrival. In the first seconds it is
    /// barely above walking pace, and the arrival it gives can be hours out (#461 review).
    static let settlingSeconds = 60

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        let remainingMeters = store.navigation.remainingDistanceMeters
        let averageSpeedMPS = store.averageSpeedMPS
        let movingSeconds = store.speedSampleCount
        // Stopped, nothing in the store changes — the distance left and the moving average both
        // hold — but the arrival still moves later with the clock. Every second rather than every
        // minute, since the arrival's minute turns over at the clock's seconds plus the time left.
        // With no arrival to move, it doesn't tick at all.
        let isArriving = Self.arrival(
            now: .now, remainingMeters: remainingMeters, averageSpeedMPS: averageSpeedMPS, movingSeconds: movingSeconds
        ) != nil
        TimelineView(EverySecondSchedule(isRunning: isArriving)) { context in
            ETAWidget(
                arrival: Self.arrival(
                    now: context.date,
                    remainingMeters: remainingMeters,
                    averageSpeedMPS: averageSpeedMPS,
                    movingSeconds: movingSeconds
                ),
                hasRoute: store.navigation.activeRoute != nil,
                isTurnByTurnEnabled: store.navigation.preferences.isTurnByTurnEnabled,
                detail: { store.liveMapSheet }
            )
        }
    }

    /// Now, plus what is left of the route at the ride's moving average (W2's). Nil with no route
    /// to follow, until the average has `settlingSeconds` of moving behind it, and once the route
    /// is complete — there is nothing left to arrive at.
    static func arrival(now: Date, remainingMeters: Double?, averageSpeedMPS: Double, movingSeconds: Int) -> Date? {
        guard let remainingMeters, remainingMeters > 0, averageSpeedMPS > 0, movingSeconds >= settlingSeconds
        else { return nil }
        return now.addingTimeInterval(remainingMeters / averageSpeedMPS)
    }
}

/// A tick each second while running, and none while not. One type either way, so stopping it
/// doesn't change the `TimelineView`'s identity — which would close an open map sheet.
private struct EverySecondSchedule: TimelineSchedule, Equatable {
    let isRunning: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldSequence<Date, (Date?, Bool)> {
        sequence(first: startDate) { [isRunning] in isRunning ? $0.addingTimeInterval(1) : nil }
    }
}

/// What VoiceOver reads for W19 and W20 when they show "—" (#461 review): a route drawn on the map
/// but not followed is not "No route".
enum RouteProgressReading {
    static func empty(hasRoute: Bool, isTurnByTurnEnabled: Bool) -> String {
        if !hasRoute { return "No route" }
        if !isTurnByTurnEnabled { return "Turn-by-turn off" }
        return "No reading"
    }
}
