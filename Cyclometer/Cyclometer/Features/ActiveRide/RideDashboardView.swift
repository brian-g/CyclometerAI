import SwiftUI
import ComposableArchitecture
import AudioToolbox

/// Full-screen active ride dashboard — presented as fullScreenCover over the tab bar.
/// Matches prototype RideDashboardView with TCA store replacing local @State.
/// Dashboard uses the 2-col × 7-row widget grid (S05.4 factory default).
struct RideDashboardView: View {
    let store: StoreOf<ActiveRideFeature>
    let onClose: () -> Void
    let onFinish: () -> Void
    @State private var isConfirmingFinish = false
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Grabber ───────────────────────────────────────────────────────
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: Spacing.xxl, height: Spacing.grabberHeight)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            // ── Widget Grid (S05.4 factory default) ───────────────────────────
            // GeometryReader is intentional here: containerRelativeFrame measures
            // from the fullScreenCover container (full screen height), not from
            // this grid area (screen minus grabber and controls). GeometryReader
            // correctly captures only the height available to the grid.
            // Rows 1-2: Speed (W1 2×2)
            // Row 3:    HR (W4 1×1) + HR Zones (W12 1×1)
            // Row 4:    Radar (W7 1×1) + Pace (W11 1×1)
            // Row 5:    Cadence (W5 1×1) + Weather (W10 1×1) [placeholder]
            // Rows 6-7: Map (W8 2×2)
            GeometryReader { geo in
                let unit = geo.size.height / 7
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    // W1 — Speed 2×2
                    GridRow {
                        SpeedWidget(
                            speed: store.speedKPH,
                            distance: store.distanceKM,
                            elapsed: store.elapsedSeconds,
                            averageSpeed: store.averageSpeedKPH,
                            maxSpeed: store.maxSpeedKPH
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
                        CadenceWidget(cadence: store.cadenceRPM)
                            .frame(height: unit)
                        WeatherWidget()
                            .frame(height: unit)
                    }

                    // W8 — Map 2×2
                    GridRow {
                        MapWidget()
                            .gridCellColumns(2)
                            .frame(height: unit * 2)
                    }
                }
            }

            // ── Ride Controls ─────────────────────────────────────────────────
            HStack(spacing: Spacing.md) {
                if store.isPaused {
                    Button {
                        store.send(.resumeTapped)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Resume")

                    Button {
                        isConfirmingFinish = true
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Finish")
                } else {
                    Button {
                        store.send(.pauseTapped)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Pause")
                }

                Spacer()

                Button {
                    AudioServicesPlaySystemSound(1005)
                } label: {
                    Label("Bell", systemImage: "bell.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Ring Bell")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(.bar)
        }
        .padding(0)
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
        .alert("Finish Ride", isPresented: $isConfirmingFinish) {
            Button("Finish", role: .destructive) { onFinish() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Dashboard Widgets

/// W1 — Speed 2×2: hero speed + distance + elapsed + avg/max
struct SpeedWidget: View {
    let speed: Double
    let distance: Double
    let elapsed: Int
    let averageSpeed: Double
    let maxSpeed: Double

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HeroNumber(speed, unit: "mph")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                    HeroNumber(distance, unit: "mi") {
                        Text("Distance").font(.caption)
                    }
                    .heroNumberSize(.small)
                    HeroNumber(elapsed.formattedElapsed, unit: "") {
                        Text("Time").font(.caption)
                    }
                    .heroNumberSize(.small)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HeroNumber(averageSpeed, unit: "") {
                    Text("AVG").font(.caption)
                }
                .heroNumberSize(.small)
                .layout(.vertical)
                HeroNumber(maxSpeed, unit: "") {
                    Text("MAX").font(.caption)
                }
                .heroNumberSize(.small)
                .layout(.vertical)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.cyBgSecondary)
    }
}

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
            HeroNumber("\(bpm)", unit: "bpm").heroNumberSize(.medium)
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
            HeroNumber("Z\(zone == 0 ? "-" : "\(zone)")", unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
    }
}

/// W7 — Radar 1×1 (24pt column on right edge per S06 spec)
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
                    Text("–")
                        .dDINCondensed(size: 68, relativeTo: .largeTitle)
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
    let cadence: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CADENCE")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HeroNumber("\(cadence)", unit: "rpm").heroNumberSize(.medium)
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

/// W8 — Map 2×2 (placeholder; full MapKit implementation in M8)
private struct MapWidget: View {
    var body: some View {
        Rectangle()
            .fill(Color.cyBgTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(systemName: "map")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.cyTextTertiary)
            }
    }
}

// MARK: - Helpers

private extension Int {
    var formattedElapsed: String {
        let d = Duration.seconds(self)
        if self >= 3600 {
            return d.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1, fractionalSecondsLength: 0)))
        } else {
            return d.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 0)))
        }
    }
}

// MARK: - Previews

#Preview("Zone 4 — Radar Active") {
    RideDashboardView(
        store: Store(
            initialState: ActiveRideFeature.State(
                elapsedSeconds: 2340,
                speedKPH: 28.4,
                heartRateBPM: 155,
                hrZone: 4,
                cadenceRPM: 87,
                distanceKM: 12.3,
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
        onClose: { },
        onFinish: { }
    )
}

// Renders W1 at a representative grid height (≈unit×2 on a typical iPhone).
// Use this preview to catch layout regressions in HeroNumber's frameSize constraint.
#Preview("SpeedWidget — grid height") {
    SpeedWidget(
        speed: 28.4,
        distance: 12.3,
        elapsed: 2340,
        averageSpeed: 28.4,
        maxSpeed: 34.1
    )
    .frame(width: 393, height: 200)
}

#Preview("Paused") {
    RideDashboardView(
        store: Store(
            initialState: ActiveRideFeature.State(
                isPaused: true,
                elapsedSeconds: 1230,
                heartRateBPM: 130,
                hrZone: 3,
                cadenceRPM: 0,
                distanceKM: 7.6,
                maxSpeedKPH: 31.2
            )
        ) {
            ActiveRideFeature()
        },
        onClose: { },
        onFinish: { }
    )
}
