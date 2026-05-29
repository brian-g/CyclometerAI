import SwiftUI
import ComposableArchitecture

struct RideMetricsView: View {
    let store: StoreOf<RideMetricsFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()

            // ── Root layout: metrics content + 24pt radar column ────────────
            // The radar column is part of the layout — it takes real horizontal
            // space from the widget grid. It collapses to zero width (not hidden
            // with opacity) when no Varia device is paired.
            HStack(spacing: 0) {

                // ── Left: all ride metrics ───────────────────────────────────
                VStack(spacing: 0) {
                    Spacer()

                    // Hero speed
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", store.speedKPH))
                            .font(.cyHeroSpeed)
                            .foregroundStyle(Color.cyTextPrimary)
                            .monospacedDigit()

                        Text("km/h")
                            .font(.cyLabel)
                            .foregroundStyle(Color.cyTextSecondary)
                            .textCase(.uppercase)
                            .tracking(2)
                    }
                    .padding(.bottom, 32)

                    // Secondary metrics grid (2 columns)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        MetricTileView(
                            label: "Heart Rate",
                            value: "\(store.heartRateBPM)",
                            unit: "bpm",
                            borderColor: Color.hrZone(store.hrZone)
                        )
                        MetricTileView(label: "Cadence",  value: "\(store.cadenceRPM)",                      unit: "rpm")
                        MetricTileView(label: "Distance", value: String(format: "%.2f", store.distanceKM),   unit: "km")
                        MetricTileView(label: "Time",     value: store.elapsedSeconds.formattedElapsed,      unit: "")
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    // Controls
                    HStack(spacing: 20) {
                        if !store.isRiding {
                            CYButton(label: "Start", style: .primary) {
                                store.send(.startRideTapped)
                            }
                        } else if store.isPaused {
                            CYButton(label: "Resume", style: .primary)      { store.send(.resumeRideTapped) }
                            CYButton(label: "Stop",   style: .destructive)  { store.send(.stopRideTapped) }
                        } else {
                            CYButton(label: "Pause",  style: .secondary)    { store.send(.pauseRideTapped) }
                            CYButton(label: "Stop",   style: .destructive)  { store.send(.stopRideTapped) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                }

                // ── Right: 24pt radar column (S06 spec) ──────────────────────
                // Vehicles positioned top (closest/critical) → bottom (furthest).
                // Zero-width when unpaired — takes no space, causes no reflow.
                if store.isRadarPaired {
                    RadarColumnView(targets: store.radarTargets)
                        .frame(width: 24)
                }
            }
        }
        .onAppear   { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
    }
}

// MARK: - Button Component (local stub; move to Components/ if reused widely)

private struct CYButton: View {
    enum Style { case primary, secondary, destructive }
    let label: String
    let style: Style
    let action: () -> Void

    var bgColor: Color {
        switch style {
        case .primary:     return .cyPrimary
        case .secondary:   return .cyBgSecondary
        case .destructive: return .cyDestructive
        }
    }

    var fgColor: Color {
        style == .secondary ? .cyTextPrimary : .cyTextOnPrimary
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fgColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Helpers

private extension Int {
    var formattedElapsed: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
