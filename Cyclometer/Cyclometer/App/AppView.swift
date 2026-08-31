import SwiftUI
import SwiftData
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    // Only finished rides belong in the Rides list — an in-progress ride is
    // reflected live via the ActiveRideFeature accessory strip instead, not as a
    // history entry (#171 review).
    @Query(
        filter: AppView.endedRidesFilter,
        sort: \Ride.startedAt,
        order: .reverse
    ) private var items: [Ride]
    @Environment(\.scenePhase) private var scenePhase

    // #Predicate's macro can't resolve a nested-type member-access chain like
    // `Ride.RecordingState.ended` written directly inside the predicate closure
    // ("key path cannot refer to enum case") — capturing the case in a local first
    // sidesteps that.
    private static let endedRidesFilter: Predicate<Ride> = {
        let ended = Ride.RecordingState.ended
        return #Predicate<Ride> { $0.recordingState == ended }
    }()

    /// The accessory strip shows only while a ride is active or paused (S05.3).
    private var hasVisibleRide: Bool {
        switch store.activeRide?.recordingState {
        case .active, .paused: return true
        default: return false
        }
    }

    var body: some View {
        ZStack() {
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
            
            // ── Active Ride Dashboard ───────────────────────────
            if store.isDashboardPresented {
                if let rideStore = store.scope(state: \.activeRide, action: \.activeRide) {
                    RideDashboardView(
                        store: rideStore,
                        onClose: { store.send(.dashboardDismissed) }
                    )
                    .transition(.move(edge: .bottom)) // Animates beautifully when appearing/dismissing
                    .zIndex(1) // Ensures it sits above the TabView
                    // Any touch resets the auto-dim countdown (#110). Simultaneous so
                    // it observes the touch without stealing it from the ride controls
                    // or the dashboard's page swipe.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in store.send(.userInteracted) }
                    )
                }
            }

            // ── Auto-Dim Blocker (#110) ─────────────────────────────────────────
            // Lowering the backlight does not block touches, so this invisible layer
            // is what makes the dim modal: it swallows the wake touch — taps *and*
            // swipes — so it can't also trigger whatever sits underneath it.
            if store.isDimmed {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in store.send(.userInteracted) }
                    )
                    .accessibilityLabel("Screen dimmed. Tap to wake.")
                    .zIndex(2)
            }

            // ── Onboarding (S01→S02) ──────────────────────────────────────────────
            // Non-dismissible by design (#105) — a manual overlay, not a system
            // presentation, matching the dashboard/dim-blocker idiom above rather than
            // introducing `.fullScreenCover`.
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
                    .zIndex(3)
            }
        }
        .animation(.smooth, value: store.isDashboardPresented)
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(isActive: phase == .active))
        }
        // Hands the rider's persisted pairings to BLECSCClient, which connects
        // nothing it hasn't been told about.
        .task { await store.send(.task).finish() }
    }
}

// MARK: - Previews

#Preview("Rides Tab") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock { $0.hasCompletedOnboarding = true }
        return AppView(
            store: Store(initialState: AppFeature.State()) {
                AppFeature()
            }
        )
        .modelContainer(for: Ride.self, inMemory: true)
    }
}

#Preview("Active Ride") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
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
        .modelContainer(for: Ride.self, inMemory: true)
    }
}
