import ComposableArchitecture
import CoreBluetooth
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
// Retrieve after an untethered ride: `log collect --device --last 1h` (notice level persists).
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "csc")

private let cscServiceUUID     = CBUUID(string: "1816")
private let cscMeasurementUUID = CBUUID(string: "2A5B")  // notify

// Identifies this client to BLEClient's connection ref-count, so disconnecting a
// CSC peripheral never tears down a connection a different client (HR/radar) shares
// with the same physical device.
private let cscOwnerID = "csc"
// 0x2A5C (CSC Feature, read) deliberately unused: BLEClient has no readValue
// operation, sensor capabilities are inferable from the measurement flags byte,
// and the role-selection sheet is an M6/S11 (pairing UI) concern. See BLE.md §5.0.

// Default 700c × 23mm tyre. Parameterised so M6 can supply the user-configured or
// GPS-auto-calibrated value via setWheelCircumference.
private let defaultWheelCircumferenceMM = 2096

// MARK: - BLECSCClient

/// TCA dependency for the Bluetooth SIG standard BLE Cycling Speed and Cadence
/// (CSC) Profile (0x1816). Connects to any compliant sensor (Garmin GSC-10, Wahoo
/// RPM, etc.) and derives speed from cumulative wheel revolutions and cadence from
/// cumulative crank revolutions. Uses BLEClient as the CoreBluetooth transport.
///
/// Speed and cadence are independent *roles*, not a single combined sensor type
/// (BLE.md §5.0). One physical device may serve both roles, or a rider may pair a
/// dedicated speed sensor and use a combo device for cadence only. Each role reads
/// only its relevant fields from the shared CSC notification stream, so the client
/// supports up to one peripheral per role simultaneously.
struct BLECSCClient: Sendable {
    enum SensorRole: Hashable, CaseIterable, Sendable { case speed, cadence }

    /// Connection lifecycle per BLE.md §6. `.active` means notifications are
    /// enabled and measurement data is flowing. State is tracked per role: a role's
    /// state is the state of the peripheral fulfilling it, or `.disconnected` /
    /// `.scanning` when no peripheral holds it.
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case scanning
        case connecting
        case connected
        case active
        case reconnecting
    }

    /// Scan for CSC sensors and auto-connect whichever ones are needed to fulfil
    /// both roles — the first discovered sensor optimistically takes both; if its
    /// first measurement shows it only supports one, the other role is freed for
    /// a second discovered sensor to claim.
    var startScanning:         @Sendable () async -> Void
    var stopScanning:          @Sendable () async -> Void
    /// Explicit role assignment (M6 pairing UI). Roles currently held by another
    /// peripheral are reassigned to this one; a peripheral left with no roles is
    /// disconnected. The same peripheral may hold both roles.
    var connect:               @Sendable (UUID, Set<SensorRole>) async -> Void
    /// Disconnect every CSC peripheral. Per-device disconnect is an S11 concern.
    var disconnect:            @Sendable () async -> Void
    /// Wheel circumference in millimetres; affects subsequent speed calculations.
    var setWheelCircumference: @Sendable (Int) async -> Void
    var speed:                 @Sendable () -> AsyncStream<Double>            // m/s
    var cadence:               @Sendable () -> AsyncStream<Double>            // rpm
    var connectionState:       @Sendable (SensorRole) -> AsyncStream<ConnectionState>
    /// Advertised name of the peripheral currently holding this role, or nil if
    /// unheld or the peripheral didn't advertise one. Replays on subscribe, same
    /// as `connectionState`.
    var sensorName:            @Sendable (SensorRole) -> AsyncStream<String?>

    /// Reconnection backoff ladder: 1s, 2s, 4s, 8s, 16s, then capped at 30s.
    /// Identical policy to VariaRadarClient (BLE.md §6.1).
    static func reconnectDelay(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 5), 30))
    }

    /// After this many failed attempts the sensor is considered lost: its slot is
    /// released and the role falls back to `.disconnected` (BLE.md §6.1).
    static let maxReconnectAttempts = 10
}

// MARK: - Measurement parsing

