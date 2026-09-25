import Foundation

/// The active energy a finished ride's `HKWorkout` carries (#276), estimated from the recorded
/// track because the app has no power meter. With it the workout earns Move credit, not just
/// Exercise (UX.md §S10).
///
/// **Physics first.** Each 1 Hz interval's pedal power is the sum of the forces the rider works
/// against — air, rolling resistance, gravity — over the drivetrain's efficiency, clamped at zero
/// so a coasting descent adds nothing rather than paying back the climb. Mechanical work converts
/// to metabolic energy one-for-one in kilojoules to kilocalories: a rider is about 24% efficient,
/// and 1 kcal is 4.184 kJ, so the two factors cancel.
///
/// **MET where physics can't be trusted.** An interval with no speed, a gap in the track longer
/// than `maxPhysicsGapSeconds` (a tunnel), or a grade too steep to be real altitude uses the
/// Compendium's speed-banded MET instead; so does recording time the track doesn't cover at all
/// (a ride recorded on a CSC sensor with location denied).
///
/// Pure, so every constant below is pinned by `RideEnergyTests`.
enum RideEnergy {

    /// The issue's default (#276). A constant, not a preference: nothing in the app can set it.
    static let bikeKilograms = 10.0
    /// Drag area of a rider on the hoods, m².
    static let dragAreaSquareMeters = 0.32
    /// Clincher tyre on pavement.
    static let rollingResistance = 0.005
    /// Sea-level air at 15 °C, kg/m³.
    static let airDensity = 1.225
    /// Chain, bearings and derailleur: pedal power = wheel power ÷ (1 − this).
    static let drivetrainLoss = 0.025
    static let gravity = 9.806_65

    /// Longer than this between two points is a dropout, and the speeds either side say nothing
    /// about what happened in between.
    static let maxPhysicsGapSeconds: TimeInterval = 5

    /// Steeper than this, over one interval of smoothed altitude, is GPS altitude noise rather
    /// than road: few paved climbs pass 20%.
    static let maxPlausibleGrade = 0.25

    /// GPS altitude jitters by metres from one fix to the next, and summing the raw deltas would
    /// credit a flat ride with climbing. A centred average over ~31 s at 1 Hz takes that out.
    static let altitudeSmoothingHalfWindow = 15

    /// Active kilocalories for a ride.
    ///
    /// - Parameters:
    ///   - trackPoints: The persisted track, ascending by time. Pauses are segment boundaries,
    ///     so the time between two segments is never counted.
    ///   - movingSeconds: Recording time (`Ride.durationSeconds`), which excludes pauses.
    ///   - distanceMeters: The ride's distance, for the average speed of time the track misses.
    static func activeKilocalories(
        trackPoints: [TrackPointDTO],
        movingSeconds: TimeInterval,
        distanceMeters: Double,
        riderKilograms: Double
    ) -> Double {
        let mass = riderKilograms + bikeKilograms
        var workJoules = 0.0
        var fallbackKilocalories = 0.0
        var coveredSeconds = 0.0

        for segment in TrackPointDTO.segments(of: trackPoints) where segment.count > 1 {
            let altitude = RouteTerrain.movingAverage(
                segment.map(\.altitudeMeters), halfWindow: altitudeSmoothingHalfWindow
            )
            for index in segment.indices.dropFirst() {
                let start = segment[index - 1], end = segment[index]
                let seconds = end.timestamp.timeIntervalSince(start.timestamp)
                guard seconds > 0 else { continue }
                coveredSeconds += seconds

                if seconds <= maxPhysicsGapSeconds,
                   let startSpeed = start.speedMPS, let endSpeed = end.speedMPS {
                    let speed = (startSpeed + endSpeed) / 2
                    // A stationary second is not riding (#262), and has no run to take a grade over.
                    guard speed > ActiveRideFeature.stationarySpeedMPS else { continue }
                    let rise = altitude[index] - altitude[index - 1]
                    if abs(rise / (speed * seconds)) <= maxPlausibleGrade {
                        workJoules += pedalWatts(speed: speed, climbRate: rise / seconds, mass: mass) * seconds
                        continue
                    }
                }
                let straightLine = RouteGeometry.distanceMeters([
                    RouteCoordinate(latitude: start.latitude, longitude: start.longitude),
                    RouteCoordinate(latitude: end.latitude, longitude: end.longitude),
                ])
                fallbackKilocalories += metKilocalories(speed: straightLine / seconds, seconds: seconds, riderKilograms: riderKilograms)
            }
        }

        let uncoveredSeconds = movingSeconds - coveredSeconds
        if uncoveredSeconds > 0, movingSeconds > 0 {
            fallbackKilocalories += metKilocalories(
                speed: distanceMeters / movingSeconds, seconds: uncoveredSeconds, riderKilograms: riderKilograms
            )
        }

        return workJoules / 1000 + fallbackKilocalories
    }

    /// Power at the pedals to hold `speed` while rising at `climbRate` m/s, never negative.
    static func pedalWatts(speed: Double, climbRate: Double, mass: Double) -> Double {
        let aero = 0.5 * airDensity * dragAreaSquareMeters * speed * speed * speed
        let rolling = rollingResistance * mass * gravity * speed
        let climbing = mass * gravity * climbRate
        return max(0, (aero + rolling + climbing) / (1 - drivetrainLoss))
    }

    /// Active kilocalories at the Compendium MET for `speed`. MET counts resting metabolism as 1,
    /// and HealthKit's active energy excludes it, so one MET comes off.
    static func metKilocalories(speed: Double, seconds: TimeInterval, riderKilograms: Double) -> Double {
        guard let met = met(speed: speed) else { return 0 }
        return (met - 1) * riderKilograms * seconds / 3600
    }

    /// 2024 Adult Compendium of Physical Activities, bicycling codes 01010–01060
    /// (pacompendium.com/bicycling). Nil at or below the app's stationary threshold (#262).
    static func met(speed: Double) -> Double? {
        guard speed > ActiveRideFeature.stationarySpeedMPS else { return nil }
        let mph = Measurement(value: speed, unit: UnitSpeed.metersPerSecond).converted(to: .milesPerHour).value
        switch mph {
        case ..<10: return 4.0   // 01010
        case ..<12: return 6.8   // 01020
        case ..<14: return 8.0   // 01030
        case ..<16: return 10.0  // 01040
        case ..<20: return 12.0  // 01050
        default:    return 16.8  // 01060
        }
    }
}
