import Foundation

/// What S15's metric sections (#536) take from a finished ride's saved track, worked out once
/// when it loads rather than on every body pass: the dashboard's chart series over the whole ride,
/// the seconds at each heart rate the zones sort, and the elevation the live tracker would have
/// ended on.
///
/// The `Ride` row's stored numbers (`RideStats`) are used wherever the dashboard stored them at
/// the finish. This is only what the row doesn't keep.
struct RideDetailTrack: Equatable, Sendable {
    var speed: [SpeedSample] = []
    var cadence: [CadenceSample] = []
    var heartRate: [HeartRateSample] = []
    var altitude: [AltitudeSample] = []
    /// `RideDetailSeries.secondsByBPM`: the live Heart Rate sheet's tally, from the same points.
    var secondsByBPM: [Int: Int] = [:]
    var highestMeters: Double?
    var lowestMeters: Double?
    var steepestClimbPercent: Double?
    var steepestDescentPercent: Double?
    /// What the map sheet's route coloring and stops read (#537).
    var map = RideMapTrack(segments: [])
}

// In an extension, so the struct keeps its memberwise initializer.
extension RideDetailTrack {
    /// The series are `WatermarkSeed`'s, unwindowed; the elevation is `ElevationTracker`'s
    /// replay. The track doesn't record which source each altitude came from, so
    /// `altitudeSource` is the caller's guess, as the finish-stats backfill makes it.
    init(points: [TrackPointDTO], altitudeSource: AltitudeResolver.Source) {
        if let series = WatermarkSeed(wholeRide: points) {
            speed = series.speed
            cadence = series.cadence
            heartRate = series.heartRate
            altitude = series.altitude
        }
        secondsByBPM = RideDetailSeries.secondsByBPM(points)
        let elevation = ElevationTracker.replaying(savedTrack: points, source: altitudeSource)
        highestMeters = elevation.highestMeters
        lowestMeters = elevation.lowestMeters
        steepestClimbPercent = elevation.steepestClimbPercent
        steepestDescentPercent = elevation.steepestDescentPercent
        map = RideMapTrack(points: points)
    }
}

// MARK: - Builders

// One per dashboard sheet: the sheet's metrics over the whole ride, with no current reading.
// Each is nil when the ride recorded nothing for its sections, which S15 then leaves out
// (UX.md §S15).

extension RideMetrics {
    /// Speed, Pace and Time. Never nil: a ride always has a time. Speed and Pace are left out by
    /// the view for a ride with no moving second (`hasSpeed`).
    static func wholeRide(track: RideDetailTrack, stats: RideStats, summary: RideListSummary,
                          unit: UnitSystem) -> RideMetrics {
        RideMetrics(
            speedMPS: nil,
            averageSpeedMPS: stats.averageSpeedMPS,
            maxSpeedMPS: stats.maxSpeedMPS,
            distanceMeters: summary.distanceMeters,
            movingSeconds: stats.movingSeconds,
            rideSeconds: Int(summary.durationSeconds),
            unit: unit,
            speedHistory: track.speed,
            altitudeHistory: track.altitude
        )
    }

    /// Whether the ride had a moving second, so an average speed and pace.
    var hasSpeed: Bool { movingSeconds > 0 }
}

extension CaloriesMetrics {
    /// Active Calories: the series stored at the finish (#536). Nil without one, as for a ride
    /// with no body mass in Health.
    static func wholeRide(stats: RideStats, summary: RideListSummary) -> CaloriesMetrics? {
        guard let series = stats.calorieSeries, !series.isEmpty else { return nil }
        // `rider` only explains an empty series, which this never is.
        return CaloriesMetrics(series: series, rideSeconds: Int(summary.durationSeconds))
    }
}

/// The Cadence sheet's inputs (`CadenceList`), which take the average and max apart from
/// `CadenceDetail`.
struct RideDetailCadence: Equatable {
    var averageCadence: Int
    var maxCadence: Int
    var zones: CadenceZoneBoundaries
    var detail: CadenceDetail

    /// Cadence and Cadence Zones. The zone time is the tally the ride stored per rpm (#340),
    /// sorted into `zones` as they are now. Nil for a ride with no cadence sensor.
    static func wholeRide(track: RideDetailTrack, stats: RideStats,
                          zones: CadenceZoneBoundaries) -> RideDetailCadence? {
        guard let average = stats.averageCadenceRPM else { return nil }
        return RideDetailCadence(
            averageCadence: average,
            maxCadence: stats.maxCadenceRPM ?? 0,
            zones: zones,
            detail: CadenceDetail(
                cadenceSamples: track.cadence,
                altitudeSamples: track.altitude,
                zoneSeconds: zones.zoneSeconds(stats.cadenceSecondsByRPM),
                coastingSeconds: stats.cadenceCoastingSeconds
            )
        )
    }
}

extension HeartRateMetrics {
    /// Heart Rate and Heart Rate Zones, sorted into `zoneBounds` as they are now. Nil for a ride
    /// with no heart rate.
    static func wholeRide(track: RideDetailTrack, stats: RideStats,
                          zoneBounds: [ClosedRange<Int>]) -> HeartRateMetrics? {
        guard let average = stats.averageHeartRateBPM else { return nil }
        return HeartRateMetrics(
            averageBPM: average,
            maxBPM: stats.maxHeartRateBPM ?? 0,
            zoneBounds: zoneBounds,
            zoneSeconds: RideDetailSeries.zoneSeconds(track.secondsByBPM, zoneBounds: zoneBounds),
            history: track.heartRate,
            altitudeHistory: track.altitude
        )
    }
}

extension ElevationMetrics {
    /// Elevation, Climbing and Grade, without the sheet's Route part. Ascent and descent are the
    /// totals stored at the finish (#460); the range and steepest grades are the replay's. Nil for
    /// a ride with no altitude.
    static func wholeRide(track: RideDetailTrack, stats: RideStats, unit: UnitSystem) -> ElevationMetrics? {
        guard let ascent = stats.ascentMeters else { return nil }
        return ElevationMetrics(
            ascentMeters: ascent,
            descentMeters: stats.descentMeters ?? 0,
            highestMeters: track.highestMeters,
            lowestMeters: track.lowestMeters,
            steepestClimbPercent: track.steepestClimbPercent,
            steepestDescentPercent: track.steepestDescentPercent,
            history: track.altitude,
            unit: unit
        )
    }
}
