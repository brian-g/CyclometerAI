@preconcurrency import CoreBluetooth

/// Issues one sensor client's hardware scan calls in the order its lock decided them (#586).
///
/// A client decides to start or stop under its lock, but can't await the transport there.
/// Awaiting after the lock let two decisions made A-then-B reach `BLECentral` B-then-A. At ride
/// start that dropped the CSC service: the Start sheet's last `endPairingScan` decided to stop,
/// the ride's `startScanning` decided to start in the gap, and the stop landed last.
///
/// Enqueue inside the lock acquisition that made the decision, then await the returned task
/// once the lock is released. Each call waits for the one enqueued before it, so the transport
/// sees them in decision order, and the caller still returns only once its own call has landed.
///
/// Not `Sendable`: it lives in a client's lock-guarded state and is only touched under that lock.
struct ScanCallSequence {
    enum Call { case start, stop }

    private let bleClient: BLEClient
    private let serviceUUID: CBUUID
    private var last: Task<Void, Never>?

    init(bleClient: BLEClient, serviceUUID: CBUUID) {
        self.bleClient = bleClient
        self.serviceUUID = serviceUUID
    }

    /// Must be called with the owning client's lock held.
    mutating func enqueue(_ call: Call) -> Task<Void, Never> {
        let previous = last
        let task = Task { [bleClient, serviceUUID] in
            await previous?.value
            switch call {
            case .start: await bleClient.startScanning([serviceUUID])
            case .stop:  await bleClient.stopScanning([serviceUUID])
            }
        }
        last = task
        return task
    }
}
