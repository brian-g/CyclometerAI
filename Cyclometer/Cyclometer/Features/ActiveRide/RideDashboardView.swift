import SwiftUI
import ComposableArchitecture
import AudioToolbox

/// Full-screen active ride dashboard — a fullScreenCover that zooms out of the ride
/// accessory and collapses back into it on a drag down (#333).
/// Matches prototype RideDashboardView with TCA store replacing local @State.
/// Its pages come from the rider's `dashboardLayout` (#139), each a 2-col × 7-row widget grid.
struct RideDashboardView: View {
    @Bindable var store: StoreOf<ActiveRideFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The dashboard's full-screen size, which S08's previews take their proportions from (#142).
    @State private var canvas = CGSize.zero

    var body: some View {
        // S05 — Map widget safe-area bleed. The toolbar floats as an overlay
        // (not a safe-area inset) so the grid's map cell can extend behind it
        // all the way to the physical screen bottom.
        TabView(selection: Binding(
            get: { store.visibleDashboardPage },
            set: { store.send(.dashboardPageChanged($0)) }
        )) {
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
        .overlay {
            ZStack {
                if let turn = store.navigation.turnInstruction {
                    TurnInstructionOverlay(maneuver: turn)
                        .transition(turnTransition)
                }
            }
            .animation(.default, value: store.navigation.turnInstruction)
            .allowsHitTesting(false)
        }
        // Grabber floats as a top overlay (not a safe-area inset) so it does not
        // push page content down. The overlay keeps the safe area, so the grabber
        // sits just below the Dynamic Island while the pages bleed up behind it.
        .overlay(alignment: .top) {
            VStack(spacing: Spacing.xs) {
                // Edit mode can't be minimised (#141), so the grabber, a minimise cue, steps aside.
                if !store.isEditingDashboard {
                    grabber()
                }
                if let banner = activeBanner {
                    RideBanner(text: banner.text, icon: banner.icon)
                        .transition(bannerTransition)
                        // A notice, not a control. In edit mode it sits over the top row's remove
                        // buttons (#141 review), so touches pass through to them.
                        .allowsHitTesting(false)
                }
            }
            .animation(.default, value: activeBanner?.text)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: Spacing.xs) {
                pageIndicator
                rideControls
            }
        }
        .overlay {
            if store.isEditingDashboard {
                editControls
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
    }

    /// The widget grid's size: the screen, less the radar lane beside it when it shows
    /// (`DashboardPageView`).
    private var gridSize: CGSize {
        CGSize(width: canvas.width - (store.isRadarSidebarVisible ? Spacing.radarColumnWidth : 0), height: canvas.height)
    }

    // ── Grabber ───────────────────────────────────────────────────────────────
    // Sits at the top of the safe area, just below the Dynamic Island. A visual
    // affordance only: the zoom presentation's own drag, anywhere on the dashboard,
    // collapses it into the accessory (#333).
    private func grabber() -> some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: Spacing.xxl, height: Spacing.grabberHeight)
            .frame(maxWidth: .infinity, minHeight: Spacing.sm, alignment: .top)
            .padding(.bottom, Spacing.xs)
            // VoiceOver can't perform the drag.
            .accessibilityRepresentation {
                Button("Minimize Ride") { dismiss() }
            }
    }

    // ── Edit controls — S07 (#141), Sketch "S07 - Dashboard Customization" ─────
    // Add and Done flank the Dynamic Island, centred in the band above the safe area, so they
    // never sit on a top-row widget's remove button. Add opens S08 (#142).
    private var editControls: some View {
        GeometryReader { proxy in
            HStack {
                EditModeButton(title: "Add Widget", systemImage: "plus") {
                    store.send(.addWidgetTapped)
                }
                Spacer()
                EditModeButton(title: "Done", systemImage: "checkmark", isProminent: true) {
                    store.send(.dashboardEditingDoneTapped, animation: .default)
                }
            }
            .padding(.horizontal, Spacing.xl)
            // At least a tap target tall: without an island or notch, the hidden status bar
            // leaves no top inset, and a 0 pt band would put Done — the only way out — half off
            // screen.
            .frame(height: max(proxy.safeAreaInsets.top, Spacing.mapControl))
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .transition(.opacity)
    }

    // ── Paging indicator — always visible; one dot per layout page ─────────────
    private var pageIndicator: some View {
        let pageCount = store.dashboardLayout.pages.count
        return HStack(spacing: Spacing.xs) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == store.visibleDashboardPage ? Color.cyPrimary : Color.cyTextTertiary)
                    .frame(width: Spacing.pageIndicatorDot, height: Spacing.pageIndicatorDot)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(store.visibleDashboardPage + 1) of \(pageCount)")
        // VoiceOver's way into S07 edit mode (#141), which is otherwise only a long press.
        .accessibilityAction(named: "Edit Dashboard") {
            store.send(.dashboardLongPressed, animation: .default)
        }
    }

    // ── Ride Controls — floating glass buttons (S05) ───────────────────────────
    private var rideControls: some View {
        HStack(spacing: Spacing.sm) {
            if store.isPaused {
                rideControlButton("Resume", systemImage: "play.fill") { store.send(.resumeTapped) }
                    .transition(controlTransition)
                rideControlButton("Finish", systemImage: "stop.fill") { store.send(.finishTapped) }
                    .transition(controlTransition)
            } else {
                rideControlButton("Pause", systemImage: "pause.fill") { store.send(.pauseTapped) }
                    .transition(controlTransition)
            }

            Spacer()

            rideControlButton("Ring Bell", systemImage: "bell.fill") { ringBell() }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.isPaused)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, -1 * Spacing.cornerMd)
    }

