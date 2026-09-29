import SwiftUI
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    /// The dashboard zooms out of the ride accessory and collapses back into it (#333).
    @Namespace private var dashboardZoom

    /// The accessory strip shows only while a ride is active or paused (S05.3).
    private var hasVisibleRide: Bool {
        switch store.activeRide?.recordingState {
        case .active, .paused: return true
        default: return false
        }
    }

    /// The dashboard's store while it's presented. `item:` rather than `isPresented:`
    /// so SwiftUI keeps the last store through the collapse: Finish nils `activeRide`
    /// in the same action that dismisses, and the scoped store holds its last state.
    private var dashboardStore: Binding<StoreOf<ActiveRideFeature>?> {
        Binding(
            get: {
                store.isDashboardPresented
                    ? store.scope(state: \.activeRide, action: \.activeRide)
                    : nil
            },
            set: { if $0 == nil { store.send(.dashboardDismissed) } }
        )
    }

    var body: some View {
        ZStack() {
            TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
                
                // ── Rides ────────────────────────────────────────────────────────
                // Brings its own stack, driven by `RidesFeature.path`, so a row pushes S15 as
                // reducer state (#251) — the Routes tab's arrangement.
                RidesNavigationStack(
                    store: store.scope(state: \.rides, action: \.rides),
                    isStartRideHidden: store.activeRide != nil,
                    onStartRide: { store.send(.startRideButtonTapped) }
                )
                .tabItem { Label("Rides", image: "cyclometer.rider") }
                .tag(AppFeature.Tab.rides)
                
                // ── Routes ───────────────────────────────────────────────────────
                // Brings its own stack, driven by `RoutesFeature.path`, so a row pushes S20 as
                // reducer state (#195). Start Ride is passed in rather than layered on from
                // here: this screen has toolbar items of its own, and an ancestor's item would
                // sort ahead of them.
                RoutesNavigationStack(
                    store: store.scope(state: \.routes, action: \.routes),
                    isStartRideHidden: store.activeRide != nil,
                    onStartRide: { store.send(.startRideButtonTapped) }
                )
                .tabItem { Label("Routes", systemImage: RouteLibrary.symbolName) }
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
            // Visible only while a ride is active or paused (S05.3), not during the
            // brief .idle window before `.task` starts the ride.
            .tabViewBottomAccessory(isEnabled: hasVisibleRide) {
                if let ride = store.activeRide, hasVisibleRide {
                    ActiveRideAccessoryView(
                        progress: nil,                       // no route model yet → bicycle glyph
                        distanceMeters: ride.distanceMeters,
                        speedMPS: ride.speedMPS,
                        elapsedSeconds: ride.elapsedSeconds,
                        unit: ride.unitSystem,
                        onOpen: { store.send(.dashboardOpened) }
                    )
                    .padding(.horizontal, 4)
                    .matchedTransitionSource(id: DashboardZoom.sourceID, in: dashboardZoom)
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

            // ── Ride Summary (S10) ───────────────────────────────────────────────
            .sheet(item: $store.scope(state: \.rideSummary, action: \.rideSummary)) { summaryStore in
                RideSummaryView(store: summaryStore)
                    .presentationDragIndicator(.visible)
            }

            // ── Active Ride Dashboard (#333) ─────────────────────────────────────
            // A system zoom presentation, as Apple Music's player does it: it expands from
            // the accessory, and a drag down anywhere collapses it back in. Hand-built
            // motion can't do this: moving a view re-flows its safe-area extension, so
            // the old overlay squished as it was dragged (#330).
            .fullScreenCover(item: dashboardStore) { rideStore in
                RideDashboardView(store: rideStore)
                    .navigationTransition(.zoom(sourceID: DashboardZoom.sourceID, in: dashboardZoom))
            }

            // ── Onboarding (S01→S02) ──────────────────────────────────────────────
            // Non-dismissible by design (#105) — a manual overlay, not a system
            // presentation.
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
                    .zIndex(3)
            }
        }
        // Auto-dim (#110, #333): the countdown pauses under any finger in the app
        // window, and while dimmed a blocker window takes every touch.
        .background {
            AutoDimWindowBridge(
                isTracking: store.isDashboardPresented,
                isDimmed: store.isDimmed,
                onTouchBegan: { store.send(.touchBegan) },
                onTouchEnded: { store.send(.touchEnded) },
                onWake: { store.send(.wakeTapped) }
            )
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(isActive: phase == .active))
        }
        // Hands the rider's persisted pairings to BLECSCClient, which connects
        // nothing it hasn't been told about.
        .task { await store.send(.task).finish() }
        // "Open in Cyclometer" on a `.gpx` from Files, Mail or Safari.
        .onOpenURL { store.send(.fileOpened($0)) }
    }
}

/// The dashboard's zoom-transition source, shared by the accessory and the cover.
private enum DashboardZoom {
    static let sourceID = "activeRideDashboard"
}

// MARK: - Previews

#Preview("Rides Tab") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock { $0.hasCompletedOnboarding = true }
        return AppView(
            store: Store(initialState: AppFeature.State()) {
                AppFeature()
            }
        )
    }
}

#Preview("Active Ride") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock { $0.hasCompletedOnboarding = true }
        return AppView(
            store: Store(
                initialState: AppFeature.State(
                    activeRide: ActiveRideFeature.State(
                        recordingState: .active,
                        elapsedSeconds: 2340,
                        speedKPH: 28.4,
                        heartRateBPM: 155,
                        hrZone: 4,
                        isHRPaired: true,
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
    }
}
