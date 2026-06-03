import SwiftUI

private enum NewRideDestination: Hashable {
    case routePicker
}

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
                    NavigationLink(value: NewRideDestination.routePicker) {
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
            .navigationDestination(for: NewRideDestination.self) { _ in
                RoutePickerView(routes: routes, selectedRouteName: $selectedRouteName)
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
        HStack(spacing: Spacing.md) {
            Image(systemName: sensor.systemImage)
                .font(.headline)
                .foregroundStyle(sensor.tint)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(sensor.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: Spacing.cornerMd))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(sensor.name).font(.headline)
                Text(sensor.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(sensor.status)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, Spacing.xs)
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
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(route.name).foregroundStyle(.primary)
                        Text(route.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if route.name == selectedRouteName {
                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
