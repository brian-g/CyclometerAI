import SwiftUI
import ComposableArchitecture

/// W23 Active Calories on the dashboard (#465). Its tap opens the Calories sheet.
struct CaloriesDashboardWidget: DashboardWidget {
    static let id = "activeCalories"
    static let title = "Active Calories"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        CaloriesWidget(
            kilocalories: store.calories.last?.kilocalories,
            rider: store.energyRider,
            metrics: { store.caloriesMetrics }
        )
    }
}