extension BLECSCClient {
    /// Decoded CSC Measurement (0x2A5B) payload. Wheel and crank fields are present
    /// independently per the flags byte, so a sensor may report one, both, or
    /// neither. See BLE.md §5.2.
    struct Measurement: Equatable, Sendable {
        var cumulativeWheelRevolutions: UInt32?
        var lastWheelEventTime: UInt16?         // 1/1024 s units
        var cumulativeCrankRevolutions: UInt16?
        var lastCrankEventTime: UInt16?         // 1/1024 s units

        /// Returns nil for malformed payloads (drop the notification).
        init?(data: Data) {
            // Index from a copied byte array — Data slices need not be zero-based.
            let bytes = [UInt8](data)
            guard let flags = bytes.first else { return nil }
            let hasWheelData = flags & 0x01 != 0
            let hasCrankData = flags & 0x02 != 0
            var offset = 1

            if hasWheelData {
                guard bytes.count >= offset + 6 else { return nil }
                cumulativeWheelRevolutions =
                    UInt32(bytes[offset])
                    | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 24
                lastWheelEventTime = UInt16(bytes[offset + 4]) | UInt16(bytes[offset + 5]) << 8
                offset += 6
            }

            if hasCrankData {
                guard bytes.count >= offset + 4 else { return nil }
                cumulativeCrankRevolutions = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                lastCrankEventTime = UInt16(bytes[offset + 2]) | UInt16(bytes[offset + 3]) << 8
            }
        }
    }
}

// MARK: - Calculator

/// Derives a revolution rate (revs/second) from successive cumulative-count samples.
/// One instance per role: the wheel calculator (`Revs == UInt32`) drives speed, the
/// crank calculator (`Revs == UInt16`) drives cadence. See BLE.md §5.3.
///
/// Returns `nil` for "no emission" (priming, glitches, sub-threshold duplicates) and
/// `0` once the wheel/crank is confirmed stopped. The caller scales the rate into
/// m/s (× circumference) or rpm (× 60).
struct CSCCalculator<Revs: FixedWidthInteger & UnsignedInteger & Sendable>: Sendable {
    /// Plausibility cap. A backwards counter (sensor reset/replacement) wraps to a
    /// huge positive delta; anything above this is rejected and re-primes the state.
    let maxRevsPerSecond: Double

    private var previous: (revs: Revs, time: UInt16)?
    private var duplicateCount = 0

    /// Consecutive unchanged samples before emitting 0. Sensors notify ~1 Hz; the
    /// threshold stops slow pedalling from flickering to zero between strokes.
    private static var zeroThreshold: Int { 3 }

    init(maxRevsPerSecond: Double) {
        self.maxRevsPerSecond = maxRevsPerSecond
    }

    /// Discard accumulated state. Called on disconnect so a stale sample from before
    /// the gap can't produce a bogus rate after reconnection.
    mutating func reset() {
        previous = nil
        duplicateCount = 0
    }

    mutating func update(revs: Revs, eventTime: UInt16) -> Double? {
        guard let prev = previous else {
            previous = (revs, eventTime)   // prime; no rate from a single sample
            return nil
        }

        // Wrapping subtraction handles 16/32-bit counter rollover via modular
        // arithmetic — no explicit max-value conditional needed.
        let revDelta = revs &- prev.revs
        let timeDelta = eventTime &- prev.time

        if revDelta == 0 {
            // Unchanged counter: wheel/crank stopped. Emit 0 only after a few
            // duplicates so a slow cadence doesn't read zero between strokes.
            duplicateCount += 1
            return duplicateCount >= Self.zeroThreshold ? 0 : nil
        }

        if timeDelta == 0 {
            // Revolutions advanced but event time didn't — a glitch. Drop without
            // updating state so the next valid pair averages across the gap.
            return nil
        }

        // First moving sample after a confirmed stop: the pre-stop event time (16-bit,
        // wraps every 64s) makes this delta meaningless. Re-prime and skip one sample.
        if duplicateCount >= Self.zeroThreshold {
            previous = (revs, eventTime)
            duplicateCount = 0
            return nil
        }

        let rps = Double(revDelta) / (Double(timeDelta) / 1024.0)
        previous = (revs, eventTime)
        duplicateCount = 0
        guard rps <= maxRevsPerSecond else { return nil }   // reset spike — re-primed above
        return rps
    }
}

