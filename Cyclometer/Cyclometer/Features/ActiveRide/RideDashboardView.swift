import SwiftUI
import ComposableArchitecture

/// Full-screen active ride dashboard — a fullScreenCover that zooms out of the ride
/// accessory and collapses back into it on a drag down (#333).
/// Matches prototype RideDashboardView with TCA store replacing local @State.
/// Its pages come from the rider's `dashboardLayout` (#139), each a 2-col × 7-row widget grid.
struct RideDashboardView: View {
    @Bindable var store: StoreOf<ActiveRideFeature>
    /// The dashboard's full-screen size, which S08's previews take their proportions from (#142).
    @State private var canvas = CGSize.zero

    var body: some View {
        // S05 — Map widget safe-area bleed. The toolbar floats as an overlay
        // (not a safe-area inset) so the grid's map cell can extend behind it
        // all the way to the physical screen bottom.
        TabView(selection: $store.visibleDashboardPage.sending(\.dashboardPageChanged)) {
            // Identified by page, not index: S07 (#141) inserts and prunes pages, and a view keyed
            // by index would carry one page's widget state onto another.
            ForEach(Array(store.dashboardLayout.pages.enumerated()), id: \.element.id) { index, page in
                DashboardPageView(page: page, store: store)
                    .tag(index)
            }
        }
        .environment(\.isEditingDashboard, store.isEditingDashboard)
        .background(Color.cyBgSecondary)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.all)
        .onGeometryChange(for: CGSize.self, of: \.size) { canvas = $0 }
        // The turn the rider is about to make, centred over the whole dashboard (#197, Sketch
        // "Sxx - Route overlay"). Not hit-testable, so the rider can still page through it.
        .overlay { DashboardTurnOverlay(store: store) }
        // Grabber floats as a top overlay (not a safe-area inset) so it does not
        // push page content down. The overlay keeps the safe area, so the grabber
        // sits just below the Dynamic Island while the pages bleed up behind it.
        .overlay(alignment: .top) { DashboardTopBar(store: store) }
        // The dots share the ride controls' row, flush with the buttons' bottom edge (#447), and
        // sit beneath them: a long indicator can be drawn over, but never takes a button's touch.
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                DashboardPageIndicator(store: store)
                RideControls(store: store)
            }
            .padding(.bottom, -1 * Spacing.cornerMd)
        }
        .overlay {
            if store.isEditingDashboard {
                DashboardEditControls(store: store)
            }
        }
        // S07 (#141): Done is the only way out of edit mode — no drag-down minimise — and its
        // controls take the status bar's place beside the Dynamic Island, as on SpringBoard.
        .interactiveDismissDisabled(store.isEditingDashboard)
        .statusBarHidden(store.isEditingDashboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Ride effects (timer/HR/radar/location) are started by AppFeature when
        // the ride begins and live for the whole ride, so they keep running when
        // this dashboard is minimized to the accessory strip. Do NOT start them
        // from a view `.task` here — that ties them to this view's lifetime.
        .alert($store.scope(state: \.finishAlert, action: \.finishAlert))
        .sheet(isPresented: $store.isAddWidgetPresented.sending(\.addWidgetPresentationChanged)) {
            AddWidgetSheet(store: store, canvas: gridSize)
        }
        .sheet(isPresented: $store.isSensorsSheetPresented.sending(\.sensorsSheetPresentationChanged)) {
            SensorsSheet { store.sensorHealth.devices }
        }
    }

    /// The widget grid's size: the screen, less the radar lane beside it when it shows
    /// (`DashboardPageView`).
    private var gridSize: CGSize {
        CGSize(width: canvas.width - (store.isRadarSidebarVisible ? Spacing.radarColumnWidth : 0), height: canvas.height)
    }

    /// The banner slot holds exactly one notice. Four sources can be armed at once, so they
    /// are resolved to a single value here rather than each rendering its own capsule and
    /// stacking. A turn is not one of them: it has the centred `TurnInstructionOverlay` (#197).
    ///
    /// 1. **A speed-source switch** — it changes what the rider is currently reading.
    /// 2. **A wheel auto-calibration.**
    /// 3. **Rain on the route ahead** (#152) — informational, so below the two that change the
    ///    numbers on screen.
    /// 4. **Off route** — last because it is the only one that lasts. It stays up until the
    ///    rider rejoins, so ranking it higher would hide any of the others for their whole
    ///    four seconds.
    ///
    /// Takes the inputs rather than the state, so the view keeps observing exactly those and
    /// the order can be tested without rendering a dashboard. Only the winner's text is built.
    /// A notice whose text carries a unit symbol is spoken with the unit in words (#568).
    static func banner(
        sourceSwitch: String?,
        calibrationMM: Int?,
        rain: RainAhead?,
        unitSystem: UnitSystem,
        isOffRoute: Bool
    ) -> RideBanner? {
        if let sourceSwitch { return RideBanner(text: sourceSwitch, icon: "shuffle") }
        if let mm = calibrationMM {
            return RideBanner(
                text: WheelCalibration.bannerText(mm: mm),
                icon: "ruler",
                spokenText: WheelCalibration.spokenBannerText(mm: mm)
            )
        }
        if let rain {
            return RideBanner(
                text: rain.bannerText(unitSystem: unitSystem),
                icon: rain.symbolName,
                spokenText: rain.spokenText(unitSystem: unitSystem)
            )
        }
        if isOffRoute { return RideBanner(text: NavigationFeature.offRouteBannerText, icon: "exclamationmark.triangle") }
        return nil
    }
}

