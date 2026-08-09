import ComposableArchitecture
import Foundation

/// S11 (subset) — Device Management. Scans for CSC sensors, lists what was found,
/// and pairs or unpairs one at a time.
///
/// Scope is deliberately narrow (#68): CSC only, no persistence, no sorting beyond
/// paired-first, no per-row status detail. M10 extends this screen with radar / HR
/// sections and richer status rather than replacing it, so the list is built from a
/// device stream that can carry other sensor types later.
///
/// Pairing does not survive an app restart — `PairedSensor` persistence and the
/// Speed / Cadence / Both role sheet land in #67.
@Reducer
struct DeviceManagementFeature {

    @Dependency(\.bleCSCClient) var bleCSCClient

    @ObservableState
    struct State: Equatable {
        var devices: [BLECSCClient.DiscoveredSensor] = []

        var pairedDevices: [BLECSCClient.DiscoveredSensor] { devices.filter(\.isPaired) }
        var availableDevices: [BLECSCClient.DiscoveredSensor] { devices.filter { !$0.isPaired } }
    }

    enum Action: Equatable {
        case task
        case onDisappear
        case devicesUpdated([BLECSCClient.DiscoveredSensor])
        case pairButtonTapped(UUID)
        case unpairButtonTapped(UUID)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .run { _ in await bleCSCClient.beginPairingScan() },
                    .run { send in
                        for await devices in bleCSCClient.discoveredSensors() {
                            await send(.devicesUpdated(devices))
                        }
                    }
                )

            case .onDisappear:
                // Explicit rather than relying on effect cancellation: the client's
                // scan refcount has to be balanced deterministically, and an action
                // is what a TestStore can assert.
                return .run { _ in await bleCSCClient.endPairingScan() }

            case .devicesUpdated(let devices):
                state.devices = devices
                return .none

            case .pairButtonTapped(let id):
                return .run { _ in await bleCSCClient.pair(id) }

            case .unpairButtonTapped(let id):
                return .run { _ in await bleCSCClient.unpair(id) }
            }
        }
    }
}
