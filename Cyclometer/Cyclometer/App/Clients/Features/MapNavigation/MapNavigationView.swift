import SwiftUI
import ComposableArchitecture
import MapKit

struct MapNavigationView: View {
    let store: StoreOf<MapNavigationFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()
            // TODO: MapKit view with GPX route polyline overlay
            // TODO: Turn instruction strip at bottom
            VStack {
                Spacer()
                Text("Map & Navigation")
                    .font(.cyMetricMedium)
                    .foregroundStyle(Color.cyTextPrimary)
                Spacer()
            }
        }
        .onAppear { store.send(.onAppear) }
    }
}
