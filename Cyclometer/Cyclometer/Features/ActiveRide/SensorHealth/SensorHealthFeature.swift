import ComposableArchitecture
import Foundation

/// Watches every paired sensor's battery and link for the length of a ride, so the ride can
/// end with a verdict on each (#391). `ActiveRideFeature` reads `log` at ride end.
///
/// Mid-ride it also holds each sensor's live status and battery, for the Sensors toolbar button
/// and sheet (#464, #466). Those stay quiet — a badge, never a sound or banner — so nothing here
/// competes with radar alerts.
@Reducer
struct SensorHealthFeature {
    @Dependency(\.date.now) var now
    @Dependency(\.bleClient) var bleClient
    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient

    @ObservableState
    struct State: Equatable {
        var log = SensorHealthLog()
        /// Whether the ride is recording, forwarded by `ActiveRideFeature` as it does for
        /// `CadenceFeature`. Link losses count only while it is: at a café stop the phone may
        /// sit at the edge of range, and a healthy sensor would time out there.
        var isRecording = false
        /// The roles whose sensor is up right now: `.active` (HR: notifying), the same bar the
        /// log counts as showing up.
        var connectedRoles: Set<SensorRole> = []
        /// Maps a role's battery reading, and a peripheral's link loss, to a paired device.
        @SharedReader(.appPreferences) var preferences

        /// Every paired device, in `SensorRole.allCases` order of its first role. A combo CSC
        /// sensor is one device with both roles: one battery, one radio.
        var devices: [Device] {
            var devices: [Device] = []
            for role in SensorHealthFeature.watchedRoles {
                guard let record = preferences.pairedSensor(for: role) else { continue }
                let isConnected = connectedRoles.contains(role)
                if let index = devices.firstIndex(where: { $0.id == record.peripheralID }) {
                    devices[index].roles.append(role)
                    devices[index].isConnected = devices[index].isConnected && isConnected
                } else {
                    devices.append(Device(id: record.peripheralID, roles: [role], name: record.displayName,
                                          isConnected: isConnected,
                                          batteryPercent: log.minBatteryPercent(peripheral: record.peripheralID)))
                }
            }
            return devices
        }

        /// The devices the toolbar's Sensors button counts: missing or low.
        var devicesNeedingAttention: [Device] { devices.filter(\.needsAttention) }
    }

    /// One paired device as the ride sees it now.
    struct Device: Equatable, Identifiable {
        /// The peripheral.
        let id: UUID
        var roles: [SensorRole]
        let name: String?
        /// Every one of its roles is up. A combo whose cadence side dropped is missing.
        var isConnected: Bool
        /// The lowest level it has reported this ride, the log's minimum; nil when none yet.
        ///
        /// Latched, not live: a sagging cell reads high between transmissions (BLE.md §14.5), so a
        /// live level would flick the Sensors button on and off as it rebounds across 20%.
        var batteryPercent: Int?

        var isMissing: Bool { !isConnected }

        /// At or below the level `SensorBatteryLabel` turns red at, at any point this ride. Counted
        /// only while connected: a missing device is missing, not also low.
        var isBatteryLow: Bool {
            guard isConnected, let batteryPercent else { return false }
            return batteryPercent <= SensorHealthReport.lowBatteryPercent
        }

        var needsAttention: Bool { isMissing || isBatteryLow }

        /// "Speed & Cadence" for a combo, as S10 lists one.
        var title: String { roles.map(\.displayName).joined(separator: " & ") }
    }

    /// The roles a client streams status and battery for. `.power` is Phase 3 hardware: a
    /// record for it would read missing forever.
    static let watchedRoles: [SensorRole] = [.radar, .heartRate, .speed, .cadence]

    enum Action: Equatable {
        case startListening
        case statusChanged(SensorRole, isConnected: Bool)
        case batteryReported(SensorRole, Int?)
        case linkTimedOut(UUID)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                // The same per-client battery and status streams the Start sheet reads; each
                // replays its current value on subscribe. Reaching `.active` (HR: notifying) is
                // what counts as the sensor showing up for the ride.
                return .merge(
                    .run { [variaRadarClient] send in
                        for await status in variaRadarClient.connectionState() {
                            await send(.statusChanged(.radar, isConnected: status == .active))
                        }
                    },
                    .run { [bleHRClient] send in
                        for await isPaired in bleHRClient.pairingStatus() {
                            await send(.statusChanged(.heartRate, isConnected: isPaired))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await status in bleCSCClient.connectionState(.speed) {
                            await send(.statusChanged(.speed, isConnected: status == .active))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await status in bleCSCClient.connectionState(.cadence) {
                            await send(.statusChanged(.cadence, isConnected: status == .active))
                        }
                    },
                    .run { [variaRadarClient] send in
                        for await level in variaRadarClient.batteryLevel() {
                            await send(.batteryReported(.radar, level))
                        }
                    },
                    .run { [bleHRClient] send in
                        for await level in bleHRClient.batteryLevel() {
                            await send(.batteryReported(.heartRate, level))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await level in bleCSCClient.batteryLevel(.speed) {
                            await send(.batteryReported(.speed, level))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await level in bleCSCClient.batteryLevel(.cadence) {
                            await send(.batteryReported(.cadence, level))
                        }
                    },
                    .run { [bleClient] send in
                        for await id in bleClient.linkTimeouts() {
                            await send(.linkTimedOut(id))
                        }
                    }
                )

            case .statusChanged(let role, let isConnected):
                guard isConnected else {
                    state.connectedRoles.remove(role)
                    return .none
                }
                state.connectedRoles.insert(role)
                guard let peripheral = state.preferences.pairedSensor(for: role)?.peripheralID else { return .none }
                state.log.recordConnected(peripheral: peripheral)
                return .none

            case .batteryReported(let role, let level):
                guard let peripheral = state.preferences.pairedSensor(for: role)?.peripheralID else { return .none }
                state.log.recordBattery(level, peripheral: peripheral)
                return .none

            case .linkTimedOut(let peripheral):
                // Only a sensor holding a role is the rider's concern; the shared central
                // also sees peripherals S11 merely discovered.
                guard state.isRecording,
                      state.preferences.pairedSensors.contains(where: { $0.peripheralID == peripheral }) else {
                    return .none
                }
                state.log.recordLinkLoss(peripheral: peripheral, at: now)
                return .none
            }
        }
    }
}
