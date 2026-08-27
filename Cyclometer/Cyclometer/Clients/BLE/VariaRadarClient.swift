import ComposableArchitecture
import CoreBluetooth
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
// Retrieve after an untethered ride: `log collect --device --last 1h` (notice level persists).
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "radar")

// Identifies this client to BLEClient's connection ref-count so disconnecting the
// radar never severs a peripheral another client shares (see BLEClient.connect).
private let radarOwnerID = "radar"

// radarServiceUUID matched Garmin's assumed numbering on the first RTL15451 tested
// against; radarAlertUUID and radarCapabilityUUID did not (confirmed against real
// hardware — see the "characteristics discovered" log from that session) and are
// corrected here. parseAlert's payload layout is now confirmed too, against a real
// vehicle pass on that same hardware — see parseAlert's doc comment.
private let radarServiceUUID    = CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
private let radarAlertUUID      = CBUUID(string: "6A4E3203-667B-11E3-949A-0800200C9A66")  // notify
// Read-only capability characteristic. `BLEClient.readValue` can fetch it now, but
// its payload is unvalidated until the developer-program application lands and no
// acceptance criterion needs it.
private let radarCapabilityUUID = CBUUID(string: "6A4E3205-667B-11E3-949A-0800200C9A66")

// MARK: - VariaRadarClient

/// TCA dependency for Garmin Varia RTL515 / RCT715 radar data over raw BLE.
/// Protocol: Garmin Radar Data BLE Program.
/// Reference: pycycling RDR module (open-source Python implementation).
/// Note: RearVue 820 excluded — secured BLE protocol.
/// Uses BLEClient as the CoreBluetooth transport.
struct VariaRadarClient: Sendable {
    /// Connection lifecycle, per PRD §9.1 state machine. `.active` means
    /// notifications are enabled and radar data is flowing.
    ///
    /// The enum itself moved to `Models/SensorConnectionState.swift` in #98, where
    /// `DiscoveredDevice` — shared with CSC and HR — could refer to it. It was already
    /// character-identical to `BLECSCClient.ConnectionState`; both keep the typealias so
    /// every existing call site and stream reads unchanged.
    typealias ConnectionState = SensorConnectionState

    /// Scan for radars and reconnect the one the rider has paired. Nothing is adopted
    /// speculatively: a peripheral is connected only if `setPairedSensor` has named it,
    /// so an unknown radar advertising nearby is listed and ignored (BLE.md §6).
    var startScanning:   @Sendable () async -> Void
    var stopScanning:    @Sendable () async -> Void
    var connect:         @Sendable (UUID) async -> Void   // explicit device selection (future settings UI)
    /// Stop using the radar for now; the pairing survives. This is what ride finish
    /// calls — contrast `setPairedSensor(nil)`, which forgets the radar entirely.
    var disconnect:      @Sendable () async -> Void
    /// The rider's durable radar pairing, or nil when none. The client holds no
    /// persistence; `AppPreferences` owns the record and pushes it here at launch and on
    /// every change, the same way wheel circumference is pushed to the CSC client. Only
    /// this peripheral is connected on discovery.
    ///
    /// Passing nil — or a different peripheral — tears the current connection down in
    /// the same call. The gate and the connection identity move in one critical section,
    /// so BLE.md §5.0's "records before teardown" holds without the caller having to
    /// order two calls. `BLECSCClient` needs the separate `unpair` only because its map
    /// covers several peripherals and one can shed a role yet stay connected; a
    /// single-slot client has no such ambiguity.
    var setPairedSensor: @Sendable (UUID?) async -> Void
    /// Every radar seen this session, paired or not. Replays on subscribe.
    var discoveredDevices: @Sendable () -> AsyncStream<[DiscoveredDevice]>
    /// Scan on behalf of the pairing UI. Refcounted and independent of the ambient
    /// dashboard scan, so it still scans while the radar is connected — unlike
    /// `startScanning`, which only starts from a cold state. Mirrors
    /// `BLECSCClient.beginPairingScan` (#68); the Sensors screen holds one of these
    /// open per client for as long as it is on screen (#98).
    var beginPairingScan: @Sendable () async -> Void
    /// Balance a `beginPairingScan`. The hardware scan stops only when no pairing
    /// scan and no ambient scan remain — `BLEClient.requestedServices` is a plain set
    /// with no per-caller refcount, so whoever releases last has to be the one to
    /// release the radio.
    var endPairingScan: @Sendable () async -> Void
    var radarTargets:    @Sendable () -> AsyncStream<[RadarTarget]>
    var connectionState: @Sendable () -> AsyncStream<ConnectionState>
    /// Battery percentage of the connected radar, or `nil` when unknown — nothing
    /// connected, or a unit that doesn't expose the Battery Service. Replays the
    /// current value on subscribe.
    var batteryLevel:    @Sendable () -> AsyncStream<Int?>

