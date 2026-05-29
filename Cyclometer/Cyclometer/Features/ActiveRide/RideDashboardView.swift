import SwiftUI
import ComposableArchitecture
import AudioToolbox
import Charts

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
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // ── Widget Grid (S05.4 factory default) ───────────────────────────
            // Rows 1-2: Speed (W1 2×2)
            // Row 3:    HR (W4 1×1) + HR Zones (W12 1×1)
            // Row 4:    Radar (W7 1×1) + Pace (W11 1×1)
            // Row 5:    Cadence (W5 1×1) + Weather (W10 1×1) [placeholder]
            // Rows 6-7: Map (W8 2×2)
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
                    .gridCellUnsizedAxes(.vertical)
                }
                Divider()

                // W4 HR + W12 HR Zones
                GridRow {
                    HeartRateWidget(bpm: store.heartRateBPM, zone: store.hrZone)
                        .gridCellUnsizedAxes(.vertical)
                    HRZonesWidget(zone: store.hrZone)
                        .gridCellUnsizedAxes(.vertical)
                }
                Divider()

                // W7 Radar + W11 Pace
                GridRow {
                    RadarWidget(
                        targets: store.radarTargets,
                        isRadarPaired: store.isRadarPaired
                    )
                    .gridCellUnsizedAxes(.vertical)
                    PaceWidget(speedKPH: store.speedKPH)
                        .gridCellUnsizedAxes(.vertical)
                }
                Divider()

                // W5 Cadence + W10 Weather placeholder
                GridRow {
                    CadenceWidget(cadence: store.cadenceRPM)
                        .gridCellUnsizedAxes(.vertical)
                    WeatherWidget()
                        .gridCellUnsizedAxes(.vertical)
                }
                Divider()

                // W8 — Map 2×2
                GridRow {
                    MapWidget()
                        .gridCellColumns(2)
                        .gridCellUnsizedAxes(.vertical)
                }
            }
            .gridCellUnsizedAxes(.vertical)

            Spacer(minLength: 0)

            // ── Ride Controls ─────────────────────────────────────────────────
            HStack(spacing: 12) {
                if store.isPaused {
                    Button {
                        store.send(.resumeTapped)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Resume")

                    Button {
                        isConfirmingFinish = true
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
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
                            .frame(width: 52, height: 52)
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
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Ring Bell")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
private struct SpeedWidget: View {
    let speed: Double
    let distance: Double
    let elapsed: Int
    let averageSpeed: Double
    let maxSpeed: Double

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HeroNumber(String(format: "%.1f", speed), unit: "mph")
                Spacer()
                HStack(spacing: 16) {
                    HeroNumber(String(format: "%.1f", distance), unit: "mi") {
                        Text("DIST").font(.caption)
                    }
                    .heroNumberSize(.small)
                    HeroNumber(elapsed.formattedElapsed, unit: "") {
                        Text("TIME").font(.caption)
                    }
                    .heroNumberSize(.small)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HeroNumber(String(format: "%.1f", averageSpeed), unit: "") {
                    Text("AVG").font(.caption)
                }
                .heroNumberSize(.small)
                .layout(.vertical)
                HeroNumber(String(format: "%.1f", maxSpeed), unit: "") {
                    Text("MAX").font(.caption)
                }
                .heroNumberSize(.small)
                .layout(.vertical)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104)
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
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color.hrZone(zone))
                .frame(width: 3),
            alignment: .leading
        )
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
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
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
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 24pt radar column (S06) — only when paired
            if isRadarPaired {
                RadarColumnView(targets: targets)
                    .frame(width: 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104)
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
        return String(format: "%d:%02d", minutes, seconds)
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
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
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
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
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
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.cyBgSecondary)
    }
}

/// W8 — Map 2×2 (placeholder; full MapKit implementation in M8)
private struct MapWidget: View {
    var body: some View {
        Rectangle()
            .fill(Color.cyBgTertiary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 195)
            .overlay(
                Image(systemName: "map")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.cyTextTertiary)
            )
    }
}

// MARK: - Active Ride Accessory (tabViewBottomAccessory mini-player)

struct ActiveRideAccessoryView: View {
    let distanceKM: Double
    let speedKPH: Double
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var distanceMi: Double { distanceKM * 0.621371 }
    private var speedMPH: Double { speedKPH * 0.621371 }

