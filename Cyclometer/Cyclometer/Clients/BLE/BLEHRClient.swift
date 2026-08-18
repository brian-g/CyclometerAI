import ComposableArchitecture
import CoreBluetooth
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "hr")

private let hrServiceUUID     = CBUUID(string: "180D")
private let hrMeasurementUUID = CBUUID(string: "2A37")

// Identifies this client to BLEClient's connection ref-count so disconnecting the
// HR strap never severs a peripheral another client shares (see BLEClient.connect).
private let hrOwnerID = "hr"

// MARK: - BLEHRClient

/// TCA dependency for the Bluetooth SIG standard BLE Heart Rate Profile (0x180D).
/// Connects to any compliant HR strap (Polar H10, Wahoo TICKR, Garmin HRM-Pro, etc.)
/// and delivers real-time BPM. Uses BLEClient as the CoreBluetooth transport.
struct BLEHRClient: Sendable {
    /// Scan for HR straps and reconnect the one the rider has paired. Nothing is adopted
    /// speculatively: a peripheral is connected only if `setPairedSensor` has named it,
    /// so an unknown strap advertising nearby is listed and ignored (BLE.md §6).
    var startScanning:  @Sendable () async -> Void
    var stopScanning:   @Sendable () async -> Void
    var connect:        @Sendable (UUID) async -> Void   // explicit device selection (future settings UI)
    /// Stop using the strap for now; the pairing survives. This is what ride finish
    /// calls — contrast `setPairedSensor(nil)`, which forgets the strap entirely.
    var disconnect:     @Sendable () async -> Void
    /// The rider's durable HR pairing, or nil when none. The client holds no persistence;
    /// `AppPreferences` owns the record and pushes it here at launch and on every change.
    /// Only this peripheral is connected on discovery.
    ///
    /// Passing nil — or a different peripheral — tears the current connection down in
    /// the same call, so BLE.md §5.0's "records before teardown" holds without the caller
    /// having to order two calls. See `VariaRadarClient.setPairedSensor` for why a
    /// single-slot client needs no separate `unpair`.
    var setPairedSensor: @Sendable (UUID?) async -> Void
    /// Every HR strap seen this session, paired or not. Replays on subscribe.
    var discoveredDevices: @Sendable () -> AsyncStream<[DiscoveredDevice]>
    /// Scan on behalf of the pairing UI. Refcounted and independent of the ambient
    /// dashboard scan, so it still scans while a strap is connected. Mirrors
    /// `BLECSCClient.beginPairingScan` (#68); the Sensors screen holds one of these
    /// open per client for as long as it is on screen (#98).
    var beginPairingScan: @Sendable () async -> Void
    /// Balance a `beginPairingScan`. The hardware scan stops only when no pairing
    /// scan and no ambient scan remain — `BLEClient.requestedServices` is a plain set
    /// with no per-caller refcount, so whoever releases last has to be the one to
    /// release the radio.
    var endPairingScan: @Sendable () async -> Void
    var heartRate:      @Sendable () -> AsyncStream<Int>
    var pairingStatus:  @Sendable () -> AsyncStream<Bool>
    /// Battery percentage of the connected strap, or `nil` when unknown — nothing
    /// connected, or a strap that doesn't expose the Battery Service. Replays the
    /// current value on subscribe.
    var batteryLevel:   @Sendable () -> AsyncStream<Int?>

    /// Parse BPM from a 0x2A37 Heart Rate Measurement characteristic value.
    /// Flags byte[0] bit 0: 0 = uint8 in byte[1], 1 = uint16 LE in bytes[1..2].
    static func parseBPM(from data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        if data[0] & 0x01 == 0 {
            return Int(data[1])
        } else {
            guard data.count >= 3 else { return nil }
            return Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        }
    }
}

// MARK: - DependencyKey

