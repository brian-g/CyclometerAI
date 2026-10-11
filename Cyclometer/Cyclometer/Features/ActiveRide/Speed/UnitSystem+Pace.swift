import Foundation

/// Pace (W11, #144). Apart from `UnitSystem.swift` because it reads the ride's stationary
/// threshold, and `UnitSystem` is shared with the widget extension, which has no ride (#306).
extension UnitSystem {
    /// Seconds required to cover one distance unit (mile or kilometer) at the
    /// given speed. `nil` when the rider is stopped — at or below
    /// `ActiveRideFeature.stationarySpeedMPS`, not only at zero: a stationary
    /// phone's GPS reports a few cm/s, which read as a 500-minute pace (#144).
    /// Built on `speed(fromMPS:)` rather than a separate factor, so pace and
    /// speed can never disagree about the conversion.
    func paceSeconds(fromMPS mps: Double) -> Double? {
        guard mps > ActiveRideFeature.stationarySpeedMPS else { return nil }
        return 3600.0 / speed(fromMPS: mps)
    }

    /// Pace label ("/mi", "/km") to pair with `paceSeconds(fromMPS:)`.
    var paceLabel: String { "/" + distanceLabel }

    /// Pace as W11 shows it, "5:30": whole seconds, minutes unpadded and uncapped. `nil` where
    /// `paceSeconds(fromMPS:)` is.
    func formattedPace(fromMPS mps: Double) -> String? {
        guard let paceSeconds = paceSeconds(fromMPS: mps) else { return nil }
        let seconds = Int(paceSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Pace in words, "5 minutes, 30 seconds per kilometer" (#144): VoiceOver reads "5:30" digit by
    /// digit, as it does a time (#361). `nil` where `paceSeconds(fromMPS:)` is.
    func spokenPace(fromMPS mps: Double) -> String? {
        guard let paceSeconds = paceSeconds(fromMPS: mps) else { return nil }
        let time = Duration.seconds(Int(paceSeconds))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return time + (self == .metric ? " per kilometer" : " per mile")
    }
}
