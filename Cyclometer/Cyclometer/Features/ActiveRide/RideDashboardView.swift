import SwiftUI
import ComposableArchitecture
import AudioToolbox

/// Full-screen active ride dashboard — presented as fullScreenCover over the tab bar.
/// Matches prototype RideDashboardView with TCA store replacing local @State.
/// Dashboard uses the 2-col × 7-row widget grid (S05.4 factory default).
struct RideDashboardView: View {
    /// Dashboard pages. Factory default is two; rider customisation (S07) will
    /// drive this from state. Raw value doubles as the paging-dot index.
    private enum Page: Int, CaseIterable {
        case grid, map
    }

    @Bindable var store: StoreOf<ActiveRideFeature>
    let onClose: () -> Void
    @GestureState private var dragOffset: CGFloat = 0
    @State private var selectedPage: Page = .grid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // S05 — Map widget safe-area bleed. The toolbar floats as an overlay
        // (not a safe-area inset) so the grid's map cell can extend behind it
        // all the way to the physical screen bottom.
        TabView(selection: $selectedPage) {
            gridPage
                .tag(Page.grid)

            // Page 2 — temporarily testing other configs
            secondPage
                .tag(Page.map)
        }
        .background(Color.cyBgSecondary)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.all)
        // Grabber floats as a top overlay (not a safe-area inset) so it does not
        // push page content down. Pages that must stay clear of the island (the
        // grid) reserve the space themselves; the map page bleeds up behind it.
        .overlay(alignment: .top) {
            VStack(spacing: Spacing.xs) {
                grabber()
                    .gesture(dismissDrag)
                if let banner = activeBanner {
                    RideBanner(text: banner.text, icon: banner.icon)
                        .transition(bannerTransition)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: max(dragOffset, 0))
        // Ride effects (timer/HR/radar/location) are started by AppFeature when
        // the ride begins and live for the whole ride, so they keep running when
        // this dashboard is minimized to the accessory strip. Do NOT start them
        // from a view `.task` here — that ties them to this view's lifetime.
        .alert($store.scope(state: \.finishAlert, action: \.finishAlert))
    }

    // ── Page 1 — Widget Grid (S05.4 factory default) ──────────────────────────
    // GeometryReader measures the full screen (safe areas are ignored at the
    // TabView level), so `unit = height / 7` sizes the 5 widget rows at the
    // spec'd ≈201×96pt. The floating toolbar is a bottom overlay (not a
    // safe-area inset), so the grid fills the full height and the map row
    // (`unit * 2`) bleeds behind the toolbar to the screen bottom.
    // Rows 1-2: Speed (W1 2×2)
    // Row 3:    HR (W4 1×1) + HR Zones (W12 1×1)
    // Row 4:    Pace (W11), full width — Radar (W7) is not a grid cell
    // Row 5:    Cadence (W5 1×1) + Weather (W10 1×1) [placeholder]
    // Rows 6-7: Map (W8 2×2) — bleeds behind the floating toolbar
    //
    // Radar (W7, S06) is a full-height lane beside the grid, not a grid row —
    // per PRD §8.2/UX.md §S06 it represents the road behind the rider and needs
    // the dashboard's full height to space vehicles readably, which no single
    // grid row can give it. `isRadarSidebarVisible` reserves its 24pt only once
    // radar has ever paired this ride; the grid gets the remaining width.
    private var gridPage: some View {
        GeometryReader { geo in
            let unit = max(geo.size.height, 1) / 7
            HStack(spacing: 0) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    // W1 — Speed 2×2
                    GridRow {
                        SpeedWidget(
                            speed: store.speed.speedMPS,
                            speedHistory: store.speed.watermarkSamples,
                            activeSpeedSource: store.speed.activeSpeedSource,
                            distance: store.distanceMeters,
                            elapsed: store.elapsedSeconds,
                            averageSpeed: store.averageSpeedMPS,
                            maxSpeed: store.maxSpeedMPS,
                            unit: store.unitSystem,
                            size: .twoByTwo
                        )
                        .gridCellColumns(2)
                        .frame(height: unit * 2)
                    }

                    // W4 HR + W12 HR Zones
                    GridRow {
                        HeartRateWidget(bpm: store.heartRateBPM, zone: store.hrZone, source: store.hrSource)
                            .frame(height: unit)
                        HRZonesWidget(zone: store.hrZone, source: store.hrSource)
                            .frame(height: unit)
                    }

                    // W11 Pace — full width; radar sidebar lives outside the grid
                    GridRow {
                        PaceWidget(speedMPS: store.speed.speedMPS ?? 0, unit: store.unitSystem)
                            .gridCellColumns(2)
                            .frame(height: unit)
                    }

                    // W5 Cadence + W10 Weather placeholder
                    GridRow {
                        CadenceWidget(
                            cadence: store.cadence.cadenceRPM,
                            cadenceHistory: store.cadence.watermarkSamples,
                            averageCadence: store.cadence.averageCadenceRPM,
                            maxCadence: store.cadence.maxCadenceRPM,
                            size: .oneByOne
                        )
                        .frame(height: unit)
                        WeatherWidget()
                            .frame(height: unit)
                    }

                    // W8 — Map 2×2 (extends behind the floating toolbar)
                    GridRow {
                        MapWidget(coordinates: store.trackCoordinates)
                        .gridCellColumns(2)
                        .frame(height: unit * 2)
                    }
                }
                .frame(maxWidth: .infinity)

                // W7 — Radar full-height sidebar (S06), beside the grid, not in it.
                //
                // `RadarColumnView`'s body is a `GeometryReader`, which has no
                // intrinsic height of its own — sitting next to the `Grid` (whose
                // rows pin it to a fixed, already-full height) in this `HStack`,
                // it collapses toward a tiny cross-axis size unless told to be
                // greedy. `.frame(maxHeight: .infinity)` makes it claim the same
                // full height the `Grid` gets, all the way to the physical top and
                // bottom edges (the outer `GeometryReader` already measures the
                // full screen — see the comment at the top of `gridPage`).
                if store.isRadarSidebarVisible {
                    RadarColumnView(targets: store.radarTargets, isOffline: store.isRadarOffline)
                        .frame(width: Spacing.radarColumnWidth)
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }
        }
    }

    // ── Page 2 — Static page to test other configurations
    
    private var secondPage: some View {
        GeometryReader { geo in
            let unit = max(geo.size.height, 1) / 7
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                // W1 — Speed 2×2
                GridRow {
                    MapWidget(coordinates: store.trackCoordinates)
                        .gridCellColumns(2)
                        .frame(height: unit * 2)
                }
                GridRow {
                    CadenceWidget(
                        cadence: store.cadence.cadenceRPM,
                        cadenceHistory: store.cadence.watermarkSamples,
                        averageCadence: store.cadence.averageCadenceRPM,
                        maxCadence: store.cadence.maxCadenceRPM,
                        size: .twoByOne)
                }
            }
        }
    }

    // ── Grabber ───────────────────────────────────────────────────────────────
    // Floats as a top overlay on a view that ignores safe areas, so the capsule
    // sits flush against the physical top edge (behind the dynamic island).
    private func grabber() -> some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: Spacing.xxl, height: Spacing.grabberHeight)
            // Expand the hit area beyond the thin capsule so the whole strip is
            // draggable; the paging TabView underneath never sees these drags.
            // Pin the capsule to the top so the enlarged frame grows downward
            // and doesn't push the visible grabber lower.
            .frame(maxWidth: .infinity, minHeight: Spacing.sm, alignment: .top)
            .contentShape(Rectangle())
            .padding(.bottom, Spacing.xs)
    }

    /// Pull-down-to-dismiss. Attached to the grabber (not the container) so it
    /// wins over the paging TabView's internal gesture recognizer.
    private var dismissDrag: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 { onClose() }
            }
    }

    // ── Paging indicator — always visible; factory default shows 2 dots ────────
    private var pageIndicator: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Page.allCases, id: \.self) { page in
                Circle()
                    .fill(page == selectedPage ? Color.cyPrimary : Color.cyTextTertiary)
                    .frame(width: Spacing.pageIndicatorDot, height: Spacing.pageIndicatorDot)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(selectedPage.rawValue + 1) of \(Page.allCases.count)")
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

            rideControlButton("Ring Bell", systemImage: "bell.fill", action: ringBell)
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
        Button(action: action) {
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

    /// The banner slot holds exactly one notice. Two sources can be armed at once —
    /// a speed-source switch and a wheel auto-calibration — so they are resolved to a
    /// single value here rather than each rendering its own capsule and stacking.
    /// Source switching wins: it changes what the rider is currently reading.
    private var activeBanner: (text: String, icon: String)? {
        if let text = store.speed.sourceSwitchBanner { return (text, "shuffle") }
        if let text = store.calibration.banner { return (text, "ruler") }
        return nil
    }

    private func ringBell() {
        AudioServicesPlaySystemSound(1005) // 1005 = system "Tink"; route via AudioClient later
    }
}

// MARK: - Dashboard Widgets

/// Shared empty state for W4/W12 when neither BLE nor HealthKit has a reading (#161).
private struct NoHRSourceLabel: View {
    var body: some View {
        Text("No HR Source")
            .font(.cyCaption)
            .foregroundStyle(.cyTextTertiary)
    }
}

/// W4 — Heart Rate 1×1
private struct HeartRateWidget: View {
    let bpm: Int
    let zone: Int
    let source: HRSource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Heart Rate")
            if source == .none {
                NoHRSourceLabel()
            } else {
                HeroNumber(bpm > 0 ? "\(bpm)" : "—", unit: "bpm").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.hrZone(zone))
                .frame(width: Spacing.hrBorderWidth)
        }
    }
}

