import SwiftUI
import SwiftData
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]

    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.tabSelected)) {

            // ── Rides ────────────────────────────────────────────────────────
            NavigationStack {
                RidesView(
                    store: store.scope(state: \.rides, action: \.rides),
                    recordedItems: items,
                    onStartRide: { store.send(.startRideTapped) }
                )
                .toolbar {
                    if store.activeRide == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                store.send(.startRideTapped)
                            } label: {
                                Label("Start Ride", systemImage: "play.fill")
                            }
                            .accessibilityLabel("Start Ride")
                        }
                    }
                }
            }
            .tabItem { Label("Rides", systemImage: "figure.outdoor.cycle") }
            .tag(AppFeature.Tab.rides)

            // ── Routes ───────────────────────────────────────────────────────
            NavigationStack {
                RoutesView(store: store.scope(state: \.routes, action: \.routes))
            }
            .tabItem { Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            .tag(AppFeature.Tab.routes)

            // ── Settings ─────────────────────────────────────────────────────
            NavigationStack {
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppFeature.Tab.settings)
        }

        // ── Active Ride Accessory (Apple Music mini-player pattern) ──────────
        .tabViewBottomAccessory(isEnabled: store.activeRide != nil) {
            if store.activeRide != nil {
                ActiveRideAccessoryView(onOpen: {
                    store.send(.dashboardDismissed)
                }) {
                    store.send(.dashboardDismissed)
                }
                .padding(.horizontal, 4)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.cyPrimary)
        .tabViewStyle(.tabBarOnly)
        .fontDesign(.rounded)

        // ── New Ride Sheet ────────────────────────────────────────────────────
        .sheet(isPresented: Binding(
            get: { store.isShowingNewRide },
            set: { _ in store.send(.newRideSheetDismissed) }
        )) {
            NewRideView(
                onCancel: { store.send(.newRideSheetDismissed) },
                onStartRide: { store.send(.rideStartConfirmed) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        // ── Active Ride Dashboard (fullScreenCover) ───────────────────────────
        .fullScreenCover(isPresented: Binding(
            get: { store.isDashboardPresented },
            set: { _ in store.send(.dashboardDismissed) }
        )) {
            if let rideStore = store.scope(state: \.activeRide, action: \.activeRide) {
                RideDashboardView(
                    store: rideStore,
                    onClose: { store.send(.dashboardDismissed) },
                    onFinish: { store.send(.rideFinished) }
                )
            }
        }
    }
}
