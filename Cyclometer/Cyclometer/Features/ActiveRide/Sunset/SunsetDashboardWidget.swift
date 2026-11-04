import SwiftUI
import ComposableArchitecture

/// W21 Sunset on the dashboard (#462). Its tap opens W8's map sheet, as W9's does.
struct SunsetDashboardWidget: DashboardWidget {
    static let id = "sunset"
    static let title = "Sunset"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    /// The device's, which decides what "today" is.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let coordinate = store.sunsetFix?.coordinate
        // The sunset is to the minute, so the countdown turns over on the clock's minute. The clock
        // alone also carries it past sunset and midnight, with no fix needed.
        TimelineView(.everyMinute) { context in
            SunsetWidget(
                countdown: Sunset.countdown(now: context.date, coordinate: coordinate, timeZone: timeZone),
                detail: { store.liveMapSheet }
            )
        }
    }
}
