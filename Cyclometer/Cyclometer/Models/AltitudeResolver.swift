import Foundation
import os

private let logger = Logger.cyclometer(.location)

/// The ride's altitude, from the best source on hand (#387).
///
/// - **Absolute barometric** (`AltimeterReading.absolute`): Core Motion's barometer-and-GPS fusion,
///   once it is as sure of itself as a GPS fix worth anchoring on. Its first estimates come from
///   pressure alone and can be tens of metres out; GPS stands in until it settles, and from then
///   on it stays, so the ride doesn't flip between sources. Core Motion can re-anchor mid-ride, moving
///   its altitude hundreds of metres that the barometer never saw (#433); that part is taken back
///   out, so the ride carries on from where it was.
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

    /// Past this, Core Motion's change between two absolute readings and the barometer's change over
    /// the same span disagree because Core Motion re-anchored, not because the rider moved (#433).
    /// On 2026-10-16 they disagreed by 300 m. Weather drifts the barometer against Core Motion's GPS
    /// correction too, but 30 m is about 3.6 hPa, more than a front moves it across a ride's stop.
    /// Metres, not a rate: absolute updates come only when Core Motion detects a change, so the
    /// gap between two can be anything.
    static let reanchorToleranceMeters = 30.0

    /// Nil until a source has given one, and after a GPS fix without one while GPS is the source
    /// (#303): an invalid fix is never covered with the altitude before it.
    private(set) var altitude: Double?
    private(set) var source: Source = .gps

    private var isAbsoluteLive = false
    /// The relative barometer's latest reading, nil while it isn't running.
    private var relativeMeters: Double?
    /// Sea-level altitude at the relative barometer's zero.
    private var anchor: Double?
    /// What re-anchors have moved Core Motion's absolute altitude by, taken back out of it. Returns
    /// to about zero when Core Motion steps back.
    private var reanchorOffset = 0.0
    /// Core Motion's last absolute reading as it gave it, with the barometer's at the time, to
    /// check the next one against.
    private var lastAbsolute: AbsoluteReading?

    private struct AbsoluteReading: Equatable, Sendable {
        let meters: Double
        let barometerMeters: Double?
    }

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
        case .absolute(let meters, let accuracy, let barometerMeters):
            guard isAbsoluteLive || (0...Self.trustedAccuracyMeters).contains(accuracy) else { return }
            // Without the barometer either side there's nothing to check against: Core Motion's
            // altitude passes as it is.
            if let lastAbsolute, let barometerMeters, let lastBarometer = lastAbsolute.barometerMeters {
                // Only the disagreement comes out, so whatever the rider climbed across it stays.
                let reanchor = (meters - lastAbsolute.meters) - (barometerMeters - lastBarometer)
                if abs(reanchor) > Self.reanchorToleranceMeters {
                    reanchorOffset -= reanchor
                    let offset = reanchorOffset
                    logger.notice("""
                        altimeter re-anchored \(reanchor, format: .fixed(precision: 1)) m \
                        ±\(accuracy, format: .fixed(precision: 1)); carried across, offset \
                        \(offset, format: .fixed(precision: 1)) m
                        """)
                }
            }
            lastAbsolute = AbsoluteReading(meters: meters, barometerMeters: barometerMeters)
            isAbsoluteLive = true
            altitude = meters + reanchorOffset
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
        reanchorOffset = 0
        lastAbsolute = nil
        relativeMeters = nil
        anchor = nil
        if source == .barometric {
            altitude = nil
            source = .gps
        }
    }
}
