import ComposableArchitecture
import Foundation
import SwiftUI

/// S05.1 — Start Ride sheet. Global (app-level) setup screen: ride-setup stubs plus a live
/// Sensors group. Presented by `AppFeature` via `@Presents`; the "Start Ride" CTA bubbles up
/// as `.delegate(.startRide)` for the parent to begin the ride.
@Reducer
struct StartSheetFeature {

    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.dismiss) var dismiss

    @ObservableState
    struct State: Equatable {
        var sensors: [SensorRow] = SensorRow.Kind.allCases.map { SensorRow(kind: $0) }
    }

    enum Action: Equatable {
        case task
        case radarStatusUpdated(VariaRadarClient.ConnectionState)
        case hrPairingUpdated(Bool)
        case speedStatusUpdated(BLECSCClient.ConnectionState)
        case cadenceStatusUpdated(BLECSCClient.ConnectionState)
        case batteryUpdated(SensorRow.Kind, Int?)
        case pairButtonTapped(SensorRow.Kind)
        case cancelButtonTapped
        case startRideButtonTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case startRide
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                // Reflect live connection status from each client. Streams replay current
                // state on subscribe, so already-connected sensors show immediately. This
                // sheet does not own the scan/connect lifecycle (a future pairing feature).
                return .merge(
                    .run { send in
                        for await status in variaRadarClient.connectionState() {
                            await send(.radarStatusUpdated(status))
                        }
                    },
                    .run { send in
                        for await paired in bleHRClient.pairingStatus() {
                            await send(.hrPairingUpdated(paired))
                        }
                    },
                    .run { send in
                        for await status in bleCSCClient.connectionState(.speed) {
                            await send(.speedStatusUpdated(status))
                        }
                    },
                    .run { send in
                        for await status in bleCSCClient.connectionState(.cadence) {
                            await send(.cadenceStatusUpdated(status))
                        }
                    },
                    // Battery is a separate stream per sensor rather than part of the
                    // status ones: it is read once per connection and arrives well
                    // after the status transition that preceded it.
                    .run { send in
                        for await level in variaRadarClient.batteryLevel() {
                            await send(.batteryUpdated(.radar, level))
                        }
                    },
                    .run { send in
                        for await level in bleHRClient.batteryLevel() {
                            await send(.batteryUpdated(.heartRate, level))
                        }
                    },
                    .run { send in
                        for await level in bleCSCClient.batteryLevel(.speed) {
                            await send(.batteryUpdated(.speed, level))
                        }
                    },
                    .run { send in
                        for await level in bleCSCClient.batteryLevel(.cadence) {
                            await send(.batteryUpdated(.cadence, level))
                        }
                    }
                )

            case .radarStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .radar)
                return .none

            case .hrPairingUpdated(let paired):
                // HR client exposes only a paired bool — no "searching" signal.
                state.setStatus(paired ? .connected : .notPaired, for: .heartRate)
                return .none

            case .speedStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .speed)
                return .none

            case .cadenceStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .cadence)
                return .none

            case .batteryUpdated(let kind, let percent):
                state.setBattery(percent, for: kind)
                return .none

            case .pairButtonTapped:
                // A discovered-but-unpaired sensor offers a "Tap to Pair" action. The pairing
                // flow itself is a future feature; this is the hook for it.
                return .none

            case .cancelButtonTapped:
                return .run { _ in await dismiss() }

            case .startRideButtonTapped:
                return .send(.delegate(.startRide))

            case .delegate:
                return .none
            }
        }
    }

    // The two client `ConnectionState` enums are identical in shape but distinct types;
    // map each to the sheet's three-state badge model.
    private static func status(from state: VariaRadarClient.ConnectionState) -> SensorRow.Status {
        switch state {
        case .disconnected: .notPaired
        case .scanning, .connecting, .reconnecting: .searching
        case .connected, .active: .connected
        }
    }

    private static func status(from state: BLECSCClient.ConnectionState) -> SensorRow.Status {
        switch state {
        case .disconnected: .notPaired
        case .scanning, .connecting, .reconnecting: .searching
        case .connected, .active: .connected
        }
    }
}

extension StartSheetFeature.State {
    mutating func setStatus(_ status: SensorRow.Status, for kind: SensorRow.Kind) {
        guard let index = sensors.firstIndex(where: { $0.kind == kind }) else { return }
        sensors[index].status = status
    }

    mutating func setBattery(_ percent: Int?, for kind: SensorRow.Kind) {
        guard let index = sensors.firstIndex(where: { $0.kind == kind }) else { return }
        sensors[index].batteryPercent = percent
    }
}

/// A single sensor row in the Start sheet's Sensors group.
struct SensorRow: Equatable, Identifiable {
    enum Kind: CaseIterable {
        case radar, heartRate, speed, cadence
    }

    enum Status: Equatable {
        case connected, searching, notPaired
    }

    var kind: Kind
    /// Connected device name, when known. `nil` renders as "Not Paired".
    /// No BLE client exposes a device name yet, so this is always `nil` for now.
    var name: String? = nil
    var status: Status = .notPaired
    /// Battery percentage (0–100), or nil when the sensor is disconnected or doesn't
    /// expose the Battery Service. Rendered only when non-nil and connected.
    var batteryPercent: Int? = nil

    var id: Kind { kind }
}

extension SensorRow.Kind {
    var displayName: String {
        switch self {
        case .radar: "Radar"
        case .heartRate: "Heart Rate"
        case .speed: "Speed"
        case .cadence: "Cadence"
        }
    }

    var systemImage: String {
        switch self {
        case .radar: "dot.radiowaves.forward"
        case .heartRate: "heart.fill"
        case .speed: "speedometer"
        case .cadence: "dial.medium.fill"
        }
    }

    var tint: Color {
        switch self {
        case .radar: .purple
        case .heartRate: .red
        case .speed: .blue
        case .cadence: .green
        }
    }
}

extension SensorRow.Status {
    /// Badge text + colors, mirroring the app's capsule-badge idiom (`SpeedWidgetView.sourceBadge`).
    var badge: (label: String, foreground: Color, background: Color) {
        switch self {
        case .connected: ("Connected", .cyTextOnPrimary, .cyPrimary)
        case .searching: ("Searching", .cyTextTertiary, .cyBgTertiary)
        case .notPaired: ("Not Paired", .cyTextTertiary, .cyBgTertiary)
        }
    }
}
