import SwiftUI
import ComposableArchitecture

/// W14 Ascent on the dashboard (#387).
struct AscentDashboardWidget: DashboardWidget {
    static let id = "ascent"
    static let title = "Ascent"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        ElevationTotalWidget(
            title: Self.title, meters: store.elevation.ascentMeters, unit: store.unitSystem,
            metrics: { store.elevationMetrics }
        )
    }
}

/// W15 Descent on the dashboard (#387).
struct DescentDashboardWidget: DashboardWidget {
    static let id = "descent"
    static let title = "Descent"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        ElevationTotalWidget(
            title: Self.title, meters: store.elevation.descentMeters, unit: store.unitSystem,
            metrics: { store.elevationMetrics }
        )
    }
}

/// W16 Grade on the dashboard (#387).
struct GradeDashboardWidget: DashboardWidget {
    static let id = "grade"
    static let title = "Grade"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        GradeWidget(percent: store.elevation.gradePercent, metrics: { store.elevationMetrics })
    }
}

/// W17 Elevation on the dashboard (#387).
struct ElevationDashboardWidget: DashboardWidget {
    static let id = "elevation"
    static let title = "Elevation"
    static let supportedSizes: [WidgetSize] = [.twoByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        ElevationWidget(
            altitude: store.altitude,
            gradePercent: store.elevation.gradePercent,
            history: store.altitudeWatermarkSamples,
            unit: store.unitSystem,
            metrics: { store.elevationMetrics }
        )
    }
}

/// W18 Route Elevation on the dashboard (#387).
struct RouteElevationDashboardWidget: DashboardWidget {
    static let id = "routeElevation"
    static let title = "Route Elevation"
    static let supportedSizes: [WidgetSize] = [.twoByOne]
    static let category = WidgetCategory.route

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        let profile = store.navigation.activeRoute?.elevationProfile
        RouteElevationWidget(
            altitude: store.altitude,
            gradePercent: store.elevation.gradePercent,
            routeProfile: profile,
            routeProgress: profile == nil ? nil : store.navigation.routeProgressFraction,
            // Only W17's face reads it: a route's profile stands in for the ride's.
            history: profile == nil ? store.altitudeWatermarkSamples : [],
            unit: store.unitSystem,
            metrics: { store.elevationMetrics }
        )
    }
}