extension BLEHRClient: DependencyKey {
    /// Factory with injectable transport, matching `VariaRadarClient.live` and
    /// `BLECSCClient.live`, so tests can drive BLE events through the state machine.
    static func live(bleClient: BLEClient) -> BLEHRClient {
        let state = HRClientState(bleClient: bleClient)
        return BLEHRClient(
            startScanning:     { await state.startScanning() },
            stopScanning:      { await state.stopScanning() },
            connect:           { id in await state.connect(peripheralID: id) },
            disconnect:        { await state.disconnect() },
            setPairedSensor:   { id in await state.setPairedSensor(id) },
            discoveredDevices: { state.makeDiscoveredDevicesStream() },
            beginPairingScan:  { await state.beginPairingScan() },
            endPairingScan:    { await state.endPairingScan() },
            heartRate:      { state.makeHeartRateStream() },
            pairingStatus:  { state.makePairingStream() },
            batteryLevel:   { state.makeBatteryStream() }
        )
    }

    static let liveValue = BLEHRClient.live(bleClient: .liveValue)

    static let testValue = BLEHRClient(
        startScanning:     { },
        stopScanning:      { },
        connect:           { _ in },
        disconnect:        { },
        setPairedSensor:   { _ in },
        discoveredDevices: { AsyncStream { $0.finish() } },
        beginPairingScan:  { },
        endPairingScan:    { },
        heartRate:      { AsyncStream { $0.finish() } },
        pairingStatus:  { AsyncStream { $0.finish() } },
        batteryLevel:   { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var bleHRClient: BLEHRClient {
        get { self[BLEHRClient.self] }
        set { self[BLEHRClient.self] = newValue }
    }
}

// MARK: - Live implementation

/// Manages the BLE connection lifecycle for a single HR peripheral.
/// Follows the same @unchecked Sendable + NSLock pattern as BLECentral.
private final class HRClientState: @unchecked Sendable {
    private let bleClient: BLEClient
    /// Who we are currently talking to.
    private var targetPeripheralID: UUID?
    /// The rider's durable pairing, and the entire basis on which `.discovered` decides
    /// whether to connect. Deliberately *not* the same field as `targetPeripheralID`:
    /// ride finish calls `disconnect()`, which clears the connection identity, and a
    /// pairing that died with it would never reconnect for the next ride.
    private var pairedPeripheralID: UUID?
    /// Notifications are enabled and BPM is flowing — this client's connected signal.
    /// Note this is *not* `DiscoveredDevice.isPaired`, which is the gate above.
    private var isPaired = false
    private var batteryPercent: Int?

    /// An ambient (dashboard) scan is running. Tracked explicitly because this client
    /// has no connection-state field to infer it from, and `endPairingScan` has to
    /// know whether anyone else still wants the radio.
    private var isScanning = false
    /// How many pairing scans are open. Mirrors `BLECSCClient.pairingScanCount`; only
    /// the sum of this and `isScanning` decides whether the radio may be released.
    private var pairingScanCount = 0

    /// Every strap seen this session. The inventory the pairing list is built from, and
    /// what lets `setPairedSensor` connect a strap discovered before it was paired —
    /// CoreBluetooth won't redeliver `.discovered` for a peripheral already seen.
    private var discoveredIDs: Set<UUID> = []
    /// Separate from `discoveredIDs` because a nil name can't be stored in a dictionary.
    private var discoveredNames: [UUID: String] = [:]

    private var heartRateContinuations: [Int: AsyncStream<Int>.Continuation] = [:]
    private var pairingContinuations: [Int: AsyncStream<Bool>.Continuation] = [:]
    private var batteryContinuations: [Int: AsyncStream<Int?>.Continuation] = [:]
    private var discoveredContinuations: [Int: AsyncStream<[DiscoveredDevice]>.Continuation] = [:]
    private var nextID = 0
    private let lock = NSLock()

    init(bleClient: BLEClient) {
        self.bleClient = bleClient
        startEventLoop()
    }

    // MARK: Subscriber streams

    func makeHeartRateStream() -> AsyncStream<Int> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        lock.withLock { heartRateContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.heartRateContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makePairingStream() -> AsyncStream<Bool> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        // Replay current state, as the radar and CSC state streams do. Without it a
        // sheet opened after the strap paired shows "Not Paired" until the strap
        // drops — and since the Start sheet hides unpaired rows, the row (and its
        // battery level) never appears at all.
        lock.withLock {
            continuation.yield(isPaired)
            pairingContinuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.pairingContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    func makeBatteryStream() -> AsyncStream<Int?> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<Int?>.makeStream()
        // Battery is read once per connection, so a late subscriber that didn't
        // replay would wait until the next reconnect to learn anything.
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
        // Replay + register in one critical section, same as the pairing stream. The
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
        logger.notice("starting scan")
        lock.withLock { isScanning = true }
        await bleClient.startScanning([hrServiceUUID])
    }

    func stopScanning() async {
        let shouldStopHardware = lock.withLock { () -> Bool in
            isScanning = false
            return pairingScanCount == 0
        }
        // `BLEClient.requestedServices` is a plain set with no per-caller refcount, so
        // dropping the HR UUID here would cancel the Sensors screen's scan too.
        guard shouldStopHardware else {
            logger.info("stopScanning kept alive — \(self.pairingScanCountSnapshot) pairing scan(s) open")
            return
        }
        logger.notice("stopping scan")
        await bleClient.stopScanning([hrServiceUUID])
    }

    // MARK: Pairing UI support (S11)

    /// Scan on behalf of the pairing UI. Unlike the radar and CSC clients there is no
    /// cold-state guard to bypass here — `startScanning` is unconditional — but the
    /// refcount is still needed, because `stopScanning` and `disconnect` would
    /// otherwise release a scan this screen still wants.
    func beginPairingScan() async {
        lock.withLock { pairingScanCount += 1 }
        // Re-issuing the scan restarts the CoreBluetooth session, so peripherals
        // already seen are re-advertised to us rather than suppressed as duplicates.
        // That is also what makes pull-to-refresh work (#98).
        await bleClient.startScanning([hrServiceUUID])
        logger.notice("pairing scan started (\(self.pairingScanCountSnapshot) open)")
    }

    func endPairingScan() async {
        let shouldStopHardware = lock.withLock { () -> Bool in
            pairingScanCount = max(0, pairingScanCount - 1)
            return pairingScanCount == 0 && !isScanning
        }
        guard shouldStopHardware else { return }
        await bleClient.stopScanning([hrServiceUUID])
        logger.notice("pairing scan stopped")
    }

    private var pairingScanCountSnapshot: Int { lock.withLock { pairingScanCount } }

    // MARK: Connection control

    func connect(peripheralID: UUID) async {
        lock.withLock { targetPeripheralID = peripheralID }
        await bleClient.connect(peripheralID, hrOwnerID)
        logger.notice("connect requested for \(peripheralID, privacy: .public)")
    }

    func disconnect() async {
        // Read and clear atomically, as the radar client does: a `.disconnected` event
        // processed between a separate read and clear would still match the target and
        // restart the scan.
        //
        // Clearing here is the only chance: the `.disconnected` event that follows
        // guard-fails on the now-nil target, so its clearing branch never runs.
        // Left set, the replayed state tells the next subscriber that a strap the
        // rider just disconnected is still connected, at its last known battery.
        let id = lock.withLock { () -> UUID? in
            let current = targetPeripheralID
            targetPeripheralID = nil
            return current
        }
        broadcastPairing(false)
        setBattery(nil)
        if let id {
            await bleClient.disconnect(id, hrOwnerID)
        }
        // Outside the `if`: a ride that finished with no strap connected must still stop
        // the scan, or the radio keeps looking for a strap this client will now refuse
        // to adopt anyway. Still refcounted, though — ride finish must not silently kill
        // a pairing scan the Sensors screen is holding open.
        let shouldStopHardware = lock.withLock { () -> Bool in
            isScanning = false
            return pairingScanCount == 0
        }
        guard shouldStopHardware else { return }
        await bleClient.stopScanning([hrServiceUUID])
    }

    /// Cache the rider's durable pairing, tearing down whatever no longer matches it and
    /// connecting the new strap if it has already been seen this session.
    ///
    /// Deliberately does not start a scan — see `VariaRadarClient.setPairedSensor` for
    /// why.
    func setPairedSensor(_ id: UUID?) async {
        // The gate and the connection identity move together in one acquisition, so a
        // `.discovered` racing on the event-loop task sees either both old or both new
        // and can never act on an open gate with a stale target.
        let (toDisconnect, toConnect): (UUID?, UUID?) = lock.withLock {
            guard pairedPeripheralID != id else { return (nil, nil) }
            pairedPeripheralID = id

            // Both halves, not either/or: swapping A for B has to release A *and* pick
            // up B. Returning after the teardown would leave the rider's new strap
            // unconnected until it next advertised.
            var toDisconnect: UUID?
            if let current = targetPeripheralID, current != id {
                targetPeripheralID = nil
                toDisconnect = current
            }
            // The new strap is already in the session inventory: connect it now rather
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
            broadcastPairing(false)
            setBattery(nil)
            await bleClient.disconnect(toDisconnect, hrOwnerID)
        }
        if let toConnect {
            await bleClient.connect(toConnect, hrOwnerID)
        }
        logger.notice("paired strap → \(id?.uuidString ?? "none", privacy: .public)")
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
        // Battery is a device concern, not an HR one — the shared handshake drives its
        // own discover → read and only ever claims 0x2A19 value updates.
        if let reading = await BatteryService.handle(event, bleClient: bleClient, owns: { [weak self] id in
            self?.lock.withLock { self?.targetPeripheralID } == id
        }) {
            setBattery(reading.level)
        }

        switch event {
        case .discovered(let id, let name, _, let services):
            // Reconnect only what the rider has paired. Nothing is adopted
            // speculatively: an unknown strap is listed for the pairing UI and otherwise
            // left alone, so a training partner's strap at a group start can never take
            // over the HR reading. The shared central may be scanning several sensor
            // types, so filter on the service first.
            guard services.contains(hrServiceUUID) else { return }
            let (shouldConnect, firstSighting): (Bool, Bool) = lock.withLock {
                let firstSighting = discoveredIDs.insert(id).inserted
                if let name { discoveredNames[id] = name }
                broadcastDiscoveredLocked()
                // `targetPeripheralID == nil` is load-bearing: the `.disconnected` branch
                // below restarts the scan, and `BLECentral.rescan` redelivers peripherals
                // already seen. Claiming the target in the same acquisition as the check
                // keeps two redeliveries from both passing it.
                guard targetPeripheralID == nil, pairedPeripheralID == id else {
                    return (false, firstSighting)
                }
                targetPeripheralID = id
                return (true, firstSighting)
            }
            // Announce the gate's verdict, once per peripheral per scan session. Without
            // this an ignored strap is indistinguishable from one that never advertised:
            // before the gate existed, "connect requested" was the only evidence
            // discovery had happened at all.
            if firstSighting {
                logger.notice("""
                    discovered "\(name ?? "?", privacy: .public)" \(id, privacy: .public) — \
                    \(shouldConnect ? "paired, connecting" : "not paired, ignoring", privacy: .public)
                    """)
            }
            guard shouldConnect else { return }
            await bleClient.connect(id, hrOwnerID)

        case .connected(let id):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            // One call for both services: didDiscoverServices reports the peripheral's
            // full service list, so a second call for 0x180F would re-fire the
            // measurement characteristic's discover → notify chain.
            await bleClient.discoverServices(id, [hrServiceUUID, BatteryService.serviceUUID])

        case .servicesDiscovered(let id, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id,
                  uuids.contains(hrServiceUUID) else { return }
            await bleClient.discoverCharacteristics(id, hrServiceUUID, [hrMeasurementUUID])

        case .characteristicsDiscovered(let id, let serviceUUID, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id,
                  serviceUUID == hrServiceUUID,
                  uuids.contains(hrMeasurementUUID) else { return }
            await bleClient.setNotifyValue(true, id, hrServiceUUID, hrMeasurementUUID)
            broadcastPairing(true)

        case .characteristicValueUpdated(let id, let charUUID, let data):
            guard lock.withLock({ targetPeripheralID }) == id,
                  charUUID == hrMeasurementUUID,
                  let bpm = BLEHRClient.parseBPM(from: data) else { return }
            broadcastHeartRate(bpm)
            logger.info("bpm \(bpm)")

        case .disconnected(let id, _):
            // Rescanning *is* this client's reconnect: `BLECentral.rescan` restarts the
            // CoreBluetooth session, the paired strap re-advertises, and `.discovered`
            // above lets exactly it back in. That is why HR needs no backoff ladder, and
            // why the rescan is now safe — it can no longer adopt a stranger.
            let stillPaired: Bool? = lock.withLock {
                guard targetPeripheralID == id else { return nil }
                targetPeripheralID = nil
                guard pairedPeripheralID != nil else { return false }
                // This rescan is an ambient scan like any other, and has to be counted
                // as one: `endPairingScan` releases the radio when nothing else wants
                // it, and a reconnect invisible to that check would be cancelled by the
                // rider merely closing the Sensors screen mid-ride.
                isScanning = true
                return true
            }
            guard let stillPaired else { return }
            broadcastPairing(false)
            setBattery(nil)   // re-read on reconnect rather than show a stale level
            // Nothing paired — an explicit `connect(_:)` selection that dropped. Scanning
            // on would leave the radio looking for a strap the gate would refuse.
            guard stillPaired else { return }
            await bleClient.startScanning([hrServiceUUID])

        default:
            break
        }
    }

    // MARK: Broadcast helpers

    private func broadcastHeartRate(_ bpm: Int) {
        let active = lock.withLock { Array(heartRateContinuations.values) }
        for continuation in active { continuation.yield(bpm) }
    }

    private func broadcastPairing(_ paired: Bool) {
        // Store and broadcast in one critical section so a replaying subscriber can't
        // slip between the two and miss the transition.
        lock.withLock {
            isPaired = paired
            for continuation in pairingContinuations.values { continuation.yield(paired) }
            // `DiscoveredDevice.isConnected` is derived from this.
            broadcastDiscoveredLocked()
        }
    }

    /// Every strap seen this session, paired first then the rest, each group alphabetical
    /// so the list doesn't reshuffle as advertisements arrive. Built from `discoveredIDs`,
    /// an inventory that is never pruned — and a `Set`, so without this sort the order
    /// would be nondeterministic. Must hold the lock.
    /// Project this client's target + notifying flags onto the shared lifecycle enum.
    /// Must hold the lock.
    private func connectionStateLocked(for id: UUID) -> SensorConnectionState? {
        guard targetPeripheralID == id else {
            return pairedPeripheralID == id ? .disconnected : nil
        }
        return isPaired ? .active : .connecting
    }

    private func discoveredDevicesLocked() -> [DiscoveredDevice] {
        discoveredIDs.map { id in
            DiscoveredDevice(
                id: id,
                name: discoveredNames[id],
                kinds: [.heartRate],
                // A single-slot client has one role and one gate, so "holds the role"
                // and "is the paired strap" are the same question — which is what
                // `isPaired` meant here before the shape was unified (#98).
                roles: pairedPeripheralID == id ? [.heartRate] : [],
                // This client tracks a target and a notifying flag rather than a
                // lifecycle enum, so the enum is projected from the two: notifying is
                // `.active`, a target that hasn't reached notifications yet is
                // `.connecting`, and a gated strap we aren't talking to is
                // `.disconnected`. A stranger's strap gets nil — nothing is tracked
                // about it.
                connectionState: connectionStateLocked(for: id),
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

    private func setBattery(_ level: Int?) {
        lock.withLock {
            guard batteryPercent != level else { return }
            batteryPercent = level
            for continuation in batteryContinuations.values { continuation.yield(level) }
        }
    }
}