// MARK: - DependencyKey

extension BLECSCClient: DependencyKey {
    /// Factory with injectable transport and clock so tests can drive BLE events
    /// and control reconnect-backoff time deterministically.
    static func live(bleClient: BLEClient, clock: any Clock<Duration>) -> BLECSCClient {
        let state = CSCClientState(bleClient: bleClient, clock: clock)
        return BLECSCClient(
            startScanning:         { await state.startScanning() },
            stopScanning:          { await state.stopScanning() },
            connect:               { id, roles in await state.connect(peripheralID: id, roles: roles) },
            disconnect:            { await state.disconnect() },
            setWheelCircumference: { mm in await state.setWheelCircumference(mm) },
            speed:                 { state.makeSpeedStream() },
            cadence:               { state.makeCadenceStream() },
            connectionState:       { role in state.makeConnectionStateStream(role: role) },
            sensorName:            { role in state.makeSensorNameStream(role: role) }
        )
    }

    static let liveValue = BLECSCClient.live(bleClient: .liveValue, clock: ContinuousClock())

    static let testValue = BLECSCClient(
        startScanning:         { },
        stopScanning:          { },
        connect:               { _, _ in },
        disconnect:            { },
        setWheelCircumference: { _ in },
        speed:                 { AsyncStream { $0.finish() } },
        cadence:               { AsyncStream { $0.finish() } },
        connectionState:       { _ in AsyncStream { $0.finish() } },
        sensorName:            { _ in AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var bleCSCClient: BLECSCClient {
        get { self[BLECSCClient.self] }
        set { self[BLECSCClient.self] = newValue }
    }
}

// MARK: - Live implementation

/// Manages CSC connection lifecycle across up to two peripherals (one per role),
/// reconnecting each independently with exponential backoff on unexpected drop.
/// Follows the same @unchecked Sendable + NSLock pattern as BLECentral / RadarClientState.
private final class CSCClientState: @unchecked Sendable {

    /// Per-peripheral connection and calculator state. A peripheral may hold one or
    /// both roles; its calculators only consume the fields for the roles it holds.
    private struct Slot {
        var roles: Set<BLECSCClient.SensorRole>
        var connectionState: BLECSCClient.ConnectionState = .connecting
        var name: String?
        var wheel = CSCCalculator<UInt32>(maxRevsPerSecond: 15)   // ~120 km/h on a 700c wheel
        var crank = CSCCalculator<UInt16>(maxRevsPerSecond: 5)    // 300 rpm
        var reconnectTask: Task<Void, Never>?
        /// True only for a role assignment guessed by the discovery auto-connect
        /// heuristic (as opposed to an explicit `connect(peripheralID:roles:)` call,
        /// e.g. from a future pairing UI) — only these are eligible for capability
        /// narrowing once real data reveals what the sensor actually supports.
        var isAutoAssigned = false
        /// Whether this slot's real wheel/crank capability has been inferred yet
        /// from a measurement's flags (auto-assigned slots only) — see the
        /// narrowing logic in `.characteristicValueUpdated` handling.
        var capabilitiesKnown = false
    }

    private let bleClient: BLEClient
    private let clock: any Clock<Duration>

    private var slots: [UUID: Slot] = [:]   // ≤ 2 entries in practice
    private var isScanning = false
    private var wheelCircumferenceMM = defaultWheelCircumferenceMM
    private var roleState: [BLECSCClient.SensorRole: BLECSCClient.ConnectionState] = [
        .speed: .disconnected, .cadence: .disconnected,
    ]
    /// Advertised names seen via `.discovered`, keyed by peripheral — looked up when
    /// a `Slot` is created so a sensor's name survives even though `connect()` (the
    /// public entry point, also usable by a future pairing UI) doesn't take one.
    private var discoveredNames: [UUID: String] = [:]
    /// CSC peripherals seen via `.discovered` that don't currently hold a role.
    /// Retained because CoreBluetooth won't redeliver a `.discovered` event for a
    /// peripheral already seen this scan session — without this, a sensor seen
    /// before a role frees up (e.g. a dedicated speed sensor's first measurement
    /// reveals it doesn't actually report crank data) would be lost for good.
    private var pendingPeripherals: [UUID] = []

    private var speedContinuations: [Int: AsyncStream<Double>.Continuation] = [:]
    private var cadenceContinuations: [Int: AsyncStream<Double>.Continuation] = [:]
    private var stateContinuations: [Int: (role: BLECSCClient.SensorRole, continuation: AsyncStream<BLECSCClient.ConnectionState>.Continuation)] = [:]
    private var nameContinuations: [Int: (role: BLECSCClient.SensorRole, continuation: AsyncStream<String?>.Continuation)] = [:]
    private var nextID = 0
    private let lock = NSLock()

    init(bleClient: BLEClient, clock: any Clock<Duration>) {
        self.bleClient = bleClient
        self.clock = clock
        startEventLoop()
    }

    // MARK: Subscriber streams

    func makeSpeedStream() -> AsyncStream<Double> {
        let id = lock.withLock { () -> Int in let current = nextID; nextID += 1; return current }
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        lock.withLock { speedContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.speedContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeCadenceStream() -> AsyncStream<Double> {
        let id = lock.withLock { () -> Int in let current = nextID; nextID += 1; return current }
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        lock.withLock { cadenceContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.cadenceContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeConnectionStateStream(role: BLECSCClient.SensorRole) -> AsyncStream<BLECSCClient.ConnectionState> {
        let id = lock.withLock { () -> Int in let current = nextID; nextID += 1; return current }
        let (stream, continuation) = AsyncStream<BLECSCClient.ConnectionState>.makeStream()
        // Replay current state so late subscribers see truth immediately. Replay and
        // registration happen in one critical section so no transition can slip
        // between the replayed value and this continuation joining the broadcast set.
        lock.withLock {
            continuation.yield(roleState[role] ?? .disconnected)
            stateContinuations[id] = (role, continuation)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.stateContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeSensorNameStream(role: BLECSCClient.SensorRole) -> AsyncStream<String?> {
        let id = lock.withLock { () -> Int in let current = nextID; nextID += 1; return current }
        let (stream, continuation) = AsyncStream<String?>.makeStream()
        lock.withLock {
            continuation.yield(nameForRoleLocked(role))
            nameContinuations[id] = (role, continuation)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.nameContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    /// Must be called with the lock held.
    private func nameForRoleLocked(_ role: BLECSCClient.SensorRole) -> String? {
        slots.values.first(where: { $0.roles.contains(role) })?.name
    }

    // MARK: Public control

    func startScanning() async {
        // Only start a fresh scan from a cold state. Re-entering (a feature's .task
        // re-running on view re-appear, while this object is process-global) must
        // not stomp live connections back to .scanning.
        let shouldScan = lock.withLock { () -> Bool in
            guard slots.isEmpty, !isScanning else { return false }
            isScanning = true
            recomputeRoleStatesLocked()
            return true
        }
        guard shouldScan else {
            logger.info("startScanning skipped — not in cold state")
            return
        }
        await bleClient.startScanning([cscServiceUUID])
    }

    func stopScanning() async {
        lock.withLock {
            isScanning = false
            recomputeRoleStatesLocked()
        }
        await bleClient.stopScanning([cscServiceUUID])
    }

    /// `speculative` marks the assignment as a discovery-time guess, eligible for
    /// later capability narrowing (see `Slot.isAutoAssigned`). The public dependency
    /// closure always calls this with the default `false` — only the internal
    /// auto-discovery path (`claimUnfilledRoles`) passes `true`.
    func connect(peripheralID: UUID, roles: Set<BLECSCClient.SensorRole>, speculative: Bool = false) async {
        let toDisconnect: [UUID] = lock.withLock {
            var removed: [UUID] = []
            // Reassign the requested roles away from any other peripheral holding them.
            for (id, var slot) in slots where id != peripheralID {
                let before = slot.roles
                slot.roles.subtract(roles)
                guard slot.roles != before else { continue }
                if slot.roles.isEmpty {
                    slot.reconnectTask?.cancel()
                    slots.removeValue(forKey: id)
                    removed.append(id)
                } else {
                    // The slot keeps another role, so it survives — but the stripped
                    // role's calculator would otherwise retain its pre-reassignment
                    // sample and compute a bogus rate if the role is later returned.
                    let stripped = before.subtracting(slot.roles)
                    if stripped.contains(.speed) { slot.wheel.reset() }
                    if stripped.contains(.cadence) { slot.crank.reset() }
                    slots[id] = slot
                }
            }
            // Upsert the target peripheral with the requested roles. An explicit
            // (non-speculative) call always marks the slot authoritative, even if it
            // was previously auto-assigned — a real pairing decision overrides a guess.
            if var slot = slots[peripheralID] {
                slot.roles.formUnion(roles)
                if !speculative { slot.isAutoAssigned = false }
                slots[peripheralID] = slot
            } else {
                slots[peripheralID] = Slot(
                    roles: roles, name: discoveredNames[peripheralID], isAutoAssigned: speculative
                )
            }
            recomputeRoleStatesLocked()
            return removed
        }
        for id in toDisconnect { await bleClient.disconnect(id, cscOwnerID) }
        await bleClient.connect(peripheralID, cscOwnerID)
        logger.notice("connect requested for \(peripheralID, privacy: .public) roles \(String(describing: roles), privacy: .public)")
    }

    /// Speculatively connects a CSC peripheral to whichever roles no current slot
    /// fulfils. `candidate` (if given) is queued if no role is free yet. Also called
    /// with `candidate: nil` after a slot's capabilities narrow, so a peripheral
    /// queued earlier can claim a role that just freed up without a fresh discovery.
    private func claimUnfilledRoles(candidate: UUID?) async {
        let next: (id: UUID, roles: Set<BLECSCClient.SensorRole>)? = lock.withLock {
            if let candidate, slots[candidate] == nil, !pendingPeripherals.contains(candidate) {
                pendingPeripherals.append(candidate)
            }
            while let first = pendingPeripherals.first, slots[first] != nil {
                pendingPeripherals.removeFirst()
            }
            let unfilled = Set(BLECSCClient.SensorRole.allCases)
                .subtracting(slots.values.flatMap(\.roles))
            guard !unfilled.isEmpty, !pendingPeripherals.isEmpty else { return nil }
            return (pendingPeripherals.removeFirst(), unfilled)
        }
        guard let next else { return }
        await connect(peripheralID: next.id, roles: next.roles, speculative: true)
    }

    func disconnect() async {
        let ids: [UUID] = lock.withLock {
            for slot in slots.values { slot.reconnectTask?.cancel() }
            let ids = Array(slots.keys)
            slots.removeAll()
            pendingPeripherals.removeAll()
            isScanning = false
            recomputeRoleStatesLocked()
            return ids
        }
        for id in ids { await bleClient.disconnect(id, cscOwnerID) }
        await bleClient.stopScanning([cscServiceUUID])
    }

    func setWheelCircumference(_ mm: Int) async {
        lock.withLock { wheelCircumferenceMM = mm }
        logger.notice("wheel circumference → \(mm)mm")
    }

    // MARK: Event loop

    private func startEventLoop() {
        Task { [weak self] in
            guard let self else { return }
            for await event in bleClient.events() {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: BLEEvent) async {
        switch event {
        case .discovered(let id, let name, _, let services):
            // Auto-connect discovered CSC sensors to whichever roles aren't already
            // fulfilled — keeps the dashboard usable before M6's pairing UI exists.
            // The shared central may be scanning several sensor types, so filter on
            // the service. See `claimUnfilledRoles` for how a second (or third)
            // sensor claims a role the first one turns out not to actually support.
            guard services.contains(cscServiceUUID) else { return }
            if let name { lock.withLock { discoveredNames[id] = name } }
            await claimUnfilledRoles(candidate: id)

        case .connected(let id):
            guard lock.withLock({ slots[id] != nil }) else { return }
            lock.withLock {
                slots[id]?.reconnectTask?.cancel()
                slots[id]?.reconnectTask = nil
                slots[id]?.connectionState = .connected
                recomputeRoleStatesLocked()
            }
            await bleClient.discoverServices(id, [cscServiceUUID])

        case .servicesDiscovered(let id, let uuids):
            guard lock.withLock({ slots[id] != nil }),
                  uuids.contains(cscServiceUUID) else { return }
            await bleClient.discoverCharacteristics(id, cscServiceUUID, [cscMeasurementUUID])

        case .characteristicsDiscovered(let id, let serviceUUID, let uuids):
            guard lock.withLock({ slots[id] != nil }),
                  serviceUUID == cscServiceUUID,
                  uuids.contains(cscMeasurementUUID) else { return }
            await bleClient.setNotifyValue(true, id, cscServiceUUID, cscMeasurementUUID)
            lock.withLock {
                slots[id]?.connectionState = .active
                recomputeRoleStatesLocked()
            }

        case .characteristicValueUpdated(let id, let charUUID, let data):
            guard charUUID == cscMeasurementUUID else { return }
            guard let measurement = BLECSCClient.Measurement(data: data) else {
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                logger.notice("csc frame [\(hex, privacy: .public)] → parse FAILED")
                return
            }
            // Role gating: feed wheel data to the calculator only if this peripheral
            // holds the speed role, crank data only if it holds cadence. This is what
            // lets a combo sensor be used for cadence only while a dedicated sensor
            // supplies speed. Compute under the lock to keep calculator state and the
            // circumference read consistent.
            var freedRole = false
            var emptiedSlot = false
            let (speedVal, cadenceVal): (Double?, Double?) = lock.withLock {
                guard var slot = slots[id] else { return (nil, nil) }
                // Auto-assigned roles are a discovery-time guess; the first real
                // measurement reveals what the sensor actually reports, so narrow the
                // guess down to that. Explicit (pairing-UI) assignments are never
                // second-guessed. A role the sensor doesn't support is freed for
                // another discovered peripheral to claim (`claimUnfilledRoles`).
                if slot.isAutoAssigned, !slot.capabilitiesKnown {
                    var supported: Set<BLECSCClient.SensorRole> = []
                    if measurement.cumulativeWheelRevolutions != nil { supported.insert(.speed) }
                    if measurement.cumulativeCrankRevolutions != nil { supported.insert(.cadence) }
                    let unsupported = slot.roles.subtracting(supported)
                    if !unsupported.isEmpty {
                        slot.roles.subtract(unsupported)
                        freedRole = true
                        logger.notice("\(id, privacy: .public) doesn't support \(String(describing: unsupported), privacy: .public) — role freed")
                    }
                    slot.capabilitiesKnown = true
                }
                var s: Double?
                var c: Double?
                if slot.roles.contains(.speed),
                   let revs = measurement.cumulativeWheelRevolutions,
                   let time = measurement.lastWheelEventTime,
                   let rps = slot.wheel.update(revs: revs, eventTime: time) {
                    s = rps * Double(wheelCircumferenceMM) / 1000.0
                }
                if slot.roles.contains(.cadence),
                   let revs = measurement.cumulativeCrankRevolutions,
                   let time = measurement.lastCrankEventTime,
                   let rps = slot.crank.update(revs: revs, eventTime: time) {
                    c = rps * 60.0
                }
                if slot.roles.isEmpty {
                    slots.removeValue(forKey: id)
                    emptiedSlot = true
                } else {
                    slots[id] = slot   // write back mutated calculator state
                }
                if freedRole { recomputeRoleStatesLocked() }
                return (s, c)
            }
            if let speedVal {
                broadcastSpeed(speedVal)
                logger.info("speed \(speedVal, format: .fixed(precision: 2)) m/s")
            }
            if let cadenceVal {
                broadcastCadence(cadenceVal)
                logger.info("cadence \(cadenceVal, format: .fixed(precision: 0)) rpm")
            }
            if emptiedSlot { await bleClient.disconnect(id, cscOwnerID) }
            if freedRole { await claimUnfilledRoles(candidate: nil) }

        case .disconnected(let id, _):
            // Only unexpected disconnects match — user disconnect() removes the slot first.
            let wasTarget = lock.withLock { () -> Bool in
                guard slots[id] != nil else { return false }
                slots[id]?.connectionState = .reconnecting
                // Reset calculators: a sample from before the gap would yield a bogus
                // rate against the first post-reconnect sample.
                slots[id]?.wheel.reset()
                slots[id]?.crank.reset()
                recomputeRoleStatesLocked()
                return true
            }
            guard wasTarget else { return }
            startReconnect(peripheralID: id)

        case .stateChanged(let managerState):
            switch managerState {
            case .poweredOff, .unauthorized, .unsupported:
                // Permission denied / radio off: stand down cleanly, never crash.
                lock.withLock {
                    for slot in slots.values { slot.reconnectTask?.cancel() }
                    slots.removeAll()
                    pendingPeripherals.removeAll()
                    isScanning = false
                    recomputeRoleStatesLocked()
                }
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: Reconnection

    private func startReconnect(peripheralID: UUID) {
        // On iOS the original connect() request stays pending and completes whenever
        // the peripheral reappears; re-issuing connect() is an idempotent nudge,
        // bounded by the BLE.md §6.1 ladder. BLECentral retains discovered
        // peripherals, so reconnect-by-UUID works without rescanning.
        let task = Task { [weak self] in
            for attempt in 0..<BLECSCClient.maxReconnectAttempts {
                guard let self else { return }
                try? await self.clock.sleep(for: BLECSCClient.reconnectDelay(attempt: attempt))
                guard !Task.isCancelled else { return }
                let stillReconnecting = self.lock.withLock {
                    self.slots[peripheralID]?.connectionState == .reconnecting
                }
                guard stillReconnecting else { return }
                logger.notice("reconnect attempt \(attempt + 1) for \(peripheralID, privacy: .public)")
                await self.bleClient.connect(peripheralID, cscOwnerID)
            }
            // Ladder exhausted — give up and release the slot so the role falls back
            // to .disconnected (BLE.md §6.1). Guard that we're still reconnecting so a
            // late success (which cancels this task) isn't undone.
            guard let self else { return }
            self.lock.withLock {
                guard self.slots[peripheralID]?.connectionState == .reconnecting else { return }
                self.slots.removeValue(forKey: peripheralID)
                self.recomputeRoleStatesLocked()
            }
            logger.notice("reconnect gave up for \(peripheralID, privacy: .public) — sensor lost")
        }
        lock.withLock {
            slots[peripheralID]?.reconnectTask?.cancel()
            slots[peripheralID]?.reconnectTask = task
        }
    }

    // MARK: Broadcast helpers

    /// Recompute each role's published state from the slots and broadcast changes.
    /// A role's state is the state of the peripheral holding it; an unheld role is
    /// `.scanning` while scanning, else `.disconnected`. Must be called with the lock held.
    private func recomputeRoleStatesLocked() {
        for role in [BLECSCClient.SensorRole.speed, .cadence] {
            let slot = slots.values.first(where: { $0.roles.contains(role) })
            let newState: BLECSCClient.ConnectionState = slot?.connectionState ?? (isScanning ? .scanning : .disconnected)

            if roleState[role] != newState {
                roleState[role] = newState
                for entry in stateContinuations.values where entry.role == role {
                    entry.continuation.yield(newState)
                }
                logger.notice("\(String(describing: role), privacy: .public) state → \(String(describing: newState), privacy: .public)")
            }

            // Broadcast unconditionally (unlike state above) — recompute only runs on
            // discrete lifecycle events, not per-notification, so this isn't hot-path.
            for entry in nameContinuations.values where entry.role == role {
                entry.continuation.yield(slot?.name)
            }
        }
    }

    private func broadcastSpeed(_ speed: Double) {
        let active = lock.withLock { Array(speedContinuations.values) }
        for continuation in active { continuation.yield(speed) }
    }

    private func broadcastCadence(_ cadence: Double) {
        let active = lock.withLock { Array(cadenceContinuations.values) }
        for continuation in active { continuation.yield(cadence) }
    }
}
