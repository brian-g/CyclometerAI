import SwiftUI
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        // Paged navigation — three full-screen swipeable pages.
        // Page 1: Ride Metrics (hosts the radar column internally)
        // Page 2: Map / Navigation
        // Page 3: Radar Detail
        TabView(selection: $store.selectedPage.sending(\.pageSelected)) {
            RideMetricsView(
                store: store.scope(state: \.rideMetrics, action: \.rideMetrics)
            )
            .tag(AppFeature.Page.rideMetrics)

            MapNavigationView(
                store: store.scope(state: \.mapNavigation, action: \.mapNavigation)
            )
            .tag(AppFeature.Page.mapNavigation)

            RadarDetailView(
                store: store.scope(state: \.radarDetail, action: \.radarDetail)
            )
            .tag(AppFeature.Page.radarDetail)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
