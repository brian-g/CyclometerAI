/// What a sensor client's `setPairingScansSuspended` has to do to the radio once it has
/// updated its state under the lock (#418). Shared by the three clients, which each make
/// the same decision about their own service UUID.
enum PairingScanSuspension {
    /// Nothing changed, or no pairing scan is open.
    case none
    /// Suspended, but the client's own ambient scan (`isScanning`, set by `startScanning`)
    /// still wants the radio, so it stays on.
    case keptByAmbientScan
    /// Suspended: withdraw the scan.
    case stop
    /// Resumed with pairing scans open: reissue the scan.
    case start
}
