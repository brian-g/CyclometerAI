import ComposableArchitecture
import CoreBluetooth
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
// Retrieve after an untethered ride: `log collect --device --last 1h` (notice level persists).
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "radar")

// UUIDs pending validation against Garmin's official Radar BLE spec
// (developer program application in progress — see issue #18).
// Identifies this client to BLEClient's connection ref-count so disconnecting the
// radar never severs a peripheral another client shares (see BLEClient.connect).
private let radarOwnerID = "radar"

private let radarServiceUUID    = CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
private let radarAlertUUID      = CBUUID(string: "6A4E3202-667B-11E3-949A-0800200C9A66")  // notify
// Read-only capability characteristic. Unused until BLEClient gains a readValue
// operation — not required for any M3 acceptance criterion.
private let radarCapabilityUUID = CBUUID(string: "6A4E3201-667B-11E3-949A-0800200C9A66")

// MARK: - VariaRadarClient

/// TCA dependency for Garmin Varia RTL515 / RCT715 radar data over raw BLE.
/// Protocol: Garmin Radar Data BLE Program.
/// Reference: pycycling RDR module (open-source Python implementation).
/// Note: RearVue 820 excluded — secured BLE protocol.
/// Uses BLEClient as the CoreBluetooth transport.
struct VariaRadarClient: Sendable {
    /// Connection lifecycle, per PRD §9.1 state machine. `.active` means
    /// notifications are enabled and radar data is flowing.
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case scanning
        case connecting
        case connected
        case active
        case reconnecting
    }

    /// Scan for and auto-connect to the first advertising Varia radar.
    var startScanning:   @Sendable () async -> Void
    var stopScanning:    @Sendable () async -> Void
    var connect:         @Sendable (UUID) async -> Void   // explicit device selection (future settings UI)
    var disconnect:      @Sendable () async -> Void
    var radarTargets:    @Sendable () -> AsyncStream<[RadarTarget]>
    var connectionState: @Sendable () -> AsyncStream<ConnectionState>

    /// Parse vehicle targets from a Radar Alert characteristic value.
    ///
    /// PAYLOAD ASSUMPTION — VALIDATE AGAINST HARDWARE:
    /// - byte 0: alert level (0 = clear, 1 = advisory, 2 = caution, 3 = danger)
    /// - byte 1: vehicle count (0–8)
    /// - bytes 2+2i, 3+2i: per-vehicle record — uint8 range (m), uint8 closing speed (m/s)
    ///
    /// The pycycling RDR reference suggests 3-byte records with per-threat IDs and
    /// speed in ~3.04 km/h units instead — reconcile once hardware is available.
    ///
    /// Returns nil for malformed payloads (drop the notification, keep last good state).
    static func parseAlert(from data: Data) -> [RadarTarget]? {
        guard data.count >= 2 else { return nil }
        let level = data[0]
        let count = Int(data[1])
        guard level <= 3, count <= 8, data.count >= 2 + count * 2 else { return nil }

        let threat: RadarTarget.ThreatLevel = switch level {
        case 0: .allClear
        case 3: .danger
        default: .warning   // advisory (1) and caution (2) collapse to L2
        }

        return (0..<count).map { i in
            RadarTarget(
                id: vehicleSlotIDs[i],
                relativeVelocityMPS: Double(data[3 + i * 2]),
                rangeMetres: Double(data[2 + i * 2]),
                threatLevel: threat
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
            startScanning:   { await state.startScanning() },
            stopScanning:    { await state.stopScanning() },
            connect:         { id in await state.connect(peripheralID: id) },
            disconnect:      { await state.disconnect() },
            radarTargets:    { state.makeTargetsStream() },
            connectionState: { state.makeConnectionStateStream() }
        )
    }

    static let liveValue = VariaRadarClient.live(bleClient: .liveValue, clock: ContinuousClock())

    static let testValue = VariaRadarClient(
        startScanning:   { },
        stopScanning:    { },
        connect:         { _ in },
        disconnect:      { },
        radarTargets:    { AsyncStream { $0.finish() } },
        connectionState: { AsyncStream { $0.finish() } }
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

    private var targetPeripheralID: UUID?
    private var connectionState: VariaRadarClient.ConnectionState = .disconnected
    private var reconnectTask: Task<Void, Never>?

    private var targetsContinuations: [Int: AsyncStream<[RadarTarget]>.Continuation] = [:]
    private var stateContinuations: [Int: AsyncStream<VariaRadarClient.ConnectionState>.Continuation] = [:]
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

    // MARK: Scanning

    func startScanning() async {
        // Only start a fresh scan from a cold state. Re-entering (the dashboard's
        // .task re-runs when the view re-appears, while this state object is
        // process-global) must not stomp a live connection back to .scanning.
        let shouldScan = lock.withLock { connectionState == .disconnected }
        guard shouldScan else {
            logger.info("startScanning skipped — not in disconnected state")
            return
        }
        setConnectionState(.scanning)
        await bleClient.startScanning([radarServiceUUID])
    }

    func stopScanning() async {
        await bleClient.stopScanning([radarServiceUUID])
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
        if let id {
            await bleClient.disconnect(id, radarOwnerID)
        }
        await bleClient.stopScanning([radarServiceUUID])
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
        case .discovered(let id, _, _, let services):
            // Auto-connect the first discovered radar. The shared central may be
            // scanning for several sensor types at once, so filter on the
            // advertised service rather than assuming every discovery is a radar.
            guard services.contains(radarServiceUUID) else { return }
            let shouldConnect = lock.withLock { targetPeripheralID == nil }
            guard shouldConnect else { return }
            await connect(peripheralID: id)

        case .connected(let id):
            guard lock.withLock({ targetPeripheralID }) == id else { return }
            cancelReconnect()
            setConnectionState(.connected)
            await bleClient.discoverServices(id, [radarServiceUUID])

        case .servicesDiscovered(let id, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id,
                  uuids.contains(radarServiceUUID) else { return }
            await bleClient.discoverCharacteristics(id, radarServiceUUID, [radarAlertUUID])

        case .characteristicsDiscovered(let id, let serviceUUID, let uuids):
            guard lock.withLock({ targetPeripheralID }) == id,
                  serviceUUID == radarServiceUUID,
                  uuids.contains(radarAlertUUID) else { return }
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
            setConnectionState(.reconnecting)
            startReconnect()

        case .stateChanged(let managerState):
            switch managerState {
            case .poweredOff, .unauthorized, .unsupported:
                // Permission denied / radio off: stand down cleanly, never crash.
                cancelReconnect()
                lock.withLock { targetPeripheralID = nil }
                broadcastTargets([])
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
            return true
        }
        if changed {
            logger.notice("connection state → \(String(describing: newState), privacy: .public)")
        }
    }

    private func broadcastTargets(_ targets: [RadarTarget]) {
        lock.withLock {
            for continuation in targetsContinuations.values { continuation.yield(targets) }
        }
    }
}
