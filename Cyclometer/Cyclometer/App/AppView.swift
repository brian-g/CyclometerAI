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
                    onStartRide: { store.send(.startRideButtonTapped) }
                )
                .startRideToolbarItem(isHidden: store.activeRide != nil) {
                    store.send(.startRideButtonTapped)
                }
            }
            .tabItem { Label("Rides", image: "cyclometer.rider") }
            .tag(AppFeature.Tab.rides)

            // ── Routes ───────────────────────────────────────────────────────
            NavigationStack {
                RoutesView(store: store.scope(state: \.routes, action: \.routes))
                    .startRideToolbarItem(isHidden: store.activeRide != nil) {
                        store.send(.startRideButtonTapped)
                    }
            }
            .tabItem { Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            .tag(AppFeature.Tab.routes)

            // ── Settings ─────────────────────────────────────────────────────
            NavigationStack {
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
                    .startRideToolbarItem(isHidden: store.activeRide != nil) {
                        store.send(.startRideButtonTapped)
                    }
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

        // ── Start Ride Sheet (S05.1) ──────────────────────────────────────────
        .sheet(item: $store.scope(state: \.startSheet, action: \.startSheet)) { sheetStore in
            StartSheetView(store: sheetStore)
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
                    onClose: { store.send(.dashboardDismissed) }
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
                    recordingState: .active,
                    elapsedSeconds: 2340,
                    speedKPH: 28.4,
                    heartRateBPM: 155,
                    hrZone: 4,
                    cadence: CadenceFeature.State(cadenceRPM: 87),
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