    var body: some View {
        HStack(spacing: 4) {
            OpenRingProgressView(progress: 0.42, percentage: 42)
                .frame(width: 42, height: 42)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HeroNumber(String(format: "%.1f", distanceMi), unit: "mi")
                    .heroNumberSize(.small)
                HeroNumber(String(format: "%.1f", speedMPH), unit: "mph")
                    .heroNumberSize(.small)
            }
            Spacer()

            Button("Open", action: onOpen)
                .buttonStyle(.borderedProminent)
        }
        .padding(0)
    }
}

private struct OpenRingProgressView: View {
    private struct Segment: Identifiable {
        let id: String; let value: Double; let color: Color
    }
    let progress: Double
    let percentage: Int

    private var segments: [Segment] {
        let arc = 0.84
        return [
            Segment(id: "complete",  value: max(progress * arc, 0.001),         color: .accentColor),
            Segment(id: "remaining", value: max((1 - progress) * arc, 0.001),   color: .secondary.opacity(0.22)),
            Segment(id: "gap",       value: 1 - arc,                            color: .clear)
        ]
    }

    var body: some View {
        ZStack {
            Chart(segments) { s in
                SectorMark(angle: .value("", s.value), innerRadius: .ratio(0.68),
                           outerRadius: .ratio(1), angularInset: s.id == "gap" ? 0 : 1)
                .cornerRadius(3)
                .foregroundStyle(s.color)
            }
            .chartLegend(.hidden)
            .rotationEffect(.degrees(90))

            Text("\(percentage)%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - New Ride Sheet

struct NewRideView: View {
    let onCancel: () -> Void
    let onStartRide: () -> Void
    @State private var selectedRouteName = "Open Ride"
    private let routes = RouteStub.availableRoutes
    private let sensors = SensorStub.newRideDemoSensors

    var body: some View {
        NavigationStack {
            List {
                Section("Ride Setup") {
                    LabeledContent("Bike") { Text(NewRideDemoData.bikeName) }
                    NavigationLink {
                        RoutePickerView(routes: routes, selectedRouteName: $selectedRouteName)
                    } label: {
                        LabeledContent("Route") {
                            Text(selectedRouteName).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Recording") { Text(NewRideDemoData.recordingSummary) }
                }
                Section("Sensors") {
                    ForEach(sensors) { sensor in SensorStatusRow(sensor: sensor) }
                }
            }
            .navigationTitle("New Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Ride", action: onStartRide)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct SensorStatusRow: View {
    let sensor: SensorStub

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sensor.systemImage)
                .font(.headline)
                .foregroundStyle(sensor.tint)
                .frame(width: 36, height: 36)
                .background(sensor.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(sensor.name).font(.headline)
                Text(sensor.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(sensor.status)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct RoutePickerView: View {
    let routes: [RouteStub]
    @Binding var selectedRouteName: String

    var body: some View {
        List(routes) { route in
            Button {
                selectedRouteName = route.name
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name).foregroundStyle(.primary)
                        Text(route.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if route.name == selectedRouteName {
                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - HeroNumber Component

enum HeroUnitAlignment: Hashable { case vertical, horizontal }
enum HeroSize: Hashable { case small, medium, large }

struct HeroNumber<Label: View>: View {
    let value: String
    let unit: String
    var size: HeroSize = .large
    var alignment: HeroUnitAlignment = .horizontal
    let label: Label

    init(_ value: String, unit: String) where Label == EmptyView {
        self.value = value; self.unit = unit; self.label = EmptyView()
    }

    init(_ value: String, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value; self.unit = unit; self.label = label()
    }

    func heroNumberSize(_ size: HeroSize) -> Self {
        var copy = self; copy.size = size; return copy
    }

    func layout(_ alignment: HeroUnitAlignment) -> Self {
        var copy = self; copy.alignment = alignment; return copy
    }

    private var ptSize: CGFloat {
        switch size {
        case .small:  return 34
        case .medium: return 68
        case .large:  return 136
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            label
            if alignment == .vertical {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle)
                    Text(unit).font(.footnote)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle)
                    if !unit.isEmpty { Text(unit).font(.footnote) }
                }
            }
        }
    }
}

// MARK: - Helpers

private extension Int {
    var formattedElapsed: String {
        let h = self / 3600; let m = (self % 3600) / 60; let s = self % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
