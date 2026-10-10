import Foundation

/// The ride's altitude, from the best source on hand (#387).
///
/// - **Absolute barometric** (`AltimeterReading.absolute`): Core Motion's barometer-and-GPS fusion,
///   once it is as sure of itself as a GPS fix worth anchoring on. Its first estimates come from
///   pressure alone and can be tens of metres out; GPS stands in until it settles, and from then
///   on it stays, so the ride doesn't flip between sources.
/// - **Relative barometric** (`AltimeterReading.relative`), on a device without absolute altitude:
///   the barometer's change since it started, added to an anchor taken from the first GPS fix
///   accurate enough to trust. Until then GPS altitude stands in, and the anchor is set so the
///   reading continues from exactly that value — no step when the barometer takes over.
/// - **GPS**, when there is no barometer, Motion & Fitness access is denied, or its stream ends.
///
/// Whatever it settles on is the ride's altitude everywhere: the dashboard, the recorded track
/// and so the GPX `<ele>`.
struct AltitudeResolver: Equatable, Sendable {
    enum Source: Equatable, Sendable { case barometric, gps }

    /// An altitude this accurate (one sigma) or better is trusted: a GPS fix to anchor the relative
    /// barometer, and Core Motion's absolute altitude to take over from GPS. Worse than it, either
    /// would put the whole ride metres off true for its entire length; a phone with a clear sky
    /// reports 3–8 m.
    static let trustedAccuracyMeters = 10.0

    /// Nil until a source has given one, and after a GPS fix without one while GPS is the source
    /// (#303): an invalid fix is never covered with the altitude before it.
    private(set) var altitude: Double?
    private(set) var source: Source = .gps

    private var isAbsoluteLive = false
    /// The relative barometer's latest reading, nil while it isn't running.
    private var relativeMeters: Double?
    /// Sea-level altitude at the relative barometer's zero.
    private var anchor: Double?

    mutating func gpsFix(altitude: Double?, verticalAccuracy: Double?) {
        if isAbsoluteLive || anchor != nil { return }
        if let relativeMeters, let altitude, let verticalAccuracy,
           verticalAccuracy <= Self.trustedAccuracyMeters {
            anchor = altitude - relativeMeters
            self.altitude = altitude
            source = .barometric
            return
        }
        self.altitude = altitude
        source = .gps
    }

    mutating func barometer(_ reading: AltimeterReading) {
        switch reading {
        case .absolute(let meters, let accuracy):
            guard isAbsoluteLive || (0...Self.trustedAccuracyMeters).contains(accuracy) else { return }
            isAbsoluteLive = true
            altitude = meters
            source = .barometric
        case .relative(let meters):
            relativeMeters = meters
            if let anchor {
                altitude = anchor + meters
                source = .barometric
            }
        }
    }

    /// The barometer stream finished: GPS again from its next fix. Until it comes there is no
    /// altitude, rather than the barometer's last one passed off as current (#303).
    mutating func barometerEnded() {
        isAbsoluteLive = false
        relativeMeters = nil
        anchor = nil
        if source == .barometric {
            altitude = nil
            source = .gps
        }
    }
}
