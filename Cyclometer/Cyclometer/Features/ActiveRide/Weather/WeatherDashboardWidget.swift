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
        WeatherWidget(
            reading: store.weather.reading,
            course: store.weather.course,
            unit: store.unitSystem,
            rain: store.weather.rain,
            metrics: { store.weatherMetrics },
            size: size
        )
    }
}
