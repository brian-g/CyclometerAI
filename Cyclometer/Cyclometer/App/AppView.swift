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
                ActiveRideAccessoryView(
                    distanceKM: store.activeRide?.distanceKM ?? 0,
                    speedKPH: store.activeRide?.speedKPH ?? 0,
                    onOpen: { store.send(.dashboardOpened) },
                    onDismiss: { store.send(.dashboardDismissed) }
                )
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

// MARK: - Previews

#Preview("Rides Tab") {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
    .modelContainer(for: Item.self, inMemory: true)
}

#Preview("Active Ride") {
    AppView(
        store: Store(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(
                    elapsedSeconds: 2340,
                    speedKPH: 28.4,
                    heartRateBPM: 155,
                    hrZone: 4,
                    cadenceRPM: 87,
                    distanceMeters: 12300,
                    speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
                    maxSpeedKPH: 34.1,
                    speedSampleCount: 120,
                    speedSampleSum: 3408
                )
            )
        ) {
            AppFeature()
        }
    )
    .modelContainer(for: Item.self, inMemory: true)
}
