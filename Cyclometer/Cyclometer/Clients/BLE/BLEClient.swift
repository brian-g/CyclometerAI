import ComposableArchitecture
import CoreBluetooth

/// TCA dependency interface for CoreBluetooth central management.
struct BLEClient {
    var startScanning:  @Sendable ([CBUUID]) async -> Void
    var stopScanning:   @Sendable () async -> Void
    var peripherals:    @Sendable () -> AsyncStream<CBPeripheral>
}

extension BLEClient: DependencyKey {
    static let liveValue = BLEClient(
        startScanning:  { _ in /* CoreBluetooth live impl */ },
        stopScanning:   { /* CoreBluetooth live impl */ },
        peripherals:    { AsyncStream { _ in } }
    )
    static let testValue = BLEClient(
        startScanning:  { _ in },
        stopScanning:   { },
        peripherals:    { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var bleClient: BLEClient {
        get { self[BLEClient.self] }
        set { self[BLEClient.self] = newValue }
    }
}
