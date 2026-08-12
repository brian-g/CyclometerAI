import ComposableArchitecture
import Foundation

/// S11 (subset) — Device Management. Scans for CSC sensors, lists what was found,
/// and pairs, unpairs or reassigns one at a time.
///
/// Scope is deliberately narrow (#68): CSC only, no sorting beyond paired-first, no
/// per-row status detail. M10 extends this screen with radar / HR sections and richer
/// status rather than replacing it, so the list is built from a device stream that can
/// carry other sensor types later.
///
/// Pairings are durable (#67): this feature owns the `PairedSensor` records and pushes
/// them into `BLECSCClient`, which holds no persistence and connects only what it has
/// been told about.
@Reducer
struct DeviceManagementFeature {

    @Dependency(\.bleCSCClient) var bleCSCClient

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// Live discovery, mirrored from the client. Membership here means "seen this
        /// scan session", not "paired" — that is `preferences.pairedSensors`.
        var devices: [BLECSCClient.DiscoveredSensor] = []
        @Presents var roleDialog: ConfirmationDialogState<Action.RoleChoice>?
        /// The peripheral currently being interrogated for capabilities after a Pair
        /// tap. Non-nil means a pairing is mid-flight, which is what makes a cancelled
        /// prompt release the sensor rather than leave it connected holding no role.
        var pendingPairing: UUID? = nil

        /// Built from the persisted records, not from `DiscoveredSensor.isPaired`: a
        /// paired sensor that is out of range holds no roles in the client, and would
        /// otherwise drop into Available with a Pair button.
        var pairedDevices: [BLECSCClient.DiscoveredSensor] {
            preferences.sensorAssignments
                .map { id, roles in
                    devices.first { $0.id == id }
                        ?? BLECSCClient.DiscoveredSensor(
                            id: id,
                            name: preferences.pairedSensors.first { $0.peripheralID == id }?.displayName,
                            roles: roles,
                            connectionState: .disconnected,
                            batteryPercent: nil,
                            capabilities: nil
                        )
                }
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }

        var availableDevices: [BLECSCClient.DiscoveredSensor] {
            let paired = Set(preferences.pairedSensors.map(\.peripheralID))
            return devices.filter { !paired.contains($0.id) }
        }

        /// Paired sensors whose hardware can fill either role, and so are worth
        /// re-prompting. A property rather than a method so the view can reach it
        /// through the store's dynamic member lookup.
        var reassignableIDs: Set<UUID> {
            let paired = Set(preferences.pairedSensors.map(\.peripheralID))
            return Set(
                devices
                    .filter { paired.contains($0.id) && $0.capabilities?.requiresRoleSelection == true }
                    .map(\.id)
            )
        }
    }

    enum Action: Equatable {
        case task
        case onDisappear
        case devicesUpdated([BLECSCClient.DiscoveredSensor])
        case pairButtonTapped(UUID)
        case unpairButtonTapped(UUID)
        case rowTapped(UUID)
        case roleDialog(PresentationAction<RoleChoice>)

        /// The peripheral travels with the choice so the dialog is self-contained —
        /// the reducer doesn't have to remember which row raised it.
        @CasePathable
        enum RoleChoice: Equatable {
            case chose(peripheralID: UUID, roles: Set<BLECSCClient.SensorRole>)
        }
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
                // A pairing in flight is waiting on the 0x2A5C read; the answer
                // arrives here, on the device list, rather than as its own event.
                guard let id = state.pendingPairing,
                      let capabilities = devices.first(where: { $0.id == id })?.capabilities
                else { return .none }

                if capabilities.requiresRoleSelection {
                    state.roleDialog = Self.roleDialog(
                        for: id, name: devices.first { $0.id == id }?.name
                    )
                    return .none
                }
                state.pendingPairing = nil
                let supported = capabilities.supportedRoles
                guard !supported.isEmpty else {
                    // Reports neither wheel nor crank — nothing it can be used for.
                    return .run { [bleCSCClient] _ in await bleCSCClient.unpair(id) }
                }
                // Single capability: assign it and ask nothing (BLE.md §5.0).
                return apply(supported, to: id, in: &state)

            case .pairButtonTapped(let id):
                state.pendingPairing = id
                return .run { _ in await bleCSCClient.pair(id) }

            case .rowTapped(let id):
                guard state.reassignableIDs.contains(id) else { return .none }
                state.roleDialog = Self.roleDialog(
                    for: id, name: state.devices.first { $0.id == id }?.name
                )
                return .none

            case .roleDialog(.presented(.chose(let id, let roles))):
                state.pendingPairing = nil
                return apply(roles, to: id, in: &state)

            case .roleDialog(.dismiss):
                // Cancelling a *new* pairing must release the sensor: it is connected
                // holding no roles, and leaving it there would be an invisible
                // half-pairing. Cancelling a reassignment just keeps what it had.
                guard let id = state.pendingPairing else { return .none }
                state.pendingPairing = nil
                return .run { [bleCSCClient] _ in await bleCSCClient.unpair(id) }

            case .unpairButtonTapped(let id):
                state.$preferences.withLock { $0.pairedSensors.removeAll { $0.peripheralID == id } }
                let assignments = state.preferences.sensorAssignments
                return .run { [bleCSCClient] _ in
                    await bleCSCClient.unpair(id)
                    await bleCSCClient.setPairedSensors(assignments)
                }
            }
        }
        .ifLet(\.$roleDialog, action: \.roleDialog)
    }

    /// The single write funnel: persist the decision and push it to the client
    /// together, so the records and the connections cannot drift apart. Mirrors
    /// `SettingsFeature.apply(_:to:)`.
    private func apply(
        _ roles: Set<BLECSCClient.SensorRole>,
        to id: UUID,
        in state: inout State
    ) -> Effect<Action> {
        let name = state.devices.first { $0.id == id }?.name
        state.$preferences.withLock { preferences in
            // Drop this peripheral's records, and any other peripheral's claim on a
            // role being reassigned — the same rule the client applies to slots, so
            // the two representations stay in step.
            preferences.pairedSensors.removeAll { $0.peripheralID == id || roles.contains($0.role) }
            // Iterate `allCases` rather than the set: `Set` has no stable order, and
            // the persisted file should not churn between writes.
            preferences.pairedSensors += BLECSCClient.SensorRole.allCases
                .filter(roles.contains)
                .map { PairedSensor(peripheralID: id, role: $0, displayName: name) }
        }
        let assignments = state.preferences.sensorAssignments
        return .run { [bleCSCClient] _ in
            await bleCSCClient.setRoles(id, roles)
            await bleCSCClient.setPairedSensors(assignments)
        }
    }

    private static func roleDialog(
        for id: UUID, name: String?
    ) -> ConfirmationDialogState<Action.RoleChoice> {
        ConfirmationDialogState {
            TextState("What should this sensor do?")
        } actions: {
            ButtonState(action: .chose(peripheralID: id, roles: [.speed])) {
                TextState("Speed")
            }
            ButtonState(action: .chose(peripheralID: id, roles: [.cadence])) {
                TextState("Cadence")
            }
            ButtonState(action: .chose(peripheralID: id, roles: [.speed, .cadence])) {
                TextState("Both")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState("\(name ?? "This sensor") reports both wheel and crank data.")
        }
    }
}
