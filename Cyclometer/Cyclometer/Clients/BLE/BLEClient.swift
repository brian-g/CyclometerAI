import ComposableArchitecture
@preconcurrency import CoreBluetooth

// MARK: - BLEEvent

/// Events broadcast by BLEClient from CBCentralManager and CBPeripheral delegate callbacks.
enum BLEEvent: Sendable {
    case stateChanged(CBManagerState)
    case discovered(id: UUID, name: String?, rssi: Int)
    case connected(id: UUID)
    case disconnected(id: UUID, error: (any Error)?)
    case failedToConnect(id: UUID, error: (any Error)?)
    case servicesDiscovered(peripheralID: UUID, serviceUUIDs: [CBUUID])
    case characteristicsDiscovered(peripheralID: UUID, serviceUUID: CBUUID, characteristicUUIDs: [CBUUID])
    case characteristicValueUpdated(peripheralID: UUID, characteristicUUID: CBUUID, value: Data)
}

// MARK: - BLEClient

/// Shared CoreBluetooth transport layer used by all BLE sensor clients.
///
/// One CBCentralManager is shared across the app. Sensor clients (VariaRadarClient,
/// BLEHRClient, BLECSCClient) subscribe to `events()` and filter for their service UUIDs.
struct BLEClient: Sendable {
    /// Start scanning for peripherals advertising the given service UUIDs.
    var startScanning: @Sendable ([CBUUID]) async -> Void
    var stopScanning: @Sendable () async -> Void
    /// Connect to a previously discovered peripheral by its UUID.
    var connect: @Sendable (UUID) async -> Void
    var disconnect: @Sendable (UUID) async -> Void
    /// Call after `.connected` to discover services on the peripheral.
    var discoverServices: @Sendable (UUID, [CBUUID]?) async -> Void
    /// Call after services are found to discover characteristics within a service.
    var discoverCharacteristics: @Sendable (UUID, CBUUID, [CBUUID]?) async -> Void
    /// Enable or disable value notifications on a characteristic. Yields
    /// `.characteristicValueUpdated` events when the peripheral sends data.
    var setNotifyValue: @Sendable (Bool, UUID, CBUUID, CBUUID) async -> Void
    /// Returns an `AsyncStream` of BLE events. Each call returns a new stream;
    /// all active streams receive the same broadcast events.
    var events: @Sendable () -> AsyncStream<BLEEvent>
}

// MARK: - DependencyKey

extension BLEClient: DependencyKey {
    static let liveValue: BLEClient = {
        let central = BLECentral.shared
        return BLEClient(
            startScanning: { central.startScanning(serviceUUIDs: $0) },
            stopScanning: { central.stopScanning() },
            connect: { central.connect(peripheralID: $0) },
            disconnect: { central.disconnect(peripheralID: $0) },
            discoverServices: { central.discoverServices(peripheralID: $0, serviceUUIDs: $1) },
            discoverCharacteristics: { central.discoverCharacteristics(peripheralID: $0, serviceUUID: $1, characteristicUUIDs: $2) },
            setNotifyValue: { central.setNotifyValue($0, peripheralID: $1, serviceUUID: $2, characteristicUUID: $3) },
            events: { central.makeEventStream() }
        )
    }()

    static let testValue = BLEClient(
        startScanning: { _ in },
        stopScanning: { },
        connect: { _ in },
        disconnect: { _ in },
        discoverServices: { _, _ in },
        discoverCharacteristics: { _, _, _ in },
        setNotifyValue: { _, _, _, _ in },
        events: { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var bleClient: BLEClient {
        get { self[BLEClient.self] }
        set { self[BLEClient.self] = newValue }
    }
}

// MARK: - Live CoreBluetooth implementation

/// Manages a single CBCentralManager and fans out events to all active subscribers.
///
/// `@unchecked Sendable`: thread safety is enforced manually — `bleQueue` for all
/// CoreBluetooth operations and peripheral storage; `lock` for subscriber management.
private final class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {

    static let shared = BLECentral()

    private let bleQueue = DispatchQueue(label: "name.glaeske.cyclometer.ble", qos: .userInitiated)
    private var manager: CBCentralManager!

    // Retained peripherals — CBCentralManager doesn't hold strong references.
    private var discovered: [UUID: CBPeripheral] = [:]

    // Multi-subscriber broadcast: each call to makeEventStream() registers a continuation.
    private var subscribers: [Int: AsyncStream<BLEEvent>.Continuation] = [:]
    private var nextSubscriberID = 0
    private let lock = NSLock()

    override private init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: Subscriber management

    func makeEventStream() -> AsyncStream<BLEEvent> {
        let id: Int = lock.withLock {
            let current = nextSubscriberID
            nextSubscriberID += 1
            return current
        }
        let (stream, continuation) = AsyncStream<BLEEvent>.makeStream()
        lock.withLock { subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    private func broadcast(_ event: BLEEvent) {
        let active = lock.withLock { Array(subscribers.values) }
        for continuation in active { continuation.yield(event) }
    }

    // MARK: Scanning

    func startScanning(serviceUUIDs: [CBUUID]) {
        bleQueue.async { [self] in
            guard manager.state == .poweredOn else { return }
            manager.scanForPeripherals(withServices: serviceUUIDs.isEmpty ? nil : serviceUUIDs)
        }
    }

    func stopScanning() {
        bleQueue.async { [self] in
            manager.stopScan()
        }
    }

    // MARK: Connection

    func connect(peripheralID: UUID) {
        bleQueue.async { [self] in
            guard let peripheral = discovered[peripheralID] else { return }
            manager.connect(peripheral)
        }
    }

    func disconnect(peripheralID: UUID) {
        bleQueue.async { [self] in
            guard let peripheral = discovered[peripheralID] else { return }
            manager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: Service and characteristic discovery

    func discoverServices(peripheralID: UUID, serviceUUIDs: [CBUUID]?) {
        bleQueue.async { [self] in
            discovered[peripheralID]?.discoverServices(serviceUUIDs)
        }
    }

    func discoverCharacteristics(peripheralID: UUID, serviceUUID: CBUUID, characteristicUUIDs: [CBUUID]?) {
        bleQueue.async { [self] in
            guard let peripheral = discovered[peripheralID],
                  let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
            peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
        }
    }

    func setNotifyValue(_ enabled: Bool, peripheralID: UUID, serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        bleQueue.async { [self] in
            guard let peripheral = discovered[peripheralID],
                  let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else { return }
            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        broadcast(.stateChanged(central.state))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discovered[peripheral.identifier] = peripheral
        broadcast(.discovered(id: peripheral.identifier, name: peripheral.name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        broadcast(.connected(id: peripheral.identifier))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        broadcast(.disconnected(id: peripheral.identifier, error: error))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        broadcast(.failedToConnect(id: peripheral.identifier, error: error))
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, let value = characteristic.value else { return }
        broadcast(.characteristicValueUpdated(
            peripheralID: peripheral.identifier,
            characteristicUUID: characteristic.uuid,
            value: value
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else { return }
        let uuids = peripheral.services?.map(\.uuid) ?? []
        broadcast(.servicesDiscovered(peripheralID: peripheral.identifier, serviceUUIDs: uuids))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else { return }
        let uuids = service.characteristics?.map(\.uuid) ?? []
        broadcast(.characteristicsDiscovered(peripheralID: peripheral.identifier, serviceUUID: service.uuid, characteristicUUIDs: uuids))
    }
}
