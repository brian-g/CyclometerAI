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
/// Pairing spans all three kinds (#100). A CSC sensor has to be interrogated for 0x2A5C
/// and may need the role prompt; a radar or a strap has no such ambiguity — the service
/// it advertises *is* the role it can fill — so its Pair goes straight to the collision
/// check and writes a record without connecting anything from here.
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
        /// Raised when the roles a sensor is claiming are already held by another
        /// peripheral (BLE.md §5.0 step 4). An alert rather than a second
        /// confirmation dialog: it is a destructive binary confirm with a title, and a
        /// distinct SwiftUI modifier is what keeps it from racing the role sheet's
        /// dismissal when the two are raised back to back.
        @Presents var collisionAlert: AlertState<Action.CollisionChoice>?
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
        /// radar has to appear here, and be marked disconnected, whether or not it is
        /// advertising.
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

        /// The flat list S11 actually renders (UX.md §S11): paired sensors first, then
        /// discovered-but-unpaired. Both halves are already name-sorted, so the order is
        /// the spec's without a second sort.
        ///
        /// The two halves stay separate properties rather than being folded in here —
        /// each answers a question the reducer asks on its own, and the split is what
        /// keeps an out-of-range sensor out of the unpaired half.
        var listedDevices: [DiscoveredDevice] { pairedDevices + availableDevices }

        /// The rider's durable pairings, keyed by peripheral — what each row's
        /// Pair/Unpair choice and role subtitle read.
        ///
        /// This, not `DiscoveredDevice.roles`, because those report live tenancy in the
        /// reporting client: a paired sensor that is out of range holds none, and would
        /// otherwise be offered a Pair button and no roles to show. A pass-through to
        /// `preferences` so the view can reach it through dynamic member lookup, the
        /// same reason `reassignableIDs` is a property.
        var pairedRoles: [UUID: Set<SensorRole>] { preferences.pairedRoles }

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
        case collisionAlert(PresentationAction<CollisionChoice>)

        /// The peripheral travels with the choice so the dialog is self-contained —
        /// the reducer doesn't have to remember which row raised it.
        @CasePathable
        enum RoleChoice: Equatable {
            case chose(peripheralID: UUID, roles: Set<SensorRole>)
        }

        /// Same reason as `RoleChoice`: the claim survives inside the alert, so the
        /// reducer needs no second field holding what is waiting to be written.
        @CasePathable
        enum CollisionChoice: Equatable {
            case replace(peripheralID: UUID, roles: Set<SensorRole>)
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
                //
                // A prompt already on screen owns that pairing, so this must not
                // re-derive it. `pendingPairing` stays set across both prompts — it is
                // what lets Cancel release the peripheral — and the sweep timer
                // re-broadcasts every 10s, so without this the rider's collision alert
                // is replaced by the role sheet again a few seconds after answering it.
                guard state.roleDialog == nil, state.collisionAlert == nil,
                      let id = state.pendingPairing,
                      let device = merged.first(where: { $0.id == id }),
                      let capabilities = device.capabilities
                else { return reconcile }

                // What the same peripheral can be claimed for outside CSC. Non-empty
                // only for a combo advertising radar or heart rate as well, which
                // unified discovery merges into this one row (#98) — one Pair button
                // has to claim everything that row can do, in one write.
                //
                // Free roles only: see `freeUnambiguousRoles`.
                let alsoClaims = Self.freeUnambiguousRoles(
                    of: device.kinds, excluding: id, in: state.preferences
                )

                if capabilities.requiresRoleSelection {
                    state.roleDialog = Self.roleDialog(for: id, name: device.name)
                    return reconcile
                }
                let supported = capabilities.supportedRoles
                guard !supported.isEmpty else {
                    // Reports neither wheel nor crank — nothing the CSC client can use
                    // it for, so release it there. `setPairedSensors` only closes the
                    // reconnect gate; the connection `pair` opened is `unpair`'s to
                    // drop. A combo still has its other role to claim, and keeps its
                    // pairing on that side.
                    state.pendingPairing = nil
                    let release = Effect<Action>.run { [bleCSCClient] _ in
                        await bleCSCClient.unpair(id)
                    }
                    guard !alsoClaims.isEmpty else { return .concatenate(reconcile, release) }
                    return .concatenate(reconcile, release, commit(alsoClaims, to: id, in: &state))
                }
                // Single capability: assign it and ask nothing about the role
                // (BLE.md §5.0) — but still run the collision check, which is what
                // "skips straight to the check" means. `commit` clears
                // `pendingPairing` itself, and only once nothing is left to confirm.
                //
                // Sequential, not merged: both effects push an assignment map, and
                // the one built last is the one that must land last.
                return .concatenate(reconcile, commit(supported.union(alsoClaims), to: id, in: &state))


            case .pairButtonTapped(let id):
                // Not while another pairing is in flight — the same rule `rowTapped`
                // follows below, for the same reason. `pendingPairing` names exactly one
                // interrogated peripheral and the dismiss path reads it to decide what to
                // release, so a second tap would either clear it — stranding the first
                // sensor connected holding no roles, its capabilities arriving to a guard
                // that no longer matches — or inherit it, releasing the wrong peripheral
                // on Cancel.
                guard state.pendingPairing == nil else { return .none }
                guard let device = state.devices.first(where: { $0.id == id }) else { return .none }
                guard device.kinds.contains(.speedCadence) else {
                    // Radar and heart rate publish no capabilities to interrogate: the
                    // service the peripheral advertised is the role it fills, so there
                    // is nothing to ask and nothing to wait for. Straight to the
                    // collision gate, with no `pendingPairing` — the single-slot clients
                    // connect on their own once `setPairedSensor` names the peripheral,
                    // so no half-pairing exists for a cancel to have to release.
                    return commit(Self.unambiguousRoles(of: device.kinds), to: id, in: &state)
                }
                state.pendingPairing = id
                return .run { _ in await bleCSCClient.pair(id) }

            case .rowTapped(let id):
                // Not while a pairing is in flight. `pendingPairing` names the
                // interrogated peripheral, and the dismiss path reads it to decide what
                // to release — so a reassignment prompt raised on top of one would make
                // its Cancel unpair the *other* sensor, and its answer would clear the
                // in-flight marker and strand that peripheral connected holding no roles.
                guard state.pendingPairing == nil, state.reassignableIDs.contains(id)
                else { return .none }
                state.roleDialog = Self.roleDialog(
                    for: id, name: state.devices.first { $0.id == id }?.name
                )
                return .none

            case .roleDialog(.presented(.chose(let id, let roles))):
                // The prompt only ever offers speed and cadence, so a combo that is also
                // a radar or a strap has to have those folded back in here — otherwise
                // answering it would silently drop the role the same Pair tap claimed.
                // Re-affirming a role the peripheral already holds is a no-op in `apply`.
                let kinds = state.devices.first { $0.id == id }?.kinds ?? []
                let alsoClaims = Self.freeUnambiguousRoles(
                    of: kinds, excluding: id, in: state.preferences
                )
                return commit(roles.union(alsoClaims), to: id, in: &state)

            case .collisionAlert(.presented(.replace(let id, let roles))):
                state.pendingPairing = nil
                return apply(roles, to: id, in: &state)

            case .roleDialog(.dismiss), .collisionAlert(.dismiss):
                // Cancelling a *new* pairing must release the sensor: it is connected
                // holding no roles, and leaving it there would be an invisible
                // half-pairing. Cancelling a reassignment just keeps what it had.
                //
                // Both prompts share this: whichever of them the rider backs out of,
                // the peripheral behind an in-flight pairing has to be released, and
                // `pendingPairing` is the only thing that distinguishes the two cases.
                guard let id = state.pendingPairing else { return .none }
                state.pendingPairing = nil
                return .run { [bleCSCClient] _ in await bleCSCClient.unpair(id) }

            case .unpairButtonTapped(let id):
                // Every record this peripheral holds, across all three kinds. The flat
                // list gives a device one row and one button (UX.md §S11), so this is
                // the only thing Unpair can mean — the M6 reading, "CSC records only,
                // the radar pairing was made elsewhere", described a screen where radar
                // and heart rate could not be paired at all.
                let released = Set((state.preferences.pairedRoles[id] ?? []).compactMap(\.kind))
                state.$preferences.withLock {
                    $0.pairedSensors.removeAll { $0.peripheralID == id }
                }
                let assignments = state.preferences.cscAssignments
                return .run { [bleCSCClient, variaRadarClient, bleHRClient] _ in
                    if released.contains(.speedCadence) {
                        // Close the reconnect gate *before* tearing the connection down.
                        // `unpair` only drops the slot; `.discovered` consults
                        // `pairedAssignments`, so the other order leaves a window in which
                        // the sensor's next advertisement reconnects it — holding roles,
                        // with no record behind it. The pairing scan is running, so that
                        // window is about one advertising interval wide.
                        await bleCSCClient.setPairedSensors(assignments)
                        await bleCSCClient.unpair(id)
                    }
                    // A single-slot client moves gate and connection together, so nil is
                    // the whole operation — no separate teardown to order against it.
                    if released.contains(.radar) { await variaRadarClient.setPairedSensor(nil) }
                    if released.contains(.heartRate) { await bleHRClient.setPairedSensor(nil) }
                }
            }
        }
        .ifLet(\.$roleDialog, action: \.roleDialog)
        .ifLet(\.$collisionAlert, action: \.collisionAlert)
    }

    /// Step 4 of the pairing flow (BLE.md §5.0): gate the write on the rider when a
    /// claimed role already belongs to someone else.
    ///
    /// Every path that assigns roles comes through here rather than calling `apply`
    /// directly — the role prompt's answer, and the auto-assignment a single-capability
    /// sensor gets without being asked. Role selection therefore always runs *first*,
    /// which is what makes it possible to name what would be displaced.
    private func commit(
        _ roles: Set<SensorRole>,
        to id: UUID,
        in state: inout State
    ) -> Effect<Action> {
        let incumbents = Self.incumbents(of: roles, excluding: id, in: state.preferences)
        guard !incumbents.isEmpty else {
            state.pendingPairing = nil
            return apply(roles, to: id, in: &state)
        }
        // `pendingPairing` deliberately survives into the alert. It is the only record
        // that this peripheral is connected holding no roles, and so the only thing
        // that lets Cancel release it rather than leave a half-pairing behind.
        state.collisionAlert = Self.collisionAlert(for: id, roles: roles, displacing: incumbents)
        return .none
    }

    /// The sensors that would be displaced by claiming `roles`, one entry per occupied
    /// role. Empty when nothing collides.
    ///
    /// Read from the durable records rather than the live device list: an incumbent
    /// that is out of range appears on no discovery stream, and naming it is exactly
    /// what `PairedSensor.displayName` is retained for.
    private static func incumbents(
        of roles: Set<SensorRole>,
        excluding id: UUID,
        in preferences: AppPreferences
    ) -> [PairedSensor] {
        // `allCases` order, not `Set` order — the copy must not reorder between runs.
        SensorRole.allCases
            .filter(roles.contains)
            .compactMap { role in
                guard let held = preferences.pairedSensor(for: role), held.peripheralID != id
                else { return nil }
                return held
            }
    }

    /// One confirmation naming every incumbent, never one per role (UX.md §S11).
    ///
    /// A single collision uses the spec's sentence as the title and needs no message.
    /// Two of them need the itemised form, and the title then depends on whether one
    /// combo holds both roles or two separate sensors do — "two sensors" would simply
    /// be false in the first case.
    private static func collisionAlert(
        for id: UUID,
        roles: Set<SensorRole>,
        displacing incumbents: [PairedSensor]
    ) -> AlertState<Action.CollisionChoice> {
        // Grammatical inside a sentence, unlike the role prompt's "This sensor" — this
        // copy always names the incumbent mid-clause.
        func name(_ incumbent: PairedSensor) -> String {
            incumbent.displayName ?? "an unnamed sensor"
        }
        let itemised = incumbents
            .map { "\($0.role.displayName) is assigned to \(name($0))." }
            .joined(separator: "\n")
        let displacedPeripherals = Set(incumbents.map(\.peripheralID)).count
        let title: String
        let message: String?
        if incumbents.count == 1, let only = incumbents.first {
            title = "\(only.role.displayName) is already assigned to \(name(only))."
            message = nil
        } else if displacedPeripherals == 1, let sole = incumbents.first {
            // "two sensors" would be false when one combo holds both roles.
            title = "Replace \(name(sole))?"
            message = itemised
        } else {
            title = "Replace two sensors?"
            message = itemised
        }
        return AlertState(
            title: { TextState(title) },
            actions: {
                ButtonState(role: .destructive, action: .replace(peripheralID: id, roles: roles)) {
                    TextState("Replace")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            },
            // The single-collision title is a whole sentence on its own; a message
            // repeating it would just be noise, so that case carries none.
            message: message.map { text in { TextState(text) } }
        )
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
        // Which profiles this claim touches. Everything below is scoped to these, so a
        // decision made about one profile cannot disturb a pairing held in another (#93)
        // — the rule that used to be spelled `isCSC`, now that a claim can carry
        // `.radar` or `.heartRate` too.
        let affected = Set(roles.compactMap(\.kind))
        state.$preferences.withLock { preferences in
            // Drop this peripheral's records within the affected profiles, and any other
            // peripheral's claim on a role being reassigned — the same rule the client
            // applies to slots, so the two representations stay in step.
            preferences.pairedSensors.removeAll {
                roles.contains($0.role)
                    || ($0.peripheralID == id && $0.role.kind.map(affected.contains) == true)
            }
            // Iterate `allCases` rather than the set: `Set` has no stable order, and
            // the persisted file should not churn between writes.
            preferences.pairedSensors += SensorRole.allCases
                .filter(roles.contains)
                .map { PairedSensor(peripheralID: id, role: $0, displayName: name) }
        }
        let assignments = state.preferences.cscAssignments
        // Read after the write, so a displaced incumbent is torn down by the very call
        // that adopts its replacement — a single-slot client needs no second call to
        // release the sensor it is no longer pointing at.
        let radarID = state.preferences.pairedSensor(for: .radar)?.peripheralID
        let hrID = state.preferences.pairedSensor(for: .heartRate)?.peripheralID
        return .run { [bleCSCClient, variaRadarClient, bleHRClient] _ in
            if affected.contains(.speedCadence) {
                // Assignments first, for the same reason as unpair: `setRoles` can strip
                // an incumbent's last role and disconnect it, and until the new map lands
                // its next advertisement reconnects it under the old one — taking the role
                // straight back off the sensor the rider just chose.
                await bleCSCClient.setPairedSensors(assignments)
                // Only the CSC subset: `roles` can now carry `.radar` or `.heartRate`,
                // and `setRoles` assigns whatever it is handed to a CSC slot.
                await bleCSCClient.setRoles(id, roles.intersection(SensorRole.cscRoles))
            }
            // Skipped entirely for a claim that touches no CSC role, because such a claim
            // cannot alter the map: the removal above only reaches a record whose role is
            // being claimed, or whose peripheral is being reassigned *within* the same
            // profiles. Pushing an unchanged map would be noise on every radar pairing.
            if affected.contains(.radar) { await variaRadarClient.setPairedSensor(radarID) }
            if affected.contains(.heartRate) { await bleHRClient.setPairedSensor(hrID) }
        }
    }

    /// The unambiguous roles worth folding into an answer about something else — the
    /// ones nothing is currently using.
    ///
    /// A combo advertising CSC *and* heart rate is paired by answering "what should this
    /// sensor do?", a question about wheel and crank data. That answer is not consent to
    /// displace the rider's strap: taking an occupied role here would raise a
    /// replace-or-cancel alert about a role they were never asked about, and cancelling
    /// it — the natural response to a question you did not expect — runs the in-flight
    /// release and throws away the speed pairing they *did* choose.
    ///
    /// A free role costs nothing to claim and saves a second trip through the list, so it
    /// still rides along. Moving an occupied one onto the combo stays what it always was:
    /// a deliberate Pair tap on that row once the incumbent is gone.
    private static func freeUnambiguousRoles(
        of kinds: Set<SensorKind>, excluding id: UUID, in preferences: AppPreferences
    ) -> Set<SensorRole> {
        unambiguousRoles(of: kinds).filter { role in
            let held = preferences.pairedSensor(for: role)
            return held == nil || held?.peripheralID == id
        }
    }

    /// The roles a peripheral advertising `kinds` can be claimed for without asking.
    ///
    /// Radar and heart rate are one service to one role, so discovery alone settles what
    /// they do. `.speedCadence` contributes nothing: one service, two roles, and which
    /// of them applies is exactly what 0x2A5C and the role prompt are for.
    private static func unambiguousRoles(of kinds: Set<SensorKind>) -> Set<SensorRole> {
        var roles: Set<SensorRole> = []
        if kinds.contains(.radar) { roles.insert(.radar) }
        if kinds.contains(.heartRate) { roles.insert(.heartRate) }
        return roles
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
