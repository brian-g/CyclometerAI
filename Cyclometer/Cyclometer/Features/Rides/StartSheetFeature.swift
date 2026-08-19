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

    /// Everything `.task` starts, so `.onDisappear` can end all of it in one place —
    /// the same shape `DeviceManagementFeature` uses for S11.
    private enum CancelID { case screen }

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// Live connection status and battery per category, fed by the client streams.
        /// Whether a category is paired at all — and what the sensor is called — comes
        /// from `preferences`, never from here.
        var sensors: [SensorRow] = SensorRow.Kind.allCases.map { SensorRow(kind: $0) }

        /// The rows the sheet shows: one per paired role, whatever its connection state.
        ///
        /// Keyed on the durable record rather than on live status, which is what makes a
        /// paired sensor the app is not connected to appear at all — out of range, or
        /// simply not reconnected yet.
        ///
        /// An unpaired category is absent rather than shown empty — pairing is S11's
        /// (#100), and this sheet runs no discovery it could offer to pair *from*.
        var pairedRows: [SensorRow] {
            sensors.compactMap { row in
                guard let record = preferences.pairedSensor(for: row.kind.role) else { return nil }
                var row = row
                // The name at pairing time, so a sensor that is out of range is still
                // named. No client can answer for one it isn't connected to.
                row.name = record.displayName
                return row
            }
        }
    }

    enum Action: Equatable {
        case task
        case onDisappear
        case radarStatusUpdated(VariaRadarClient.ConnectionState)
        case hrPairingUpdated(Bool)
        case speedStatusUpdated(BLECSCClient.ConnectionState)
        case cadenceStatusUpdated(BLECSCClient.ConnectionState)
        case batteryUpdated(SensorRow.Kind, Int?)
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
                // state on subscribe, so already-connected sensors show immediately.
                return .merge(
                    // Hold a pairing scan open for as long as the sheet is up.
                    //
                    // Without it this screen reports nothing worth reading: `startScanning`
                    // belongs to the active ride, and ride finish disconnects, so every
                    // paired sensor would sit at its last known state — in practice
                    // disconnected — until the rider had already pressed Start. The scan is
                    // refcounted and independent of the ride's (BLE.md §8), the clients
                    // connect only what the rider has paired (#97), and a connection made
                    // here survives the scan ending, so the ride begins with its sensors
                    // already up.
                    //
                    // Sequential inside one effect, and in the same order as
                    // `AppFeature.task`'s launch push, so the lifecycle is assertable as
                    // one interleaved call log.
                    .run { _ in
                        await bleCSCClient.beginPairingScan()
                        await variaRadarClient.beginPairingScan()
                        await bleHRClient.beginPairingScan()
                    },
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
                .cancellable(id: CancelID.screen)

            case .onDisappear:
                // Explicit rather than relying on effect cancellation: each client's scan
                // refcount has to be balanced deterministically, and an action is what a
                // TestStore can assert.
                return .merge(
                    .cancel(id: CancelID.screen),
                    .run { _ in
                        await bleCSCClient.endPairingScan()
                        await variaRadarClient.endPairingScan()
                        await bleHRClient.endPairingScan()
                    }
                )

            case .radarStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .radar)
                return .none

            case .hrPairingUpdated(let connected):
                // The HR client exposes a bool meaning "notifications enabled and BPM
                // flowing", not the pairing record — which is why the row's existence
                // comes from `preferences` and only its badge comes from here. It needs
                // no third state: with the scan open, "not connected" is "still looking".
                state.setStatus(connected ? .connected : .searching, for: .heartRate)
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

            case .cancelButtonTapped:
                return .run { _ in await dismiss() }

            case .startRideButtonTapped:
                return .send(.delegate(.startRide))

            case .delegate:
                return .none
            }
        }
    }

    // Map the shared client lifecycle onto the sheet's two-state badge (UX.md §S05.1).
    // This was two identical overloads until #98 gave the radar and CSC clients one
    // `SensorConnectionState` between them.
    //
    // Everything short of connected reads Searching, including `.disconnected`, and that
    // is true rather than charitable: the sheet holds a pairing scan open for as long as
    // it is up, so a paired sensor the client is not talking to is one it is actively
    // looking for. The rider setting up a ride is asking one question — is it up yet.
    private static func status(from state: SensorConnectionState) -> SensorRow.Status {
        switch state {
        case .connected, .active: .connected
        case .disconnected, .scanning, .connecting, .reconnecting: .searching
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

    /// Two states, not three. An unpaired category has no row at all — see
    /// `StartSheetFeature.State.pairedRows` — and everything short of connected is a
    /// sensor the sheet's own scan is still looking for.
    enum Status: Equatable {
        case connected, searching
    }

    var kind: Kind
    /// The sensor's name, filled in from its `PairedSensor` record. Nil only for a
    /// record written before the peripheral advertised one.
    var name: String? = nil
    var status: Status = .searching
    /// Battery percentage (0–100), or nil when the sensor is disconnected or doesn't
    /// expose the Battery Service. Rendered only when non-nil and connected.
    var batteryPercent: Int? = nil

    var id: Kind { kind }
}

extension SensorRow.Kind {
    /// The persisted role this category stands for. One-to-one: the sheet has no row
    /// for `.power`, which is Phase 3 hardware.
    var role: SensorRole {
        switch self {
        case .radar: .radar
        case .heartRate: .heartRate
        case .speed: .speed
        case .cadence: .cadence
        }
    }

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
        }
    }
}
