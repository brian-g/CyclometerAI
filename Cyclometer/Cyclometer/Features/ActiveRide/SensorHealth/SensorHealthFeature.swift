import ComposableArchitecture
import Foundation

/// Watches every paired sensor's battery and link for the length of a ride, so the ride can
/// end with a verdict on each (#391). Records only: nothing here is shown mid-ride, where a
/// warning would compete with radar alerts. `ActiveRideFeature` reads `log` at ride end.
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
        /// Maps a role's battery reading, and a peripheral's link loss, to a paired device.
        @SharedReader(.appPreferences) var preferences
    }

    enum Action: Equatable {
        case startListening
        case batteryReported(SensorRole, Int?)
        case linkTimedOut(UUID)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                // The same per-client battery streams the Start sheet reads; each replays its
                // current level on subscribe.
                return .merge(
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

            case .batteryReported(let role, let level):
                guard let peripheral = state.preferences.pairedSensor(for: role)?.peripheralID else { return .none }
                state.log.recordBattery(level, peripheral: peripheral)
                return .none

            case .linkTimedOut(let peripheral):
                // Only a sensor holding a role is the rider's concern; the shared central
                // also sees peripherals S11 merely discovered.
                guard state.preferences.pairedSensors.contains(where: { $0.peripheralID == peripheral }) else {
                    return .none
                }
                state.log.recordLinkLoss(peripheral: peripheral, at: now)
                return .none
            }
        }
    }
}
