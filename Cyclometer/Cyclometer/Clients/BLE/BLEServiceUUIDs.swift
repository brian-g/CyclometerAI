import CoreBluetooth

/// The advertised GATT service each supported sensor kind is found by (BLE.md §8).
///
/// One table rather than a file-private constant in each client. Unified discovery
/// (#98) has to answer "what kind of thing is this?" from the service list on a
/// `.discovered` event, which needs the mapping in both directions and in one place;
/// three private copies could drift and only the scan would notice.
///
/// Lives beside the clients rather than in `Models/` so `SensorKind` itself stays free
/// of CoreBluetooth.
extension SensorKind {
    /// The service a peripheral advertises to be classified as this kind.
    ///
    /// Radar is Garmin's proprietary-but-documented UUID, pending validation against
    /// the official spec (issue #18). The other two are Bluetooth SIG 16-bit UUIDs.
    var serviceUUID: CBUUID {
        switch self {
        case .radar:        CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
        case .heartRate:    CBUUID(string: "180D")
        case .speedCadence: CBUUID(string: "1816")
        }
    }

    /// Classify an advertisement. Returns every supported kind the peripheral claims —
    /// a combo device advertising two of them is one row carrying both tags, not two
    /// rows (#98).
    ///
    /// `allCases` is safe to iterate here precisely because `SensorKind` only declares
    /// kinds the app scans for; Phase 3 power (0x1818) is absent from the enum rather
    /// than filtered out at this call site.
    static func kinds(advertising services: [CBUUID]) -> Set<SensorKind> {
        Set(allCases.filter { services.contains($0.serviceUUID) })
    }
}
