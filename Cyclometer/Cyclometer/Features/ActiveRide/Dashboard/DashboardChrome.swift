import SwiftUI
import ComposableArchitecture

// The dashboard's chrome, the parts that float over its pages (#352). Each is its own view and
// reads only its own inputs, so a banner or a pause redraws that part and not the pages under it.
// `RideDashboardView` places them.

// MARK: - Top bar

/// The grabber and the banner slot, below the Dynamic Island.
///
/// The grabber is a visual affordance only: the zoom presentation's own drag, anywhere on the
/// dashboard, collapses it into the accessory (#333).
struct DashboardTopBar: View {
    let store: StoreOf<ActiveRideFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let banner = activeBanner
        VStack(spacing: Spacing.xs) {
            // Edit mode can't be minimised (#141), so the grabber, a minimise cue, steps aside.
            if !store.isEditingDashboard {
                grabber()
            }
            if let banner {
                banner
                    .transition(bannerTransition)
                    // A notice, not a control. In edit mode it sits over the top row's remove
                    // buttons (#141 review), so touches pass through to them.
                    .allowsHitTesting(false)
            }
        }
        .animation(.default, value: banner?.text)
    }

    // Sits at the top of the safe area, just below the Dynamic Island.
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

    /// Reduce Motion swaps the slide-in for a plain fade.
    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var activeBanner: RideBanner? {
        RideDashboardView.banner(
            sourceSwitch: store.speed.sourceSwitchBanner,
            calibrationMM: store.calibration.bannerMM,
            rain: store.weather.rainAhead,
            unitSystem: store.unitSystem,
            isOffRoute: store.navigation.isOffRoute
        )
    }
}

// MARK: - Turn overlay

/// The turn the rider is about to make, centred over the whole dashboard (#197, Sketch
/// "Sxx - Route overlay"). Not hit-testable, so the rider can still page through it.
struct DashboardTurnOverlay: View {
    let store: StoreOf<ActiveRideFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let turn = store.navigation.turnInstruction {
                TurnInstructionOverlay(maneuver: turn)
                    .transition(turnTransition)
            }
        }
        .animation(.default, value: store.navigation.turnInstruction)
        .allowsHitTesting(false)
    }

    /// Reduce Motion swaps the pop-in for a plain fade.
    private var turnTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }
}

// MARK: - Paging indicator

/// Always visible, one dot per layout page.
struct DashboardPageIndicator: View {
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        let pageCount = store.dashboardLayout.pages.count
        HStack(spacing: Spacing.xs) {
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
}

// MARK: - Ride controls

/// The floating glass ride controls (S05). Sensors sits beside Bell, as in the Sketch frame
/// "Sxx - Route overlay" (#466).
struct RideControls: View {
    let store: StoreOf<ActiveRideFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sensorsNeedingAttention = store.sensorHealth.devicesNeedingAttention
        HStack(spacing: Spacing.sm) {
            if store.isPaused {
                RideControlButton("Resume", systemImage: "play.fill") { store.send(.resumeTapped) }
                    .transition(controlTransition)
                RideControlButton("Finish", systemImage: "stop.fill") { store.send(.finishTapped) }
                    .transition(controlTransition)
            } else {
                RideControlButton("Pause", systemImage: "pause.fill") { store.send(.pauseTapped) }
                    .transition(controlTransition)
            }

            Spacer()

            if !sensorsNeedingAttention.isEmpty {
                SensorsButton(devices: sensorsNeedingAttention) { store.send(.sensorsButtonTapped) }
                    .transition(controlTransition)
            }
            RideControlButton("Ring Bell", systemImage: "bell.fill") { store.send(.bellTapped) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.isPaused)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: sensorsNeedingAttention.isEmpty)
        .padding(.horizontal, Spacing.lg)
    }

    /// Reduce Motion swaps the scale animation for a plain fade.
    private var controlTransition: AnyTransition {
        reduceMotion ? .opacity : .scale.combined(with: .opacity)
    }
}

/// One floating glass ride-control button (S05). The icon-only `Label` keeps its title
/// available to VoiceOver, so no separate `accessibilityLabel` is needed.
struct RideControlButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button { action() } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

// MARK: - Edit controls

/// S07's Add and Done (#141), Sketch "S07 - Dashboard Customization". They flank the Dynamic
/// Island, centred in the band above the safe area, so they never sit on a top-row widget's remove
/// button. Add opens S08 (#142).
struct DashboardEditControls: View {
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
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

/// A riding store with sample values, for the chrome previews.
private func chromePreviewStore(
    recordingState: RideRecordingState = .active,
    pairedSensors: [PairedSensor] = [],
    isEditing: Bool = false,
    configure: (inout ActiveRideFeature.State) -> Void = { _ in }
) -> StoreOf<ActiveRideFeature> {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock { $0.pairedSensors = pairedSensors }
        var state = ActiveRideFeature.State(recordingState: recordingState)
        state.isEditingDashboard = isEditing
        configure(&state)
        return Store(initialState: state) { ActiveRideFeature() }
    }
}

#Preview("Controls — Riding") {
    RideControls(store: chromePreviewStore())
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(Color.cyBgSecondary)
}

#Preview("Controls — Paused, Sensor Missing") {
    RideControls(store: chromePreviewStore(
        recordingState: .paused,
        pairedSensors: [PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515")]
    ))
    .frame(maxHeight: .infinity, alignment: .bottom)
    .background(Color.cyBgSecondary)
}

#Preview("Top Bar — Banner") {
    DashboardTopBar(store: chromePreviewStore {
        $0.speed.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
    })
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.cyBgSecondary)
}

#Preview("Top Bar — Edit Mode") {
    DashboardTopBar(store: chromePreviewStore(isEditing: true) {
        $0.navigation.isOffRoute = true
    })
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.cyBgSecondary)
}

#Preview("Edit Controls") {
    DashboardEditControls(store: chromePreviewStore(isEditing: true))
        .background(Color.cyBgSecondary)
}

#Preview("Page Indicator") {
    DashboardPageIndicator(store: chromePreviewStore())
        .padding()
        .background(Color.cyBgSecondary)
}
