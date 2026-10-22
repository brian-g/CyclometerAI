import Foundation

/// What one ride's battery readings and link losses say about one physical sensor (#391).
///
/// Per device, not per role: the battery and the radio belong to the peripheral, so a combo
/// CSC device has one verdict for both its roles. Saved in `AppPreferences.sensorHealth` at
/// ride end, which is how the next ride's Start sheet (S05.1) can warn before the first drop,
/// and how the Ride Summary (S10) finds the sensors that misbehaved on *its* ride.
struct SensorHealthReport: Codable, Equatable, Sendable {
    /// At or below this the battery reads low. Shared with `SensorBatteryLabel`, which tints
    /// the live level at the same point, so the two never disagree about what "low" is.
    static let lowBatteryPercent = 20

    /// The stretch over which link losses are counted. Five minutes is long enough that a
    /// rider riding briefly out of range (a drop, a reconnect) never adds up, and short
    /// enough that a flapping stretch inside a three-hour ride isn't averaged away.
    static let linkLossWindow: TimeInterval = 5 * 60

    /// Supervision timeouts within one `linkLossWindow` that make a link unreliable: one a
    /// minute, sustained. On 2026-10-07 a sagging coin cell dropped the speed sensor every
    /// ~7 s — about 43 a window — while the healthy cadence sensor beside it dropped none,
    /// and a healthy sensor's one drop at ride end is 1.
    static let unreliableLinkLosses = 5

    /// The ride this verdict is from.
    var rideId: UUID
    /// Lowest level the sensor reported over the ride. A sagging cell reads high between
    /// transmissions and collapses under radio load, so the latest reading says nothing —
    /// on 2026-10-07 the speed sensor read 87, 10, 95 and 0 inside two minutes.
    var minBatteryPercent: Int?
    /// Most supervision timeouts (CBError 6) inside any one `linkLossWindow` of the ride.
    var maxLinkLossesPerWindow: Int

    /// What to tell the rider, if anything.
    ///
    /// A low battery wins: it is the more specific cause, and a flapping link is the
    /// expected symptom of one. A flapping link alone names no cause — it could as well be
    /// the mount or the distance to the phone.
    var warning: SensorWarning? {
        if let minBatteryPercent, minBatteryPercent <= Self.lowBatteryPercent { return .batteryLow }
        if maxLinkLossesPerWindow >= Self.unreliableLinkLosses { return .linkUnreliable }
        return nil
    }
}

enum SensorWarning: Equatable, Sendable {
    case batteryLow
    case linkUnreliable
}

/// Collects one ride's battery readings and link losses per peripheral, for
/// `SensorHealthReport`. Bounded: it keeps the lowest level and one window of loss times,
/// not the ride's history.
struct SensorHealthLog: Equatable {
    private struct Entry: Equatable {
        var minBatteryPercent: Int?
        /// Loss times inside the window ending at the latest loss.
        var recentLinkLosses: [Date] = []
        var maxLinkLossesPerWindow = 0
    }

    private var entries: [UUID: Entry] = [:]

    /// The sensor connected this ride. Enough for a verdict on its own: a sensor without the
    /// Battery Service that never drops has nothing else to say, and without this its last
    /// warning would outlive any number of clean rides.
    mutating func recordConnected(peripheral: UUID) {
        if entries[peripheral] == nil { entries[peripheral] = Entry() }
    }

    /// A `nil` level is skipped: every sensor client publishes nil on each disconnect, and
    /// it means "unknown", not empty.
    mutating func recordBattery(_ percent: Int?, peripheral: UUID) {
        guard let percent else { return }
        entries[peripheral, default: Entry()].minBatteryPercent =
            min(entries[peripheral]?.minBatteryPercent ?? percent, percent)
    }

    mutating func recordLinkLoss(peripheral: UUID, at date: Date) {
        var entry = entries[peripheral, default: Entry()]
        entry.recentLinkLosses.append(date)
        let windowStart = date.addingTimeInterval(-SensorHealthReport.linkLossWindow)
        entry.recentLinkLosses.removeAll { $0 <= windowStart }
        entry.maxLinkLossesPerWindow = max(entry.maxLinkLossesPerWindow, entry.recentLinkLosses.count)
        entries[peripheral] = entry
    }

    /// A report for each peripheral that connected or reported this ride. One that never
    /// showed up gets none, so a dead cell that never connects keeps the warning from the ride
    /// that last saw it.
    func reports(rideId: UUID) -> [UUID: SensorHealthReport] {
        entries.mapValues {
            SensorHealthReport(rideId: rideId,
                               minBatteryPercent: $0.minBatteryPercent,
                               maxLinkLossesPerWindow: $0.maxLinkLossesPerWindow)
        }
    }
}
