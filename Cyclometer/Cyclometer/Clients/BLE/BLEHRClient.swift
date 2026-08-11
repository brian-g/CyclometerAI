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
    /// Scan for and auto-connect to the first advertising HR strap.
    var startScanning:  @Sendable () async -> Void
    var stopScanning:   @Sendable () async -> Void
    var connect:        @Sendable (UUID) async -> Void   // explicit device selection (future settings UI)
    var disconnect:     @Sendable () async -> Void
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
            startScanning:  { await state.startScanning() },
            stopScanning:   { await state.stopScanning() },
            connect:        { id in await state.connect(peripheralID: id) },
            disconnect:     { await state.disconnect() },
            heartRate:      { state.makeHeartRateStream() },
            pairingStatus:  { state.makePairingStream() },
            batteryLevel:   { state.makeBatteryStream() }
        )
    }

    static let liveValue = BLEHRClient.live(bleClient: .liveValue)

    static let testValue = BLEHRClient(
        startScanning:  { },
        stopScanning:   { },
        connect:        { _ in },
        disconnect:     { },
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
    private var targetPeripheralID: UUID?
    private var isPaired = false
    private var batteryPercent: Int?

    private var heartRateContinuations: [Int: AsyncStream<Int>.Continuation] = [:]
    private var pairingContinuations: [Int: AsyncStream<Bool>.Continuation] = [:]
    private var batteryContinuations: [Int: AsyncStream<Int?>.Continuation] = [:]
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

    // MARK: Scanning

    func startScanning() async {
        logger.notice("starting scan")
        await bleClient.startScanning([hrServiceUUID])
    }

    func stopScanning() async {
        logger.notice("stopping scan")
        await bleClient.stopScanning([hrServiceUUID])
    }

    // MARK: Connection control

    func connect(peripheralID: UUID) async {
        lock.withLock { targetPeripheralID = peripheralID }
        await bleClient.connect(peripheralID, hrOwnerID)
        logger.notice("connect requested for \(peripheralID, privacy: .public)")
    }

    func disconnect() async {
        let id = lock.withLock { targetPeripheralID }
        guard let id else { return }
        lock.withLock { targetPeripheralID = nil }
        // Clearing here is the only chance: the `.disconnected` event that follows
        // guard-fails on the now-nil target, so its clearing branch never runs.
        // Left set, the replayed state tells the next subscriber that a strap the
        // rider just disconnected is still connected, at its last known battery.
        broadcastPairing(false)
        setBattery(nil)
        await bleClient.disconnect(id, hrOwnerID)
        await bleClient.stopScanning([hrServiceUUID])
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
        case .discovered(let id, _, _, let services):
            // Auto-connect the first discovered HR device. The shared central may
            // be scanning for several sensor types at once, so filter on the
            // advertised service rather than assuming every discovery is a strap.
            guard services.contains(hrServiceUUID) else { return }
            let shouldConnect = lock.withLock { targetPeripheralID == nil }
            guard shouldConnect else { return }
            await connect(peripheralID: id)

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
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            lock.withLock { targetPeripheralID = nil }
            broadcastPairing(false)
            setBattery(nil)   // re-read on reconnect rather than show a stale level
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
        }
    }

    private func setBattery(_ level: Int?) {
        lock.withLock {
            guard batteryPercent != level else { return }
            batteryPercent = level
            for continuation in batteryContinuations.values { continuation.yield(level) }
        }
    }
}
