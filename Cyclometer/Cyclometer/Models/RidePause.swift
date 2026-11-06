import Foundation

/// One pause in a ride, manual or auto, as `ActiveRideFeature` records it (#537). S15's map draws
/// each closed pause as a stop.
///
/// Recorded rather than read from `TrackPointDTO.segmentIndex`: the index goes up on every resume,
/// but also when a ride killed while recording comes back, where nobody paused. GPS gaps don't
/// move it either way.
struct RidePause: Codable, Sendable, Equatable {
    var startedAt: Date
    /// Nil while the ride is still paused. A finished ride's last pause stays open: every
    /// finish comes from a pause, and that one is the end of the ride, not a stop.
    var endedAt: Date?
    /// Auto-pause (#82) rather than the Pause button.
    var isAuto: Bool
}

extension [RidePause] {
    /// Opens a pause, unless one is already open.
    mutating func open(at date: Date, isAuto: Bool) {
        guard last?.endedAt != nil || isEmpty else { return }
        append(RidePause(startedAt: date, endedAt: nil, isAuto: isAuto))
    }

    /// Closes the open pause, if there is one.
    mutating func close(at date: Date) {
        guard let index = indices.last, self[index].endedAt == nil else { return }
        self[index].endedAt = date
    }
}
