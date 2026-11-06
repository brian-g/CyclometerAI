import ComposableArchitecture
import SwiftUI

// MARK: - Map

/// S15's full-screen map (#538): the route, with pan and zoom, and a marker at each vehicle
/// pass. The live map sheet's shape (`LiveMapSheet`): a bar only for the close every sheet
/// carries, with no background, so the map runs to the sheet's top edge.
struct RideMapSheet: View {
    let store: StoreOf<RideMapSheetFeature>

    var body: some View {
        NavigationStack {
            RideMapView(segments: store.segments, passes: store.passes, unitSystem: store.unitSystem)
                .ignoresSafeArea(edges: .bottom)
                .sheetCloseButton()
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
            .sheetCloseButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveTapped) }
                        .disabled(!store.canSave)
                }
            }
        }
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

#Preview("Map") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RideMapSheet(store: Store(initialState: RideMapSheetFeature.State(
            segments: [(0..<60).map { step in
                let angle = Double(step) / 60 * 2 * .pi
                return RouteCoordinate(latitude: 37.3349 + 0.01 * sin(angle), longitude: -122.0090 + 0.01 * cos(angle))
            }],
            passes: previewPasses, unitSystem: .metric
        )) {
            RideMapSheetFeature()
        })
    }
}
