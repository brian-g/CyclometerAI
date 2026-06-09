import ComposableArchitecture
import CoreBluetooth

private let hrServiceUUID     = CBUUID(string: "180D")
private let hrMeasurementUUID = CBUUID(string: "2A37")

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
    static let liveValue: BLEHRClient = {
        let state = HRClientState(bleClient: BLEClient.liveValue)
        return BLEHRClient(
            startScanning:  { await state.startScanning() },
            stopScanning:   { await state.stopScanning() },
            connect:        { id in await state.connect(peripheralID: id) },
            disconnect:     { await state.disconnect() },
            heartRate:      { state.makeHeartRateStream() },
            pairingStatus:  { state.makePairingStream() }
        )
    }()

    static let testValue = BLEHRClient(
        startScanning:  { },
        stopScanning:   { },
        connect:        { _ in },
        disconnect:     { },
        heartRate:      { AsyncStream { $0.finish() } },
        pairingStatus:  { AsyncStream { $0.finish() } }
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

    private var heartRateContinuations: [Int: AsyncStream<Int>.Continuation] = [:]
    private var pairingContinuations: [Int: AsyncStream<Bool>.Continuation] = [:]
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
        lock.withLock { pairingContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.pairingContinuations.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: Scanning

    func startScanning() async {
        await bleClient.startScanning([hrServiceUUID])
    }

    func stopScanning() async {
        await bleClient.stopScanning()
    }

    // MARK: Connection control

    func connect(peripheralID: UUID) async {
        lock.withLock { targetPeripheralID = peripheralID }
        await bleClient.connect(peripheralID)
    }

    func disconnect() async {
        let id = lock.withLock { targetPeripheralID }
        guard let id else { return }
        lock.withLock { targetPeripheralID = nil }
        await bleClient.disconnect(id)
        await bleClient.stopScanning()
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
        case .discovered(let id, _, _):
            // Auto-connect first discovered HR device (startScanning filters to 0x180D only).
            let shouldConnect = lock.withLock { targetPeripheralID == nil }
            guard shouldConnect else { return }
            await connect(peripheralID: id)

        case .connected(let id):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            await bleClient.discoverServices(id, [hrServiceUUID])

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

        case .disconnected(let id, _):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            lock.withLock { targetPeripheralID = nil }
            broadcastPairing(false)
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
        let active = lock.withLock { Array(pairingContinuations.values) }
        for continuation in active { continuation.yield(paired) }
    }
}
