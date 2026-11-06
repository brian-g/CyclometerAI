import ComposableArchitecture
import SwiftUI

// MARK: - Map

/// S15's full-screen map (#538): the route, with pan and zoom. The live map sheet's shape
/// (`LiveMapSheet`): a bar only for the close every sheet carries and the map's options, with no
/// background, so the map runs to the sheet's top edge.
///
/// Its options (#537) are one menu, as Maps keeps its own: the basemap, the pass and stop layers,
/// and what the route is colored by, with a legend at the bottom for any coloring but Plain.
struct RideMapSheet: View {
    @Bindable var store: StoreOf<RideMapSheetFeature>

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Each field read here, from the store, so a change to any of them redraws the
                // map. Handing the map `store.state` whole hid the basemap and layer reads from
                // observation: the map changed only when something read here did.
                RideMapView(
                    segments: store.segments,
                    coloring: store.coloring,
                    coloredRuns: store.coloredRuns,
                    stops: store.showsStops ? store.stops : [],
                    passes: store.hasRadar && store.showsPasses ? store.passes : [],
                    unitSystem: store.unitSystem,
                    basemap: store.basemap
                )
                .ignoresSafeArea(edges: .bottom)
                if !store.legend.isEmpty {
                    RideMapLegend(coloring: store.coloring, unit: store.legendUnit, entries: store.legend)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.sm)
                }
            }
            .sheetCloseButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    RideMapOptionsMenu(store: store)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The map sheet's options (#537). A layer the ride has nothing for has no toggle, and a
/// coloring it has no data for isn't offered.
private struct RideMapOptionsMenu: View {
    @Bindable var store: StoreOf<RideMapSheetFeature>

    var body: some View {
        Menu {
            Picker("Map", selection: $store.basemap.sending(\.basemapSelected)) {
                ForEach(MapBasemap.allCases) { basemap in
                    Text(basemap.title).tag(basemap)
                }
            }
            .pickerStyle(.inline)
            if store.hasRadar || !store.stops.isEmpty {
                Section("Show") {
                    if store.hasRadar {
                        Toggle("Vehicle Passes", isOn: $store.showsPasses.sending(\.passesToggled))
                    }
                    if !store.stops.isEmpty {
                        Toggle("Stops", isOn: $store.showsStops.sending(\.stopsToggled))
                    }
                }
            }
            Picker("Color Route By", selection: $store.coloring.sending(\.coloringSelected)) {
                ForEach(store.availableColorings) { coloring in
                    Text(coloring.title).tag(coloring)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Map Options", systemImage: "square.3.layers.3d")
        }
    }
}

/// The route coloring's key (#537): each band's color over its range, low to high, with the
/// unit once beside the coloring's name. One element for VoiceOver, read low to high.
struct RideMapLegend: View {
    let coloring: RouteColoring
    let unit: String
    let entries: [RouteColorScale.LegendEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(coloring.title)
                    .heroLabel()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            HStack(spacing: Spacing.xs) {
                ForEach(entries, id: \.band) { entry in
                    VStack(spacing: Spacing.xs) {
                        Capsule()
                            .fill(coloring.color(band: entry.band))
                            .frame(height: Spacing.xs)
                        Text(entry.label)
                            .font(.caption2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Spacing.lg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route colored by \(coloring.title.lowercased())")
        .accessibilityValue(entries.map(\.spoken).joined(separator: ", "))
    }
}

// MARK: - Vehicle passes

/// S15's vehicle-pass sheet (#538): each pass's time and how fast the vehicle went by. Rows
/// aren't tappable.
struct RidePassesSheet: View {
    let store: StoreOf<RidePassesFeature>

    var body: some View {
        NavigationStack {
            List(Array(store.passes.enumerated()), id: \.offset) { _, pass in
                LabeledContent {
                    // No value when the radar never measured the vehicle's speed.
                    if let speed = pass.vehicleSpeed(store.unitSystem) {
                        Text(speed.shown).monospacedDigit()
                    }
                } label: {
                    Text(pass.timestamp, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(pass.timestamp, format: .dateTime.hour().minute().second()))
                .accessibilityValue(pass.vehicleSpeed(store.unitSystem)?.spoken ?? "")
            }
            .navigationTitle("Vehicle Passes")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton()
        }
        .presentationDetents([.medium, .large])
    }
}

extension VehiclePassEventDTO {
    /// How fast the vehicle went by, in the rider's units, whole numbers as the radar measures
    /// them. Nil when the radar never measured it.
    func vehicleSpeed(_ unit: UnitSystem) -> MetricReading? {
        guard let kph = estimatedPassSpeedKph else { return nil }
        let mps = kph / AlertLevel.kphPerMPS
        return MetricReading(value: unit.speed(fromMPS: mps).formatted(.number.precision(.fractionLength(0))),
                             unit: unit.speedLabel,
                             spoken: unit.spokenSpeed(fromMPS: mps, fractionLength: 0))
    }
}

// MARK: - Edit

/// S15's Edit sheet (#538): the ride's title and notes.
struct RideEditView: View {
    @Bindable var store: StoreOf<RideEditFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $store.title.sending(\.titleChanged))
                }
                Section("Notes") {
                    TextField("Notes", text: $store.notes.sending(\.notesChanged), axis: .vertical)
                        .lineLimit(4...)
                }
            }
            .navigationTitle("Edit Ride")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton { store.send(.closeTapped) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveTapped) }
                        .disabled(!store.canSave)
                }
            }
            .confirmationDialog($store.scope(state: \.discardDialog, action: \.discardDialog))
        }
        // Changes leave only by Save or by the close, which asks first.
        .interactiveDismissDisabled(store.hasChanges)
    }
}