private func rideDashboardPreviewStore(
    initialState: ActiveRideFeature.State,
    reducer: () -> ActiveRideFeature
) -> StoreOf<ActiveRideFeature> {
    let initialState = initialState
    initialState.$preferences.withLock { preferences in
        preferences.dashboardLayout = .rideDashboardPreview
    }
    return Store(initialState: initialState, reducer: reducer)
}

private extension DashboardLayout {
    /// A representative, map-free page keeps the interactive canvas responsive.
    static let rideDashboardPreview = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 3, column: 0),
            WidgetPlacement(HRZonesDashboardWidget.self, size: .oneByOne, row: 3, column: 1),
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(DirectionsDashboardWidget.self, size: .oneByOne, row: 4, column: 1)
        ])
    ])
}

// MARK: - Previews

#Preview("Zone 4 — Radar Active") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        RideDashboardView(
            store: rideDashboardPreviewStore(
                initialState: ActiveRideFeature.State(
                    recordingState: .active,
                    elapsedSeconds: 2340,
                    heartRateBPM: 155,
                    hrZone: 4,
                    isHRPaired: true,
                    cadence: CadenceFeature.State(cadenceRPM: 87),
                    distanceMeters: 12300,
                    speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
                    maxSpeedMPS: 9.47,
                    speedSampleCount: 1560,
                    isRadarPaired: true,
                    radarTargets: [
                        RadarTarget(id: UUID(), relativeVelocityMPS: 8.5, rangeMetres: 45, threatLevel: .warning),
                        RadarTarget(id: UUID(), relativeVelocityMPS: 12.0, rangeMetres: 20, threatLevel: .danger)
                    ],
                    radarConnectionState: .active,
                    wasRadarEverPaired: true
                )
            ) {
                ActiveRideFeature()
            }
        )
    }
}

#Preview("No Radar") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        RideDashboardView(
            store: rideDashboardPreviewStore(
                initialState: ActiveRideFeature.State(
                    recordingState: .active,
                    elapsedSeconds: 2340,
                    heartRateBPM: 155,
                    hrZone: 4,
                    isHRPaired: true,
                    cadence: CadenceFeature.State(cadenceRPM: 87),
                    distanceMeters: 12300,
                    speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
                    maxSpeedMPS: 9.47,
                    speedSampleCount: 1560,
                    isRadarPaired: false,
                    wasRadarEverPaired: false
                )
            ) {
                ActiveRideFeature()
            }
        )
    }
}

#Preview("Edit Mode") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        let store = rideDashboardPreviewStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                elapsedSeconds: 2340,
                heartRateBPM: 155,
                hrZone: 4,
                isHRPaired: true,
                cadence: CadenceFeature.State(cadenceRPM: 87),
                distanceMeters: 12300,
                speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
                maxSpeedMPS: 9.47
            )
        ) {
            ActiveRideFeature()
        }
        // Through the reducer, as a long press does.
        store.send(.dashboardLongPressed)
        return RideDashboardView(store: store)
    }
}

#Preview("Paused") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        RideDashboardView(
            store: rideDashboardPreviewStore(
                initialState: ActiveRideFeature.State(
                    recordingState: .paused,
                    elapsedSeconds: 1230,
                    heartRateBPM: 130,
                    hrZone: 3,
                    isHRPaired: true,
                    cadence: CadenceFeature.State(),
                    distanceMeters: 7600,
                    speed: SpeedFeature.State(speedMPS: 0, activeSpeedSource: .gps),
                    maxSpeedMPS: 8.67
                )
            ) {
                ActiveRideFeature()
            }
        )
    }
}
