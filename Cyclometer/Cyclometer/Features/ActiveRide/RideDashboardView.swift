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
    @State private var toolbarHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // S05 — Map widget safe-area bleed. The toolbar floats as an overlay
        // (not a safe-area inset) so the grid's map cell can extend behind it
        // all the way to the physical screen bottom.
        TabView(selection: $selectedPage) {
            gridPage
                .tag(Page.grid)

            // Page 2 — single full-bleed map (S05 "second page has a single map").
            ActiveRideMapView(coordinates: store.trackCoordinates)
                .ignoresSafeArea()
                .tag(Page.map)
        }
        .background(Color.cyBgSecondary)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) { grabber }
        .ignoresSafeArea(.all)
        .overlay(alignment: .bottom) {
            VStack(spacing: Spacing.xs) {
                pageIndicator
                rideControls
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                toolbarHeight = newValue
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: max(dragOffset, 0))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 120 { onClose() }
                }
        )
        .task { await store.send(.task).finish() }
        .alert($store.scope(state: \.finishAlert, action: \.finishAlert))
    }

    // ── Page 1 — Widget Grid (S05.4 factory default) ──────────────────────────
    // GeometryReader measures the area between the grabber and the screen
    // bottom (safe areas are ignored at the TabView level). The floating
    // toolbar overlays the bottom `toolbarHeight` pixels, so
    // `unit = (height - toolbarHeight) / 7` keeps the 5 widget rows above
    // the toolbar at the spec'd ≈201×96pt size, and the map row extends
    // `unit * 2 + toolbarHeight` to bleed behind the toolbar to the screen
    // bottom.
    // Rows 1-2: Speed (W1 2×2)
    // Row 3:    HR (W4 1×1) + HR Zones (W12 1×1)
    // Row 4:    Radar (W7 1×1) + Pace (W11 1×1)
    // Row 5:    Cadence (W5 1×1) + Weather (W10 1×1) [placeholder]
    // Rows 6-7: Map (W8 2×2) — bleeds behind the floating toolbar
    private var gridPage: some View {
        GeometryReader { geo in
            let unit = max(geo.size.height - toolbarHeight, 1) / 7
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                // W1 — Speed 2×2
                GridRow {
                    SpeedWidget(
                        speed: store.speed.speedMPS,
                        speedHistory: store.speed.speedHistory,
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
                    HeartRateWidget(bpm: store.heartRateBPM, zone: store.hrZone)
                        .frame(height: unit)
                    HRZonesWidget(zone: store.hrZone)
                        .frame(height: unit)
                }

                // W7 Radar + W11 Pace
                GridRow {
                    RadarWidget(
                        targets: store.radarTargets,
                        isRadarPaired: store.isRadarPaired
                    )
                    .frame(height: unit)
                    PaceWidget(speedKPH: store.speedKPH)
                        .frame(height: unit)
                }

                // W5 Cadence + W10 Weather placeholder
                GridRow {
                    CadenceWidget(cadence: store.cadence.cadenceRPM)
                        .frame(height: unit)
                    WeatherWidget()
                        .frame(height: unit)
                }

                // W8 — Map 2×2 (extends behind the floating toolbar)
                GridRow {
                    ActiveRideMapView(coordinates: store.trackCoordinates)
                        .gridCellColumns(2)
                        .frame(height: unit * 2 + toolbarHeight)
                }
            }
        }
    }

    // ── Grabber ───────────────────────────────────────────────────────────────
    private var grabber: some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: Spacing.xxl, height: Spacing.grabberHeight)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
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

    private func ringBell() {
        AudioServicesPlaySystemSound(1005) // 1005 = system "Tink"; route via AudioClient later
    }
}

// MARK: - Dashboard Widgets

/// W4 — Heart Rate 1×1
private struct HeartRateWidget: View {
    let bpm: Int
    let zone: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HEART RATE")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HeroNumber(bpm > 0 ? "\(bpm)" : "—", unit: "bpm").heroNumberSize(.medium)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ZONE")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HeroNumber(zone == 0 ? "—" : "Z\(zone)", unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
    }
}

/// W7 — Radar 1×1 (24pt column on right edge per S06 spec).
/// When no radar is paired (e.g. M3) the widget shows an em-dash stub,
/// matching the other unpaired metrics.
private struct RadarWidget: View {
    let targets: [RadarTarget]
    let isRadarPaired: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("RADAR")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if !isRadarPaired {
                    HeroNumber("—", unit: "").heroNumberSize(.medium)
                } else if targets.isEmpty {
                    Text("Clear")
                        .font(.headline)
                        .foregroundStyle(Color.cyRatingGood)
                }
                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 24pt radar column (S06) — only when paired
            if isRadarPaired {
                RadarColumnView(targets: targets)
                    .frame(width: Spacing.radarColumnWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.cyBgSecondary)
    }
}

/// W11 — Pace 1×1
private struct PaceWidget: View {
    let speedKPH: Double

    private var pace: String {
        guard speedKPH > 0 else { return "--:--" }
        let milesPerHour = speedKPH * 0.621371
        let secondsPerMile = 3600.0 / milesPerHour
        let minutes = Int(secondsPerMile) / 60
        let seconds = Int(secondsPerMile) % 60
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PACE")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HeroNumber(pace, unit: "/mi").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
    }
}

/// W5 — Cadence 1×1
private struct CadenceWidget: View {
    let cadence: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CADENCE")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let cadence {
                HeroNumber("\(cadence)", unit: "rpm").heroNumberSize(.medium)
            } else {
                HeroNumber("—", unit: "rpm").heroNumberSize(.medium)
            }
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
            Text("WEATHER")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
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
                ]
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
