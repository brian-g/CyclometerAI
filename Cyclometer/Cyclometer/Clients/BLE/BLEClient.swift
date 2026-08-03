import ComposableArchitecture
@preconcurrency import CoreBluetooth
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
// Retrieve after an untethered ride: `log collect --device --last 1h` (notice level persists).
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "ble")

// MARK: - BLEEvent

/// Events broadcast by BLEClient from CBCentralManager and CBPeripheral delegate callbacks.
enum BLEEvent: Sendable {
    case stateChanged(CBManagerState)
    /// `services` carries the advertised service UUIDs so sensor clients can
    /// filter discoveries — the shared central may scan for several sensor
    /// types at once.
    case discovered(id: UUID, name: String?, rssi: Int, services: [CBUUID])
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
    /// Requests from multiple clients are unioned — CoreBluetooth has a single
    /// scan per central, and a second `scanForPeripherals` call would otherwise
    /// replace the first caller's filter.
    var startScanning: @Sendable ([CBUUID]) async -> Void
    /// Stop scanning for the given service UUIDs. The central keeps scanning
    /// for any services other clients still have requested.
    var stopScanning: @Sendable ([CBUUID]) async -> Void
    /// Connect to a previously discovered peripheral by its UUID. `owner` identifies
    /// the calling sensor client; the central ref-counts connection requests so one
    /// client disconnecting never severs a peripheral another client still uses
    /// (the same physical device can serve several profiles). Repeating connect with
    /// the same owner is idempotent.
    var connect: @Sendable (UUID, _ owner: String) async -> Void
    /// Release this `owner`'s interest in the peripheral. The central cancels the
    /// CoreBluetooth connection only once no owner still wants it.
    var disconnect: @Sendable (UUID, _ owner: String) async -> Void
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
            stopScanning: { central.stopScanning(serviceUUIDs: $0) },
            connect: { central.connect(peripheralID: $0, owner: $1) },
            disconnect: { central.disconnect(peripheralID: $0, owner: $1) },
            discoverServices: { central.discoverServices(peripheralID: $0, serviceUUIDs: $1) },
            discoverCharacteristics: { central.discoverCharacteristics(peripheralID: $0, serviceUUID: $1, characteristicUUIDs: $2) },
            setNotifyValue: { central.setNotifyValue($0, peripheralID: $1, serviceUUID: $2, characteristicUUID: $3) },
            events: { central.makeEventStream() }
        )
    }()

    static let testValue = BLEClient(
        startScanning: { _ in },
        stopScanning: { _ in },
        connect: { _, _ in },
        disconnect: { _, _ in },
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

    // Which sensor clients want each peripheral connected. The same physical device
    // can serve several profiles (e.g. CSC + HR), so a CoreBluetooth connection is a
    // shared resource: cancel it only once the last interested client releases it.
    // A Set makes repeated connect() requests from one client idempotent (the radar
    // and CSC reconnect loops re-issue connect as a nudge). Guarded by bleQueue.
    private var connectionOwners: [UUID: Set<String>] = [:]

    // Union of service UUIDs requested by all sensor clients. CoreBluetooth has
    // a single scan per central — a second scanForPeripherals call replaces the
    // filter — so the central scans for the union and clients filter discoveries
    // via the `services` field on `.discovered`. Guarded by bleQueue.
    private var requestedServices: Set<CBUUID> = []

    // Multi-subscriber broadcast: each call to makeEventStream() registers a continuation.
    private var subscribers: [Int: AsyncStream<BLEEvent>.Continuation] = [:]
    private var nextSubscriberID = 0
    private let lock = NSLock()

    override private init() {
        super.init()
        // No CBCentralManagerOptionRestoreIdentifierKey: state restoration was evaluated in the
        // M6 spike (#71) and deferred to M7. It only pays off once a terminated ride is
        // recoverable, and CoreDataStack has no checkpointing yet — restoring the BLE half of a
        // state whose other half is gone buys nothing. See BLE.md §13 for the rationale and for
        // what adopting it would require. The app does declare the bluetooth-central background
        // mode, so background scanning and reconnection work without restoration.
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
            requestedServices.formUnion(serviceUUIDs)
            rescan()
        }
    }

    func stopScanning(serviceUUIDs: [CBUUID]) {
        bleQueue.async { [self] in
            requestedServices.subtract(serviceUUIDs)
            rescan()
        }
    }

    /// (Re)issue the hardware scan to match the currently requested union.
    /// Must be called on bleQueue.
    private func rescan() {
        guard manager.state == .poweredOn else {
            logger.info("rescan deferred — manager state \(self.manager.state.rawValue) (resumes on poweredOn)")
            return
        }
        if requestedServices.isEmpty {
            logger.notice("scan stopped — no services requested")
            manager.stopScan()
        } else {
            let union = requestedServices.map(\.uuidString).sorted().joined(separator: ", ")
            logger.notice("scanning for union: [\(union, privacy: .public)]")
            manager.scanForPeripherals(withServices: Array(requestedServices))
        }
    }

    // MARK: Connection

    func connect(peripheralID: UUID, owner: String) {
        bleQueue.async { [self] in
            connectionOwners[peripheralID, default: []].insert(owner)
            guard let peripheral = discovered[peripheralID] else { return }
            manager.connect(peripheral)
        }
    }

    func disconnect(peripheralID: UUID, owner: String) {
        bleQueue.async { [self] in
            connectionOwners[peripheralID]?.remove(owner)
            // Another client still depends on this peripheral — leave it connected.
            if let remaining = connectionOwners[peripheralID], !remaining.isEmpty { return }
            connectionOwners[peripheralID] = nil
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
        logger.notice("manager state → \(central.state.rawValue) (5 = poweredOn)")
        if central.state == .poweredOn {
            // Resume scans requested before power-on or cleared by a radio cycle.
            rescan()
        }
        broadcast(.stateChanged(central.state))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discovered[peripheral.identifier] = peripheral
        var services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            services.append(contentsOf: overflow)
        }
        let serviceList = services.map(\.uuidString).joined(separator: ", ")
        logger.notice("""
            discovered "\(peripheral.name ?? "?", privacy: .public)" \
            rssi \(RSSI.intValue) services [\(serviceList, privacy: .public)]
            """)
        broadcast(.discovered(
            id: peripheral.identifier, name: peripheral.name, rssi: RSSI.intValue, services: services
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        logger.notice("connected \(peripheral.name ?? "?", privacy: .public) \(peripheral.identifier, privacy: .public)")
        broadcast(.connected(id: peripheral.identifier))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        logger.notice("""
            disconnected \(peripheral.name ?? "?", privacy: .public) \
            error: \(error.map(String.init(describing:)) ?? "none", privacy: .public)
            """)
        broadcast(.disconnected(id: peripheral.identifier, error: error))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        logger.notice("""
            failed to connect \(peripheral.name ?? "?", privacy: .public) \
            error: \(error.map(String.init(describing:)) ?? "none", privacy: .public)
            """)
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