/// W12 — HR Zones 1×1
private struct HRZonesWidget: View {
    let zone: Int
    let source: HRSource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Zone")
            if source == .none {
                NoHRSourceLabel()
            } else {
                HeroNumber(zone == 0 ? "—" : "Z\(zone)", unit: "").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
    }
}

/// W11 — Pace 1×1
struct PaceWidget: View {
    let speedMPS: Double
    let unit: UnitSystem

    private var pace: String {
        guard let paceSeconds = unit.paceSeconds(fromMPS: speedMPS) else { return "--:--" }
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Pace")
            HeroNumber(pace, unit: unit.paceLabel).heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
    }
}

/// W10 — Weather 1×1 (placeholder)
private struct WeatherWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Weather")
            HeroNumber("77°", unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
    }
}

// MARK: - Previews

#Preview("Zone 4 — Radar Active") {
    RideDashboardView(
        store: Store(
            initialState: ActiveRideFeature.State(
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
                speedSampleSum: 3408,
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
        },
        onClose: { }
    )
}

#Preview("No Radar") {
    RideDashboardView(
        store: Store(
            initialState: ActiveRideFeature.State(
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
                speedSampleSum: 3408,
                isRadarPaired: false,
                wasRadarEverPaired: false
            )
        ) {
            ActiveRideFeature()
        },
        onClose: { }
    )
}

#Preview("Paused") {
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
                maxSpeedKPH: 31.2
            )
        ) {
            ActiveRideFeature()
        },
        onClose: { }
    )
}
