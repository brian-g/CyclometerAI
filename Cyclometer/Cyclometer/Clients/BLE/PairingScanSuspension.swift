/// What a sensor client's `setPairingScansSuspended` has to do to the radio once it has
/// updated its state under the lock (#418). Shared by the three clients, which each make
/// the same decision about their own service UUID.
enum PairingScanSuspension {
    /// Nothing changed, or no pairing scan is open.
    case none
    /// Suspended, but the client's own ambient scan (`isScanning`, set by `startScanning`)
    /// still wants the radio, so it stays on.
    case keptByAmbientScan
    /// Suspended: the scan's withdrawal, enqueued under the lock (#586). Await it.
    case stop(Task<Void, Never>)
    /// Resumed with pairing scans open: the scan's reissue, enqueued under the lock. Await it.
    case start(Task<Void, Never>)
}