    /// One floating glass ride-control button. The icon-only `Label` keeps its
    /// title available to VoiceOver, so no separate `accessibilityLabel` is needed.
    private func rideControlButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button { action() } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    /// Reduce Motion swaps the scale animation for a plain fade.
    private var controlTransition: AnyTransition {
        reduceMotion ? .opacity : .scale.combined(with: .opacity)
    }

    /// Reduce Motion swaps the slide-in for a plain fade.
    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    /// Reduce Motion swaps the pop-in for a plain fade.
    private var turnTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    private var activeBanner: (text: String, icon: String)? {
        Self.banner(
            sourceSwitch: store.speed.sourceSwitchBanner,
            calibration: store.calibration.banner,
            isOffRoute: store.navigation.isOffRoute
        )
    }

    /// The banner slot holds exactly one notice. Three sources can be armed at once, so they
    /// are resolved to a single value here rather than each rendering its own capsule and
    /// stacking. A turn is not one of them: it has the centred `TurnInstructionOverlay` (#197).
    ///
    /// 1. **A speed-source switch** — it changes what the rider is currently reading.
    /// 2. **A wheel auto-calibration.**
    /// 3. **Off route** — last because it is the only one that lasts. It stays up until the
    ///    rider rejoins, so ranking it higher would hide either of the others for their whole
    ///    four seconds.
    ///
    /// Takes the inputs rather than the state, so the view keeps observing exactly those and
    /// the order can be tested without rendering a dashboard.
    static func banner(
        sourceSwitch: String?,
        calibration: String?,
        isOffRoute: Bool
    ) -> (text: String, icon: String)? {
        if let sourceSwitch { return (sourceSwitch, "shuffle") }
        if let calibration { return (calibration, "ruler") }
        if isOffRoute { return (NavigationFeature.offRouteBannerText, "exclamationmark.triangle") }
        return nil
    }

    private func ringBell() {
        AudioServicesPlaySystemSound(1005) // 1005 = system "Tink"; route via AudioClient later
    }
}

/// S07's Add and Done (#141): a glass capsule exactly the Dynamic Island's height and the golden
/// ratio as wide, so the pair reads as part of the island's band. Done is tinted, as a confirm is.
private struct EditModeButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private static let goldenRatio = (1 + sqrt(5.0)) / 2

    var body: some View {
        Button(action: action) {
            // The icon-only `Label` keeps its title for VoiceOver.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(glyphColor)
                .frame(width: Spacing.dynamicIsland * Self.goldenRatio, height: Spacing.dynamicIsland)
                .glassEffect(isProminent ? .regular.tint(.cyPrimary).interactive() : .regular.interactive(), in: .capsule)
                // The capsule is the island's height; the touch area is a full 44 pt.
                .padding(.vertical, (Spacing.mapControl - Spacing.dynamicIsland) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var glyphColor: Color {
        guard isEnabled else { return .cyTextTertiary }
        return isProminent ? .cyTextOnPrimary : .cyPrimary
    }
}

// MARK: - Previews

#Preview("Zone 4 — Radar Active") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        RideDashboardView(
            store: Store(
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
            store: Store(
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
        let store = Store(
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
            store: Store(
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
