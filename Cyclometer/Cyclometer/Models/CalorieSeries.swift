import Foundation

/// The ride's active-energy estimate after `rideSeconds` of recording time: one point a minute of
/// W23's series, behind the Calories sheet's chart (#465).
struct CaloriePoint: Equatable, Sendable {
    var rideSeconds: Int
    var kilocalories: Double
    var method: RideEnergy.Estimate.Method
}

/// What the live estimate knows about the rider (#465): read from Health once at ride start, as
/// `RideHealthWorkout.write` reads it. Without a body mass there is no estimate (#276).
enum EnergyRiderStatus: Equatable, Sendable {
    case loading
    case noBodyMass
    case rider(RideEnergy.Rider)

    init(_ rider: RideEnergy.Rider?) {
        self = rider.map { .rider($0) } ?? .noBodyMass
    }

    var rider: RideEnergy.Rider? {
        guard case .rider(let rider) = self else { return nil }
        return rider
    }
}

/// W23's calorie series (#465). Live, the dashboard adds a point each minute from
/// `RideEnergy.activeKilocalories` over the track so far, the function and inputs the ride's Health
/// workout uses. A ride resumed after a kill rebuilds the minutes before it from its track here.
enum CalorieSeries {
    static let intervalSeconds = 60

    /// One point per whole minute of recording time through `seconds`, each the estimate over the
    /// track recorded by then.
    ///
    /// The track has no recording clock of its own, so a point's recording second is worked out
    /// from its timestamp within its segment, after the earlier segments' spans: a pause is a
    /// segment boundary and adds nothing. The distance by each minute is the odometer's (#262), its
    /// points' speeds above the stationary threshold, a second each. Past the track's end, as when
    /// the fix dropped out, a minute takes the whole track, and `activeKilocalories` costs the
    /// seconds it misses at the average speed, as it does at finish.
    static func rebuild(track: [TrackPointDTO], through seconds: Int, rider: RideEnergy.Rider) -> [CaloriePoint] {
        let offsets = recordingOffsets(track)
        var points: [CaloriePoint] = []
        var end = 0
        var distanceMeters = 0.0
        for minute in stride(from: intervalSeconds, through: seconds, by: intervalSeconds) {
            while end < track.count, offsets[end] < minute {
                if let speed = track[end].speedMPS, speed > ActiveRideFeature.stationarySpeedMPS {
                    distanceMeters += speed
                }
                end += 1
            }
            let estimate = RideEnergy.activeKilocalories(
                trackPoints: Array(track[..<end]),
                movingSeconds: TimeInterval(minute),
                distanceMeters: distanceMeters,
                rider: rider
            )
            points.append(CaloriePoint(rideSeconds: minute, kilocalories: estimate.kilocalories, method: estimate.method))
        }
        return points
    }

    /// Each point's second of recording time, from zero: its seconds into its segment, after the
    /// earlier segments' spans, first point to last, inclusive.
    static func recordingOffsets(_ track: [TrackPointDTO]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(track.count)
        var base = 0
        for segment in TrackPointDTO.segments(of: track) {
            guard let first = segment.first?.timestamp else { continue }
            var span = 0
            for point in segment {
                span = Int(point.timestamp.timeIntervalSince(first).rounded())
                offsets.append(base + span)
            }
            base += span + 1
        }
        return offsets
    }

    /// The average burn over W3's moving time (#465), or nil before the rider has moved.
    static func kilocaloriesPerHour(_ kilocalories: Double, movingSeconds: Int) -> Double? {
        guard movingSeconds > 0 else { return nil }
        return kilocalories * 3600 / Double(movingSeconds)
    }
}