    /// Parse vehicle targets from a Radar Alert characteristic value.
    ///
    /// Confirmed against real RTL15451 hardware — a school bus pass captured on
    /// 2026-08-25 produced a 4-byte payload with a steadily counting-down range
    /// byte, matching this layout exactly — and cross-checked against pycycling's
    /// independent reverse-engineering of the same characteristic (rear_view_radar.py):
    /// - byte 0: packet/sequence identifier, not vehicle data — ignored
    /// - per threat, 3 bytes: threat ID (ignored; `vehicleSlotIDs[i]` gives stable
    ///   identity instead — see its doc comment), uint8 range in whole metres,
    ///   uint8 closing speed in whole km/h
    ///
    /// No byte carries an alert level. `RadarTarget.ThreatLevel` is derived from
    /// closing speed instead, reusing `AlertLevel.dangerClosingSpeedKPH` so the
    /// per-vehicle dot and the ride-level escalation agree on what "danger" means.
    /// `.allClear` is intentionally never produced here — a vehicle only appears in
    /// this payload while it's being tracked as a threat, so "no threats" is an
    /// empty array rather than a `.allClear`-tagged one. `RadarTarget.ThreatLevel`
    /// keeps the case anyway: it's still constructible directly (previews, tests)
    /// and PRD §8.2/UX.md describe it as a real per-vehicle dot state, so removing
    /// it would be a model change beyond what this parser needs to make.
    ///
    /// The exact `1 + 3n` length is required — a payload with a stray trailing
    /// byte is dropped whole rather than parsed up to the misalignment. Only one
    /// real hardware capture (a single-vehicle frame) has validated this layout;
    /// silently tolerating an unexplained extra byte would risk exactly the kind
    /// of unverified guess this file's header comment already disavows. A rejected
    /// frame is loud (logged with its raw hex below) rather than quietly wrong.
    ///
    /// Returns nil for malformed payloads (drop the notification, keep last good state).
    static func parseAlert(from data: Data) -> [RadarTarget]? {
        guard !data.isEmpty, (data.count - 1).isMultiple(of: 3) else { return nil }
        let count = (data.count - 1) / 3
        guard count <= vehicleSlotIDs.count else { return nil }

        return (0..<count).map { i in
            let base = 1 + i * 3
            let closingSpeedKPH = Double(data[base + 2])
            return RadarTarget(
                id: vehicleSlotIDs[i],
                relativeVelocityMPS: closingSpeedKPH / AlertLevel.kphPerMPS,
                rangeMetres: Double(data[base + 1]),
                threatLevel: closingSpeedKPH >= AlertLevel.dangerClosingSpeedKPH ? .danger : .warning
            )
        }
    }

    /// Fixed slot UUIDs so vehicle identity is stable across notifications —
    /// preserves SwiftUI glyph identity for position animation and makes
    /// parse output deterministic for tests.
    static let vehicleSlotIDs: [UUID] = [
        UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000003")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000004")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000005")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000006")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000007")!,
        UUID(uuidString: "C0000000-0000-0000-0000-000000000008")!,
    ]

    /// Reconnection backoff ladder: 1s, 2s, 4s, 8s, 16s, then capped at 30s.
    static func reconnectDelay(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 5), 30))
    }
}

