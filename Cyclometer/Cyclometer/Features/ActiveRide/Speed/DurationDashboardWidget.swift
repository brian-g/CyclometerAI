import SwiftUI
import ComposableArchitecture

/// W3 Duration on the dashboard.
struct DurationDashboardWidget: DashboardWidget {
    static let id = "duration"
    static let title = "Duration"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        // Moving time, as UX.md §W3 specifies — the seconds W2's average divides by, so
        // W2 × W3 = W6. W1's Time is `elapsedSeconds`, which counts stopped seconds too (#140 review).
        DurationWidget(movingSeconds: store.speedSampleCount, metrics: { store.rideMetrics })
    }
}