// MARK: - Previews

private let previewPasses: [VehiclePassEventDTO] = [
    VehiclePassEventDTO(rideId: UUID(), timestamp: Date(timeIntervalSince1970: 1_750_000_060),
                        latitude: 37.3349, longitude: -122.0190, alertLevelAtPass: .caution,
                        riderSpeedKph: 25, estimatedPassSpeedKph: 58),
    VehiclePassEventDTO(rideId: UUID(), timestamp: Date(timeIntervalSince1970: 1_750_000_900),
                        latitude: 37.3400, longitude: -122.0100, alertLevelAtPass: .danger,
                        riderSpeedKph: 22, estimatedPassSpeedKph: 81),
    VehiclePassEventDTO(rideId: UUID(), timestamp: Date(timeIntervalSince1970: 1_750_001_400),
                        latitude: 37.3300, longitude: -122.0050, alertLevelAtPass: .clear,
                        riderSpeedKph: 27, estimatedPassSpeedKph: nil),
]

#Preview("Vehicle Passes — metric") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RidePassesSheet(store: Store(initialState: RidePassesFeature.State(passes: previewPasses, unitSystem: .metric)) {
            RidePassesFeature()
        })
    }
}

#Preview("Vehicle Passes — imperial, dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RidePassesSheet(store: Store(initialState: RidePassesFeature.State(passes: previewPasses, unitSystem: .imperial)) {
            RidePassesFeature()
        })
    }
    .preferredColorScheme(.dark)
}

#Preview("Edit Ride") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RideEditView(store: Store(initialState: RideEditFeature.State(title: "River Loop", notes: "Headwind on the way out.")) {
            RideEditFeature()
        })
    }
}

#Preview("Edit Ride — empty title") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RideEditView(store: Store(initialState: RideEditFeature.State(title: "", notes: "")) {
            RideEditFeature()
        })
    }
    .preferredColorScheme(.dark)
}

/// A 15-minute loop with every sensor, a climb, and one manual and one auto pause.
private let previewPoints: [TrackPointDTO] = (0..<900).map { second in
    let angle = Double(second) / 900 * 2 * .pi
    return TrackPointDTO(
        rideId: UUID(), timestamp: Date(timeIntervalSince1970: 1_750_000_000 + Double(second) + (second >= 300 ? 120 : 0) + (second >= 600 ? 45 : 0)),
        latitude: 37.3349 + 0.01 * sin(angle), longitude: -122.0090 + 0.01 * cos(angle),
        altitudeMeters: 40 + 30 * sin(angle * 2), horizontalAccuracyMeters: 5,
        speedMPS: 6 + 3 * sin(angle * 3), speedSource: .gps,
        heartRateBPM: 120 + Int(40 * sin(angle)), heartRateSource: .bleHR,
        cadenceRPM: 75 + Int(25 * sin(angle * 2)),
        segmentIndex: second < 300 ? 0 : second < 600 ? 1 : 2
    )
}

private func previewMapState(_ coloring: RouteColoring) -> RideMapSheetFeature.State {
    let track = RideMapTrack(points: previewPoints)
    var state = RideMapSheetFeature.State(
        segments: RideMapThumbnail.drawableSegments(previewPoints), track: track, passes: previewPasses,
        stops: RideStops.stops(pauses: [
            RidePause(startedAt: Date(timeIntervalSince1970: 1_750_000_300), endedAt: Date(timeIntervalSince1970: 1_750_000_420), isAuto: false),
            RidePause(startedAt: Date(timeIntervalSince1970: 1_750_000_720), endedAt: Date(timeIntervalSince1970: 1_750_000_765), isAuto: true),
        ], track: track),
        unitSystem: .imperial,
        heartRateZones: [60...123, 124...143, 144...162, 163...181, 182...200]
    )
    state.coloring = coloring
    state.recolor()
    return state
}

#Preview("Map") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RideMapSheet(store: Store(initialState: previewMapState(.plain)) {
            RideMapSheetFeature()
        })
    }
}

#Preview("Map — colored by speed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RideMapSheet(store: Store(initialState: previewMapState(.speed)) {
            RideMapSheetFeature()
        })
    }
}

#Preview("Legends") {
    VStack(spacing: Spacing.md) {
        ForEach([RouteColoring.speed, .grade, .cadence, .heartRate]) { coloring in
            let state = previewMapState(coloring)
            RideMapLegend(coloring: coloring, unit: state.legendUnit, entries: state.legend)
        }
    }
    .padding(Spacing.lg)
    .background(Color.cyBgTertiary)
}

#Preview("Legends — dark, metric") {
    VStack(spacing: Spacing.md) {
        ForEach([RouteColoring.speed, .grade, .cadence, .heartRate]) { coloring in
            let state = { var state = previewMapState(.plain); state.unitSystem = .metric; state.coloring = coloring; state.recolor(); return state }()
            RideMapLegend(coloring: coloring, unit: state.legendUnit, entries: state.legend)
        }
    }
    .padding(Spacing.lg)
    .background(Color.cyBgTertiary)
    .preferredColorScheme(.dark)
}
