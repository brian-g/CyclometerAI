import SwiftUI
import ComposableArchitecture

/// W10 Weather on the dashboard (#150): the wind first, as the rider meets it, or rain when it is
/// forecast.
struct WeatherDashboardWidget: DashboardWidget {
    static let id = "weather"
    static let title = "Weather"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]
    static let category = WidgetCategory.weather

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        // Once a minute, as W21 does: rain turns to "Now" on the hour, and a forecast an hour old
        // goes, whether or not a fix arrives.
        TimelineView(.everyMinute) { context in
            widget(at: context.date)
        }
    }

    private func widget(at now: Date) -> WeatherWidget {
        let forecast = store.weather.forecast(at: now)
        return WeatherWidget(
            reading: forecast?.current,
            course: store.weather.course,
            unit: store.unitSystem,
            rain: forecast.flatMap { RainOutlook($0, now: now) },
            metrics: { date in
                store.weather.metrics(at: date, unit: store.unitSystem, rider: store.coordinate,
                                      route: store.navigation.activeRoute?.coordinates ?? [])
            },
            onSheetAppear: { store.send(.weatherSheetOpened) },
            size: size
        )
    }
}
