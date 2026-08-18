import ComposableArchitecture
import Foundation

/// S11 — Device Management. Scans for every supported sensor, lists what was found as
/// one deduped device list, and pairs, unpairs or reassigns one at a time.
///
/// Discovery spans all three clients (#98). Each reports the peripherals its own scan
/// filter admitted, tagged with its `SensorKind`; this feature merges them into one row
/// per `CBPeripheral.identifier`, so a device speaking two supported profiles is one row
/// carrying both tags rather than two rows the rider has to reconcile. It also owns the
/// pairing-scan lifecycle: without a `beginPairingScan` per client, `BLECentral`'s
/// filtered scan never looks for a radar or a strap outside a ride, and no pairing
/// record for either could ever be created.
///
/// Pairing itself is still CSC-only. Writing `.radar` and `.heartRate` records is #100's,
/// along with the flat Sketch layout that replaces the two sections below — so a row
/// holding only those roles lists and shows its status, but carries no action.
///
/// Pairings are durable (#67): this feature owns the `PairedSensor` records and pushes
/// them into `BLECSCClient`, which holds no persistence and connects only what it has
/// been told about.
@Reducer
struct DeviceManagementFeature {

    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.continuousClock) var clock

    /// How often the list re-checks what is still advertising while the screen is open.
    ///
    /// CoreBluetooth reports a peripheral once per scan session, so a device that is
    /// switched off simply stops arriving — there is no "lost" callback to react to.
    /// Restarting the scan is what re-establishes the truth, and a sensor that misses
    /// one restart is dropped at the next, so a device goes at worst two intervals after
    /// it actually left. Ten seconds keeps that under half a minute while leaving ample
    /// margin over the ~1s advertising interval these sensors idle at.
    static let sweepInterval: Duration = .seconds(10)

    /// Everything `.task` starts, so `.onDisappear` can end all of it in one place.
    ///
    /// The three device streams never finish on their own and the sweep timer never
    /// finishes at all, so without this they outlive the screen — surviving on nothing
    /// but SwiftUI cancelling the view's `.task` scope. The reducer already prefers
    /// explicit teardown here for the scan refcount; the effects deserve the same.
    private enum CancelID { case screen }

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// Live discovery, mirrored per client. Membership here means "seen this scan
        /// session", not "paired" — that is `preferences.pairedSensors`.
        ///
        /// Kept split by source rather than merged on arrival: each client re-sends its
        /// whole list on every change, so the last list from each is the current truth
        /// for that kind, and merging on read means a stale entry can never survive a
        /// client's own removal.
        var sources: [SensorKind: [DiscoveredDevice]] = [:]
        @Presents var roleDialog: ConfirmationDialogState<Action.RoleChoice>?
        /// The peripheral currently being interrogated for capabilities after a Pair
        /// tap. Non-nil means a pairing is mid-flight, which is what makes a cancelled
        /// prompt release the sensor rather than leave it connected holding no role.
        var pendingPairing: UUID? = nil

        /// Every peripheral seen this session, one row each.
        ///
        /// The dedupe is the point: a combo device advertising CSC and heart rate
        /// arrives on two streams, and appending both would give the rider two rows for
        /// one piece of hardware, each claiming half of what it can do.
        var devices: [DiscoveredDevice] {
            sources.values.flatMap { $0 }
                .reduce(into: [UUID: DiscoveredDevice]()) { merged, device in
                    merged[device.id] = merged[device.id].map { $0.merged(with: device) } ?? device
                }
                .values
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }

        /// Built from the persisted records, not from `DiscoveredDevice.isPaired`: a
        /// paired sensor that is out of range holds no roles in its client, and would
        /// otherwise drop into Available with a Pair button.
        ///
        /// Covers every role now that the list spans all three kinds (#98) — a paired
        /// radar has to appear here, and be marked disconnected, even though nothing
        /// writes such a record until #100.
        var pairedDevices: [DiscoveredDevice] {
            let seen = devices
            return preferences.pairedRoles
                .map { id, roles in
                    seen.first { $0.id == id }
                        ?? DiscoveredDevice(
                            id: id,
                            name: preferences.pairedSensors.first { $0.peripheralID == id }?.displayName,
                            // No advertisement to classify it, so the record's own roles
                            // are the only evidence of what it is.
                            kinds: Set(roles.compactMap(\.kind)),
                            roles: roles,
                            connectionState: .disconnected
                        )
                }
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }

        /// Everything seen but not paired in any role. A peripheral already paired for
        /// one role stays out of here even when another kind it also serves is free —
        /// it has a row above, and #99 is what will let a second role be claimed on it.
        var availableDevices: [DiscoveredDevice] {
            let paired = Set(preferences.pairedRoles.keys)
            return devices.filter { !paired.contains($0.id) }
        }

        /// Paired sensors whose hardware can fill either role, and so are worth
        /// re-prompting. A property rather than a method so the view can reach it
        /// through the store's dynamic member lookup.
        ///
        /// Still keyed on `cscPairedIDs`: only a CSC pairing has a role to reassign, and
        /// only a CSC sensor ever publishes capabilities.
        var reassignableIDs: Set<UUID> {
            let paired = preferences.cscPairedIDs
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
        /// Pull to refresh. Restarts the scan on every client.
        case refreshRequested
        case devicesUpdated(SensorKind, [DiscoveredDevice])
        case pairButtonTapped(UUID)
        case unpairButtonTapped(UUID)
        case rowTapped(UUID)
        case roleDialog(PresentationAction<RoleChoice>)

        /// The peripheral travels with the choice so the dialog is self-contained —
        /// the reducer doesn't have to remember which row raised it.
        @CasePathable
        enum RoleChoice: Equatable {
            case chose(peripheralID: UUID, roles: Set<SensorRole>)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    // Sequential inside one effect, not three merged ones: a
                    // deterministic order is what makes the whole lifecycle assertable
                    // as a single interleaved call log (BLE.md §5.0). Same order as
                    // `AppFeature.task`'s launch push.
                    .run { _ in
                        await bleCSCClient.beginPairingScan()
                        await variaRadarClient.beginPairingScan()
                        await bleHRClient.beginPairingScan()
                    },
                    .run { send in
                        for await devices in bleCSCClient.discoveredDevices() {
                            await send(.devicesUpdated(.speedCadence, devices))
                        }
                    },
                    .run { send in
                        for await devices in variaRadarClient.discoveredDevices() {
                            await send(.devicesUpdated(.radar, devices))
                        }
                    },
                    .run { send in
                        for await devices in bleHRClient.discoveredDevices() {
                            await send(.devicesUpdated(.heartRate, devices))
                        }
                    },
                    // Sweeping stale rows is the same operation as a manual refresh, so
                    // it reuses that action rather than growing a second path that could
                    // drift from it.
                    .run { send in
                        for await _ in clock.timer(interval: Self.sweepInterval) {
                            await send(.refreshRequested)
                        }
                    }
                )
                .cancellable(id: CancelID.screen)

            case .onDisappear:
                // Explicit rather than relying on effect cancellation: each client's
                // scan refcount has to be balanced deterministically, and an action
                // is what a TestStore can assert.
                return .merge(
                    .cancel(id: CancelID.screen),
                    .run { _ in
                        await bleCSCClient.endPairingScan()
                        await variaRadarClient.endPairingScan()
                        await bleHRClient.endPairingScan()
                    }
                )

            case .refreshRequested:
                // Begin *then* end, per client. `beginPairingScan` unconditionally
                // re-issues the hardware scan, which is what makes CoreBluetooth
                // re-advertise peripherals it has already reported — the actual
                // mechanism behind "restarts the scan". Taking the extra reference
                // first means the refcount never reaches zero, so the radio is never
                // dropped mid-refresh, and the pair balances on its own.
                //
                // It also rotates each client's scan generation, which is what drops
                // peripherals that have stopped advertising. Both the rider's pull and
                // the sweep timer arrive here.
                return .run { _ in
                    await bleCSCClient.beginPairingScan()
                    await bleCSCClient.endPairingScan()
                    await variaRadarClient.beginPairingScan()
                    await variaRadarClient.endPairingScan()
                    await bleHRClient.beginPairingScan()
                    await bleHRClient.endPairingScan()
                }

            case .devicesUpdated(let kind, let devices):
                state.sources[kind] = devices
                // Reconciliation reads the *merged* list, not just the kind that
                // changed: capabilities only ever arrive from the CSC stream, and a row
                // sourced elsewhere carries nil and is skipped.
                let merged = state.devices
                let reconcile = reconcileCapabilities(merged, in: &state)

                // A pairing in flight is waiting on the 0x2A5C read; the answer
                // arrives here, on the device list, rather than as its own event.
                guard let id = state.pendingPairing,
                      let capabilities = merged.first(where: { $0.id == id })?.capabilities
                else { return reconcile }

                if capabilities.requiresRoleSelection {
                    state.roleDialog = Self.roleDialog(
                        for: id, name: merged.first { $0.id == id }?.name
                    )
                    return reconcile
                }
                state.pendingPairing = nil
                let supported = capabilities.supportedRoles
                guard !supported.isEmpty else {
                    // Reports neither wheel nor crank — nothing it can be used for.
                    return .concatenate(
                        reconcile,
                        .run { [bleCSCClient] _ in await bleCSCClient.unpair(id) }
                    )
                }
                // Single capability: assign it and ask nothing (BLE.md §5.0).
                // Sequential, not merged: both effects push an assignment map, and
                // the one built last is the one that must land last.
                return .concatenate(reconcile, apply(supported, to: id, in: &state))

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
                // CSC records only. Unpair on this screen means "release the speed and
                // cadence roles"; the same peripheral's radar or HR pairing was made
                // elsewhere and is not this button's to revoke (#93).
                state.$preferences.withLock {
                    $0.pairedSensors.removeAll { $0.peripheralID == id && $0.isCSC }
                }
                let assignments = state.preferences.cscAssignments
                return .run { [bleCSCClient] _ in
                    // Close the reconnect gate *before* tearing the connection down.
                    // `unpair` only drops the slot; `.discovered` consults
                    // `pairedAssignments`, so the other order leaves a window in which
                    // the sensor's next advertisement reconnects it — holding roles,
                    // with no record behind it. The pairing scan is running, so that
                    // window is about one advertising interval wide.
                    await bleCSCClient.setPairedSensors(assignments)
                    await bleCSCClient.unpair(id)
                }
            }
        }
        .ifLet(\.$roleDialog, action: \.roleDialog)
    }

    /// The single write funnel: persist the decision and push it to the client
    /// together, so the records and the connections cannot drift apart. Mirrors
    /// `SettingsFeature.apply(_:to:)`.
    private func apply(
        _ roles: Set<SensorRole>,
        to id: UUID,
        in state: inout State
    ) -> Effect<Action> {
        let name = state.devices.first { $0.id == id }?.name
        state.$preferences.withLock { preferences in
            // Drop this peripheral's records, and any other peripheral's claim on a
            // role being reassigned — the same rule the client applies to slots, so
            // the two representations stay in step.
            //
            // Scoped to CSC records: `roles` only ever holds CSC roles, but the
            // `peripheralID` clause would otherwise take a radar or HR pairing down
            // with it when a device serving both profiles is assigned a CSC role (#93).
            preferences.pairedSensors.removeAll {
                $0.isCSC && ($0.peripheralID == id || roles.contains($0.role))
            }
            // Iterate `allCases` rather than the set: `Set` has no stable order, and
            // the persisted file should not churn between writes.
            preferences.pairedSensors += SensorRole.allCases
                .filter(roles.contains)
                .map { PairedSensor(peripheralID: id, role: $0, displayName: name) }
        }
        let assignments = state.preferences.cscAssignments
        return .run { [bleCSCClient] _ in
            // Assignments first, for the same reason as unpair: `setRoles` can strip
            // an incumbent's last role and disconnect it, and until the new map lands
            // its next advertisement reconnects it under the old one — taking the role
            // straight back off the sensor the rider just chose.
            await bleCSCClient.setPairedSensors(assignments)
            await bleCSCClient.setRoles(id, roles)
        }
    }

    /// Drop persisted roles the hardware has since reported it cannot fill.
    ///
    /// The rider can't create this state — the prompt only offers roles the
    /// capabilities advertise — but a pairing can outlive a firmware change. The
    /// client narrows its own slot when that happens (`narrowRolesLocked`); without
    /// this the record never follows, so every launch reconnects, re-narrows, and the
    /// paired row goes on claiming a role the sensor refuses.
    ///
    /// Only peripherals that published capabilities are considered: a read that never
    /// answered says nothing about what the sensor can do.
    private func reconcileCapabilities(
        _ devices: [DiscoveredDevice], in state: inout State
    ) -> Effect<Action> {
        let corrections = devices.compactMap { device -> (id: UUID, surviving: Set<SensorRole>)? in
            guard let supported = device.capabilities?.supportedRoles else { return nil }
            // CSC roles only. 0x2A5C says nothing about whether the same peripheral is
            // also a radar or an HR strap, so a record for one of those must survive a
            // correction made on this evidence (#93).
            let held = Set(
                state.preferences.pairedSensors
                    .filter { $0.peripheralID == device.id && $0.isCSC }
                    .map(\.role)
            )
            guard !held.subtracting(supported).isEmpty else { return nil }
            return (device.id, held.intersection(supported))
        }
        guard !corrections.isEmpty else { return .none }

        state.$preferences.withLock { preferences in
            for correction in corrections {
                preferences.pairedSensors.removeAll {
                    $0.peripheralID == correction.id
                        && $0.isCSC
                        && !correction.surviving.contains($0.role)
                }
            }
        }
        let assignments = state.preferences.cscAssignments
        // Nothing left to hold means the pairing is over: `setRoles` rejects an empty
        // set, so releasing it has to go through `unpair`.
        let orphaned = corrections.filter(\.surviving.isEmpty).map(\.id)
        return .run { [bleCSCClient] _ in
            await bleCSCClient.setPairedSensors(assignments)
            for id in orphaned { await bleCSCClient.unpair(id) }
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