// MARK: - DependencyKey

extension VariaRadarClient: DependencyKey {
    /// Factory with injectable transport and clock so tests can drive BLE events
    /// and control reconnect-backoff time deterministically.
    static func live(bleClient: BLEClient, clock: any Clock<Duration>) -> VariaRadarClient {
        let state = RadarClientState(bleClient: bleClient, clock: clock)
        return VariaRadarClient(
            startScanning:     { await state.startScanning() },
            stopScanning:      { await state.stopScanning() },
            connect:           { id in await state.connect(peripheralID: id) },
            disconnect:        { await state.disconnect() },
            setPairedSensor:   { id in await state.setPairedSensor(id) },
            discoveredDevices: { state.makeDiscoveredDevicesStream() },
            beginPairingScan:  { await state.beginPairingScan() },
            endPairingScan:    { await state.endPairingScan() },
            radarTargets:    { state.makeTargetsStream() },
            connectionState: { state.makeConnectionStateStream() },
            batteryLevel:    { state.makeBatteryStream() }
        )
    }

    static let liveValue = VariaRadarClient.live(bleClient: .liveValue, clock: ContinuousClock())

    static let testValue = VariaRadarClient(
        startScanning:     { },
        stopScanning:      { },
        connect:           { _ in },
        disconnect:        { },
        setPairedSensor:   { _ in },
        discoveredDevices: { AsyncStream { $0.finish() } },
        beginPairingScan:  { },
        endPairingScan:    { },
        radarTargets:    { AsyncStream { $0.finish() } },
        connectionState: { AsyncStream { $0.finish() } },
        batteryLevel:    { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var variaRadarClient: VariaRadarClient {
        get { self[VariaRadarClient.self] }
        set { self[VariaRadarClient.self] = newValue }
    }
}

// MARK: - Live implementation

/// Manages the BLE connection lifecycle for a single Varia radar peripheral,
/// including reconnection with exponential backoff on unexpected disconnect.
/// Follows the same @unchecked Sendable + NSLock pattern as BLECentral / HRClientState.
private final class RadarClientState: @unchecked Sendable {
    private let bleClient: BLEClient
    private let clock: any Clock<Duration>

    /// Who we are currently talking to. Cleared by `disconnect()` and by `.stateChanged`
    /// so the `.disconnected` event that follows can't match and start a reconnect.
    private var targetPeripheralID: UUID?
    /// The rider's durable pairing, and the entire basis on which `.discovered` decides
    /// whether to connect. Deliberately *not* the same field as `targetPeripheralID`:
    /// ride finish calls `disconnect()`, which clears the connection identity, and a
    /// pairing that died with it would never reconnect for the next ride.
    private var pairedPeripheralID: UUID?
    private var connectionState: VariaRadarClient.ConnectionState = .disconnected
    private var batteryPercent: Int?
    private var reconnectTask: Task<Void, Never>?

    /// An ambient (dashboard) scan is running. Tracked separately from
    /// `connectionState` because a pairing scan must not move that state — see
    /// `beginPairingScan`.
    private var isScanning = false
    /// How many pairing scans are open. Deliberately not folded into `isScanning`:
    /// the two answer different questions, and only their sum decides whether the
    /// radio may be released. Mirrors `BLECSCClient.pairingScanCount`.
    private var pairingScanCount = 0

    /// Every radar seen this session. The inventory the pairing list is built from, and
    /// what lets `setPairedSensor` connect a device discovered before it was paired —
    /// CoreBluetooth won't redeliver `.discovered` for a peripheral already seen.
    private var discoveredIDs: Set<UUID> = []
    /// Peripherals that have advertised since the current scan generation began.
    ///
    /// CoreBluetooth reports a peripheral once per scan session, so "still there" can
    /// only be re-established by restarting the session — which `beginPairingScan`
    /// already does. Each restart rotates the generation: whatever failed to re-report
    /// during the one just ended is gone and leaves the list (#98 follow-up).
    private var sightedThisGeneration: Set<UUID> = []
    /// Separate from `discoveredIDs` because a nil name can't be stored in a dictionary,
    /// and an unnamed radar still needs a row.
    private var discoveredNames: [UUID: String] = [:]

    private var targetsContinuations: [Int: AsyncStream<[RadarTarget]>.Continuation] = [:]
    private var stateContinuations: [Int: AsyncStream<VariaRadarClient.ConnectionState>.Continuation] = [:]
    private var batteryContinuations: [Int: AsyncStream<Int?>.Continuation] = [:]
    private var discoveredContinuations: [Int: AsyncStream<[DiscoveredDevice]>.Continuation] = [:]
    private var nextID = 0
    private let lock = NSLock()

    init(bleClient: BLEClient, clock: any Clock<Duration>) {
        self.bleClient = bleClient
        self.clock = clock
        startEventLoop()
    }

    // MARK: Subscriber streams

    func makeTargetsStream() -> AsyncStream<[RadarTarget]> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<[RadarTarget]>.makeStream()
        lock.withLock { targetsContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.targetsContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeConnectionStateStream() -> AsyncStream<VariaRadarClient.ConnectionState> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<VariaRadarClient.ConnectionState>.makeStream()
        // Replay current state so late subscribers (the feature's .task) see truth
        // immediately. Replay and registration happen in one critical section so
        // no transition can slip between the replayed value and this continuation
        // joining the broadcast set.
        lock.withLock {
            continuation.yield(connectionState)
            stateContinuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.stateContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeBatteryStream() -> AsyncStream<Int?> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<Int?>.makeStream()
        // Replay for the same reason the state stream does, and more urgently: battery
        // is read once per connection, so a subscriber arriving after that read would
        // otherwise wait until the next reconnect to learn anything.
        lock.withLock {
            continuation.yield(batteryPercent)
            batteryContinuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.batteryContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeDiscoveredDevicesStream() -> AsyncStream<[DiscoveredDevice]> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<[DiscoveredDevice]>.makeStream()
        // Replay + register in one critical section, same as the state streams. The
        // replay matters more here: CoreBluetooth won't redeliver `.discovered` for a
        // peripheral already seen this session, so a sheet opened after discovery would
        // otherwise show an empty list until something changed.
        lock.withLock {
            continuation.yield(discoveredDevicesLocked())
            discoveredContinuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.discoveredContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: Scanning

    func startScanning() async {
        // Only start a fresh scan from a cold state. Re-entering (the dashboard's
        // .task re-runs when the view re-appears, while this state object is
        // process-global) must not stomp a live connection back to .scanning.
        let shouldScan = lock.withLock { () -> Bool in
            guard connectionState == .disconnected else { return false }
            isScanning = true
            return true
        }
        guard shouldScan else {
            logger.info("startScanning skipped — not in disconnected state")
            return
        }
        setConnectionState(.scanning)
        await bleClient.startScanning([radarServiceUUID])
    }

    func stopScanning() async {
        let shouldStopHardware = lock.withLock { () -> Bool in
            isScanning = false
            return pairingScanCount == 0
        }
        // `BLEClient.requestedServices` is a plain set with no per-caller refcount, so
        // dropping the radar UUID here would cancel the Sensors screen's scan too.
        guard shouldStopHardware else {
            logger.info("stopScanning kept alive — \(self.pairingScanCountSnapshot) pairing scan(s) open")
            return
        }
        await bleClient.stopScanning([radarServiceUUID])
    }

    // MARK: Pairing UI support (S11)

    /// Scan on behalf of the pairing UI, bypassing `startScanning`'s cold-state guard —
    /// the rider must be able to look for a radar while one is already connected.
    /// Deliberately does not touch `connectionState`, so the ride sidebar doesn't flip
    /// to "Searching" behind a settings screen.
    func beginPairingScan() async {
        lock.withLock {
            pairingScanCount += 1
            rotateDiscoveryGenerationLocked()
        }
        // Re-issuing the scan restarts the CoreBluetooth session, so peripherals
        // already seen are re-advertised to us rather than suppressed as duplicates.
        // That is also what makes pull-to-refresh work (#98).
        await bleClient.startScanning([radarServiceUUID])
        logger.notice("pairing scan started (\(self.pairingScanCountSnapshot) open)")
    }

    func endPairingScan() async {
        let shouldStopHardware = lock.withLock { () -> Bool in
            pairingScanCount = max(0, pairingScanCount - 1)
            return pairingScanCount == 0 && !isScanning
        }
        guard shouldStopHardware else { return }
        await bleClient.stopScanning([radarServiceUUID])
        logger.notice("pairing scan stopped")
    }

    private var pairingScanCountSnapshot: Int { lock.withLock { pairingScanCount } }

    /// Close the current scan generation and drop whatever stopped advertising.
    ///
    /// The peripheral this client is connected to is exempt, and that exemption is the
    /// whole reason this can't just clear the inventory: **a connected peripheral stops
    /// advertising**. Sweeping it would delete the row for the very radar the rider is using.
    ///
    /// A paired-but-absent peripheral is *not* exempt — it has genuinely gone out of
    /// range, and `DeviceManagementFeature` rebuilds its row from the durable record so
    /// it stays listed and unpairable regardless.
    ///
    /// Must hold the lock.
    private func rotateDiscoveryGenerationLocked() {
        var stale = discoveredIDs.subtracting(sightedThisGeneration)
        if let targetPeripheralID { stale.remove(targetPeripheralID) }
        sightedThisGeneration = []
        guard !stale.isEmpty else { return }
        discoveredIDs.subtract(stale)
        for id in stale { discoveredNames.removeValue(forKey: id) }
        logger.notice("discovery sweep dropped \(stale.count) stale peripheral(s)")
        broadcastDiscoveredLocked()
    }

    // MARK: Connection control

    func connect(peripheralID: UUID) async {
        lock.withLock { targetPeripheralID = peripheralID }
        setConnectionState(.connecting)
        await bleClient.connect(peripheralID, radarOwnerID)
    }

    /// User-initiated disconnect: clears the target first so the resulting
    /// `.disconnected` BLE event won't match and trigger reconnection.
    func disconnect() async {
        cancelReconnect()
        // Read and clear atomically — a .disconnected event processed between a
        // separate read and clear would still match the target and start an
        // unwanted reconnect.
        let id = lock.withLock { () -> UUID? in
            let current = targetPeripheralID
            targetPeripheralID = nil
            return current
        }
        setConnectionState(.disconnected)
        // Same reason as the `.disconnected` branch: that branch can't run here,
        // because the target has already been cleared above.
        setBattery(nil)
        if let id {
            await bleClient.disconnect(id, radarOwnerID)
        }
        // Ride finish must not silently kill a pairing scan the Sensors screen is
        // holding open — same shared-`requestedServices` hazard as `stopScanning`.
        let shouldStopHardware = lock.withLock { () -> Bool in
            isScanning = false
            return pairingScanCount == 0
        }
        guard shouldStopHardware else { return }
        await bleClient.stopScanning([radarServiceUUID])
    }

    /// Cache the rider's durable pairing, tearing down whatever no longer matches it and
    /// connecting the new radar if it has already been seen this session.
    ///
    /// Deliberately does not start a scan. `BLEClient.connect` is a no-op for a
    /// peripheral CoreBluetooth hasn't discovered, so at launch this call only *arms*
    /// the gate; the reconnect happens on the next scan. Scanning from here would leave
    /// the radio running from launch to termination and paper over the real gap, which
    /// is state restoration plus retrieve-by-identifier (BLE.md §13, M7).
    func setPairedSensor(_ id: UUID?) async {
        // Outside the critical section below: it takes the lock.
        cancelReconnect()

        // The gate and the connection identity move together in one acquisition, so a
        // `.discovered` racing on the event-loop task sees either both old or both new
        // and can never act on an open gate with a stale target. The state broadcasts
        // and transport calls that follow are consequences, not inputs to that decision,
        // and every broadcast helper takes this same non-recursive lock anyway.
        let (toDisconnect, toConnect): (UUID?, UUID?) = lock.withLock {
            guard pairedPeripheralID != id else { return (nil, nil) }
            pairedPeripheralID = id

            // Both halves, not either/or: swapping A for B has to release A *and* pick
            // up B. Returning after the teardown would leave the rider's new radar
            // unconnected until it next advertised.
            var toDisconnect: UUID?
            if let current = targetPeripheralID, current != id {
                targetPeripheralID = nil
                toDisconnect = current
            }
            // The new radar is already in the session inventory: connect it now rather
            // than waiting for an advertisement that won't come.
            var toConnect: UUID?
            if let id, targetPeripheralID == nil, discoveredIDs.contains(id) {
                targetPeripheralID = id
                toConnect = id
            }
            broadcastDiscoveredLocked()
            return (toDisconnect, toConnect)
        }

        if let toDisconnect {
            setConnectionState(.disconnected)
            broadcastTargets([])   // clear stale vehicles from the sidebar
            setBattery(nil)
            await bleClient.disconnect(toDisconnect, radarOwnerID)
        }
        if let toConnect {
            setConnectionState(.connecting)
            await bleClient.connect(toConnect, radarOwnerID)
        }
        logger.notice("paired radar → \(id?.uuidString ?? "none", privacy: .public)")
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
        // Battery is a device concern, not a radar one — the shared handshake drives
        // its own discover → read and only ever claims 0x2A19 value updates.
        if let reading = await BatteryService.handle(event, bleClient: bleClient, owns: { [weak self] id in
            self?.lock.withLock { self?.targetPeripheralID } == id
        }) {
            setBattery(reading.level)
        }

        switch event {
        case .discovered(let id, let name, _, let services):
            // Reconnect only what the rider has paired. Nothing is adopted
            // speculatively: an unknown radar is listed for the pairing UI and otherwise
            // left alone, so a stranger's Varia at a group start can never take over the
            // sidebar. The shared central may be scanning several sensor types, so
            // filter on the service first.
            guard services.contains(radarServiceUUID) else { return }
            let (shouldConnect, firstSighting): (Bool, Bool) = lock.withLock {
                // Record every radar seen, named or not — the pairing list is built from
                // this inventory, and an unnamed unit still needs a row.
                let firstSighting = discoveredIDs.insert(id).inserted
                sightedThisGeneration.insert(id)
                if let name { discoveredNames[id] = name }
                broadcastDiscoveredLocked()
                // `targetPeripheralID == nil` is load-bearing, not defensive:
                // `BLECentral.rescan` re-issues the scan for the whole requested union,
                // which restarts the CoreBluetooth session and redelivers peripherals
                // every client has already seen — HR's `.disconnected` branch triggers
                // exactly that. Claiming the target here rather than in `connect` keeps
                // the check and the claim in one acquisition, so two redeliveries can't
                // both pass it.
                guard targetPeripheralID == nil, pairedPeripheralID == id else {
                    return (false, firstSighting)
                }
                targetPeripheralID = id
                return (true, firstSighting)
            }
            // Announce the gate's verdict, once per peripheral per scan session. Without
            // this an ignored radar is indistinguishable from one that never advertised:
            // before the gate existed, "connecting" was the only evidence discovery had
            // happened at all, and gating it away took the diagnostic with it.
            if firstSighting {
                logger.notice("""
                    discovered "\(name ?? "?", privacy: .public)" \(id, privacy: .public) — \
                    \(shouldConnect ? "paired, connecting" : "not paired, ignoring", privacy: .public)
                    """)
            }
            guard shouldConnect else { return }
            setConnectionState(.connecting)
            await bleClient.connect(id, radarOwnerID)

        case .connected(let id):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            cancelReconnect()
            setConnectionState(.connected)
            // One call for both services: didDiscoverServices reports the peripheral's
            // full service list, so a second call for 0x180F would re-fire the alert
            // characteristic's discover → notify chain.
            await bleClient.discoverServices(id, [radarServiceUUID, BatteryService.serviceUUID])

        case .servicesDiscovered(let id, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            // Both prior guard branches (wrong peripheral, service not reported) used
            // to return silently — if the radar service UUID (#18, unvalidated) is
            // wrong, this was the only place that would ever have shown it.
            logger.notice("services discovered on \(id, privacy: .public): \(uuids.map(\.uuidString).joined(separator: ", "), privacy: .public)")
            guard uuids.contains(radarServiceUUID) else {
                logger.notice("radar service \(radarServiceUUID.uuidString, privacy: .public) not in that list — characteristic discovery never starts")
                return
            }
            // Discover everything under the service rather than filtering to the
            // assumed alert UUID (#18, unvalidated) — CoreBluetooth silently returns
            // an empty list for a filtered discovery that matches nothing, which is
            // indistinguishable from "no characteristics at all" without this.
            await bleClient.discoverCharacteristics(id, radarServiceUUID, nil)

        case .characteristicsDiscovered(let id, let serviceUUID, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id,
                  serviceUUID == radarServiceUUID else { return }
            logger.notice("characteristics discovered on \(id, privacy: .public) for radar service: \(uuids.map(\.uuidString).joined(separator: ", "), privacy: .public)")
            guard uuids.contains(radarAlertUUID) else {
                logger.notice("radar alert characteristic \(radarAlertUUID.uuidString, privacy: .public) not in that list — notify never enabled")
                return
            }
            await bleClient.setNotifyValue(true, id, radarServiceUUID, radarAlertUUID)
            setConnectionState(.active)

        case .characteristicValueUpdated(let id, let charUUID, let data):
            guard lock.withLock({ targetPeripheralID }) == id,
                  charUUID == radarAlertUUID else { return }
            // Raw frame hex is the ground truth for validating the payload-layout
            // assumption in parseAlert — keep failed parses visible.
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            guard let targets = VariaRadarClient.parseAlert(from: data) else {
                logger.notice("alert frame [\(hex, privacy: .public)] → parse FAILED — layout assumption likely wrong")
                return
            }
            let summary = targets
                .map { "(\(Int($0.rangeMetres))m, \(Int($0.relativeVelocityMPS))m/s)" }
                .joined(separator: " ")
            logger.notice("alert frame [\(hex, privacy: .public)] → \(targets.count) target(s) \(summary, privacy: .public)")
            broadcastTargets(targets)

        case .disconnected(let id, _):
            // Only unexpected disconnects match — user disconnect() nils the target first.
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            broadcastTargets([])   // clear stale vehicles from the sidebar
            setBattery(nil)        // re-read on reconnect rather than show a stale level
            setConnectionState(.reconnecting)
            startReconnect()

        case .stateChanged(let managerState):
            switch managerState {
            case .poweredOff, .unauthorized, .unsupported:
                // Permission denied / radio off: stand down cleanly, never crash. The
                // pairing survives — the rider didn't unpair, the radio went off — so
                // only the connection identity is cleared.
                cancelReconnect()
                lock.withLock { targetPeripheralID = nil }
                broadcastTargets([])
                setBattery(nil)
                setConnectionState(.disconnected)
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: Reconnection

    private func startReconnect() {
        cancelReconnect()
        // On iOS the first connect() is a pending request that never times out
        // and completes whenever the peripheral reappears — that pending request,
        // not this ladder, is what usually restores the connection. Re-issuing
        // connect() is an idempotent nudge that matters when the pending request
        // was cleared (e.g. the radio cycled off and on); the PRD §9.1 ladder
        // bounds how often it is re-issued. BLECentral retains discovered
        // peripherals, so reconnect-by-UUID works without rescanning.
        let task = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.clock.sleep(for: VariaRadarClient.reconnectDelay(attempt: attempt))
                guard !Task.isCancelled else { return }
                guard let id = self.lock.withLock({ self.targetPeripheralID }) else { return }
                logger.notice("reconnect attempt \(attempt + 1)")
                await self.bleClient.connect(id, radarOwnerID)
                attempt += 1
            }
        }
        lock.withLock { reconnectTask = task }
    }

    private func cancelReconnect() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let current = reconnectTask
            reconnectTask = nil
            return current
        }
        task?.cancel()
    }

    // MARK: Broadcast helpers

    private func setConnectionState(_ newState: VariaRadarClient.ConnectionState) {
        // Mutate and broadcast in one critical section so subscribers observe
        // transitions in order and replay-on-subscribe can't miss one. Yielding
        // to an AsyncStream never blocks, so holding the lock here is safe.
        let changed = lock.withLock { () -> Bool in
            guard connectionState != newState else { return false }
            connectionState = newState
            for continuation in stateContinuations.values { continuation.yield(newState) }
            // `DiscoveredDevice.isConnected` is derived from this, and every transition
            // in and out of a connection runs through here.
            broadcastDiscoveredLocked()
            return true
        }
        if changed {
            logger.notice("connection state → \(String(describing: newState), privacy: .public)")
        }
    }

    /// Store and publish the battery level. Same single-critical-section discipline as
    /// `setConnectionState`, so replay-on-subscribe can never miss a change.
    private func setBattery(_ level: Int?) {
        lock.withLock {
            guard batteryPercent != level else { return }
            batteryPercent = level
            for continuation in batteryContinuations.values { continuation.yield(level) }
            // The device list carries the level too, and 0x180F answers well after the
            // connection that carried it — so without this the radar's S11 row keeps the
            // nil it was built with and never shows a battery at all. `BLECSCClient`
            // never had the bug: its level lands in the slot, and
            // `recomputeRoleStatesLocked` broadcasts from there.
            broadcastDiscoveredLocked()
        }
    }

    private func broadcastTargets(_ targets: [RadarTarget]) {
        lock.withLock {
            for continuation in targetsContinuations.values { continuation.yield(targets) }
        }
    }

    /// Every radar seen this session, paired first then the rest, each group alphabetical
    /// so the list doesn't reshuffle as advertisements arrive. Built from `discoveredIDs`,
    /// an inventory that is never pruned — and a `Set`, so without this sort the order
    /// would be nondeterministic. Must hold the lock.
    private func discoveredDevicesLocked() -> [DiscoveredDevice] {
        discoveredIDs.map { id in
            DiscoveredDevice(
                id: id,
                name: discoveredNames[id],
                kinds: [.radar],
                // A single-slot client has one role and one gate, so "holds the role"
                // and "is the paired radar" are the same question — which is what
                // `isPaired` meant here before the shape was unified (#98).
                roles: pairedPeripheralID == id ? [.radar] : [],
                // The lifecycle belongs to whoever we are actually talking to. A gated
                // radar we aren't connected to reads `.disconnected` rather than nil,
                // so the row can say so; a stranger's radar gets nil, because this
                // client tracks nothing about it.
                connectionState: targetPeripheralID == id
                    ? connectionState
                    : (pairedPeripheralID == id ? .disconnected : nil),
                // Client-scoped, so it belongs only to the peripheral it was read from.
                batteryPercent: targetPeripheralID == id ? batteryPercent : nil
            )
        }
        .sorted {
            if $0.isPaired != $1.isPaired { return $0.isPaired }
            return ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    /// Fan the device list out to pairing-UI subscribers. Must hold the lock.
    private func broadcastDiscoveredLocked() {
        guard !discoveredContinuations.isEmpty else { return }
        let devices = discoveredDevicesLocked()
        for continuation in discoveredContinuations.values { continuation.yield(devices) }
    }
}
