import Foundation
import Testing
@testable import Cyclometer

/// #536: each S15 metric section's builder, against the dashboard sheet the same ride showed at
/// the finish. One ride's readings feed both the live state, a second at a time as the tick feeds
/// it, and the saved track and `Ride` row the builders read. The sheets' numbers must match,
/// minus the current readings S15 drops.
///
/// The ride is 20 minutes, inside the live buffers' hour, so the live charts still hold all of it
/// and their series compare whole.
@MainActor
@Suite("S15 metric section builders")
struct RideDetailMetricsTests {

    private static let start = Date(timeIntervalSince1970: 1_750_000_000)
    private static let seconds = 1_200
    private static let rider = RideEnergy.Rider(kilograms: 75, age: 45, sex: .male)

    /// Rolling terrain with two stops, a strap that drops out now and then, and a cadence sensor
    /// that reads 0 while coasting downhill.
    private static let track: [TrackPointDTO] = (0..<seconds).map { second in
        let wave = sin(Double(second) / 90)
        let isStopped = (300..<330).contains(second) || (800..<815).contains(second)
        let heartRate = second % 97 == 0 ? nil : 130 + Int(25 * wave)
        return TrackPointDTO(
            rideId: UUID(),
            timestamp: start.addingTimeInterval(Double(second)),
            latitude: 45 + Double(second) * 0.00006,
            longitude: -93,
            altitudeMeters: 250 + 20 * wave,
            horizontalAccuracyMeters: 5,
            speedMPS: isStopped ? 0 : 7 - 2 * wave,
            speedSource: .gps,
            heartRateBPM: heartRate,
            heartRateSource: heartRate == nil ? .none : .bleHR,
            cadenceRPM: isStopped || wave < -0.8 ? 0 : 85 + Int(10 * wave)
        )
    }

    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: start,
        distanceMeters: live.distanceMeters, durationSeconds: TimeInterval(seconds)
    )

    /// The dashboard at the finish, fed the track a second at a time as `ActiveRideFeature`'s tick
    /// feeds it.
    private static let live: ActiveRideFeature.State = {
        var state = ActiveRideFeature.State()
        for point in track {
            let time = point.timestamp
            if let speed = point.speedMPS {
                state.speed.speedSamples.append(SpeedSample(time: time, mps: speed))
                state.maxSpeedMPS = max(state.maxSpeedMPS, speed)
                if speed > ActiveRideFeature.stationarySpeedMPS {
                    state.distanceMeters += speed
                    state.speedSampleCount += 1
                }
            }
            if let meters = point.altitudeMeters {
                state.altitudeSamples.append(AltitudeSample(time: time, meters: meters))
                state.elevation.record(altitude: meters, distanceMeters: state.distanceMeters, source: .barometric)
            }
            state.hrSecondsTally.add(point)
            if let bpm = point.heartRateBPM, bpm > 0 {
                state.hrSamples.append(HeartRateSample(time: time, bpm: bpm))
                state.hrSampleCount += 1
                state.hrSampleSum += Double(bpm)
                state.maxHeartRateBPM = max(state.maxHeartRateBPM, bpm)
            }
            if let rpm = point.cadenceRPM {
                state.cadence.cadenceSamples.append(CadenceSample(time: time, rpm: Double(rpm)))
                if rpm > 0 {
                    state.cadence.secondsByRPM[rpm, default: 0] += 1
                    state.cadence.pedalingSampleCount += 1
                    state.cadence.cadenceSum += Double(rpm)
                    state.cadence.maxCadenceRPM = max(state.cadence.maxCadenceRPM, rpm)
                } else {
                    state.cadence.coastingSeconds += 1
                }
            }
            state.elapsedSeconds += 1
        }
        state.energyRider = .rider(rider)
        // What the minute ticks added, which the rebuild reproduces (`CalorieSeriesTests`).
        state.calories = CalorieSeries.rebuild(track: track, through: seconds, rider: rider)
        return state
    }()

    /// What the finish stores on the `Ride` row for `live`, as `fetchRideStats` reads it back.
    private static let stats: RideStats = {
        let finish = RideFinishStats(
            elevation: live.elevation, calorieTrack: track, calories: live.calories,
            elapsedSeconds: live.elapsedSeconds, movingSeconds: live.speedSampleCount,
            distanceMeters: live.distanceMeters, rider: rider
        )
        return RideStats(
            averageSpeedMPS: live.distanceMeters / Double(live.speedSampleCount),
            maxSpeedMPS: live.maxSpeedMPS,
            averageCadenceRPM: live.cadence.averageCadenceRPM,
            maxCadenceRPM: live.cadence.maxCadenceRPM,
            vehiclePassCount: nil,
            averageHeartRateBPM: live.averageHeartRateBPM,
            maxHeartRateBPM: live.maxHeartRateBPM,
            ascentMeters: finish.ascentMeters,
            descentMeters: finish.descentMeters,
            activeKilocalories: finish.activeKilocalories,
            calorieSeries: finish.calorieSeries,
            movingSeconds: live.speedSampleCount,
            cadenceSecondsByRPM: live.cadence.secondsByRPM,
            cadenceCoastingSeconds: live.cadence.coastingSeconds
        )
    }()

    private static let saved = RideDetailTrack(points: track, altitudeSource: .barometric)

    // MARK: Speed, Pace, Time

    @Test("Speed, Pace and Time are the Ride metrics sheet's, without the current speed, plus the splits")
    func rideMetricsMatchTheSheet() {
        var sheet = Self.live.rideMetrics
        sheet.speedMPS = nil
        #expect(sheet.paceSplits.isEmpty, "the live sheet has no splits (#547)")
        sheet.paceSplits = Self.saved.paceSplits[Self.live.unitSystem] ?? []

        let built = RideMetrics.wholeRide(track: Self.saved, stats: Self.stats, summary: Self.summary,
                                          unit: Self.live.unitSystem)
        #expect(built == sheet)
        #expect(built.hasSpeed)
        #expect(built.currentSpeed == .missing)
    }

    @Test("the splits follow the rider's units (#547)", arguments: UnitSystem.allCases)
    func splitsFollowTheUnits(unit: UnitSystem) {
        let built = RideMetrics.wholeRide(track: Self.saved, stats: Self.stats, summary: Self.summary, unit: unit)
        let expected = PaceSplits.splits(Self.track, metersPerSplit: PaceSplits.metersPerSplit(unit))
        #expect(!expected.isEmpty)
        #expect(built.paceSplits == expected)
    }

    @Test("the splits add up to the Moving Time the row stored (#547)")
    func splitsEndOnTheMovingTime() throws {
        // Imperial, where the ride's last 0.99 mi is a partial split; in km its 0.03 left over is
        // too short to be one.
        let built = RideMetrics.wholeRide(track: Self.saved, stats: Self.stats, summary: Self.summary, unit: .imperial)
        #expect(try #require(built.paceSplits.last).isPartial)
        let seconds = built.paceSplits.map(\.movingSeconds).reduce(0, +)
        #expect(abs(seconds - Double(Self.stats.movingSeconds)) < 1e-6)
    }

    @Test("a ride with no moving second has no Speed or Pace, but still a Time")
    func noMovingSecondHasNoSpeed() {
        var stats = Self.stats
        stats.movingSeconds = 0
        let built = RideMetrics.wholeRide(track: RideDetailTrack(), stats: stats, summary: Self.summary, unit: .metric)
        #expect(!built.hasSpeed)
        #expect(built.rideSeconds == Self.seconds)
    }

    // MARK: Active Calories

    @Test("Active Calories is the Calories sheet's series, closed on the finish second with the stored total")
    func caloriesMatchTheSheet() throws {
        let sheet = Self.live.caloriesMetrics
        let built = try #require(CaloriesMetrics.wholeRide(stats: Self.stats, summary: Self.summary))

        // The ride ends on a whole minute, so its closing point stands in for the last tick's.
        #expect(built.series.dropLast() == sheet.series.dropLast())
        #expect(built.series.last?.rideSeconds == sheet.series.last?.rideSeconds)
        #expect(built.total == sheet.total)
        #expect(built.series.last?.kilocalories == Self.stats.activeKilocalories)
        #expect(built.rideSeconds == sheet.rideSeconds)
        #expect(built.footer == sheet.footer)
    }

    @Test("no stored series, no Active Calories")
    func noSeriesHasNoCalories() {
        var stats = Self.stats
        stats.calorieSeries = nil
        #expect(CaloriesMetrics.wholeRide(stats: stats, summary: Self.summary) == nil)
    }

    // MARK: Cadence

    @Test("Cadence and Cadence Zones are the Cadence sheet's")
    func cadenceMatchesTheSheet() throws {
        let built = try #require(RideDetailCadence.wholeRide(
            track: Self.saved, stats: Self.stats, zones: Self.live.cadence.preferences.cadenceZones
        ))
        #expect(built.averageCadence == Self.live.cadence.averageCadenceRPM)
        #expect(built.maxCadence == Self.live.cadence.maxCadenceRPM)
        #expect(built.detail == CadenceDetail(cadence: Self.live.cadence, altitudeSamples: Self.live.altitudeSamples))
    }

    @Test("no cadence sensor, no Cadence sections")
    func noSensorHasNoCadence() {
        var stats = Self.stats
        stats.averageCadenceRPM = nil
        #expect(RideDetailCadence.wholeRide(track: Self.saved, stats: stats, zones: .default) == nil)
    }

    // MARK: Heart Rate

    @Test("Heart Rate and Heart Rate Zones are the Heart Rate sheet's, without the current reading")
    func heartRateMatchesTheSheet() throws {
        var sheet = Self.live.heartRateMetrics
        sheet.bpm = 0
        sheet.zone = 0
        sheet.source = .none

        let built = try #require(HeartRateMetrics.wholeRide(
            track: Self.saved, stats: Self.stats, zoneBounds: Self.live.hrZoneBounds
        ))
        #expect(built == sheet)
        #expect(built.hasZoneTime)
    }

    @Test("no heart rate, no Heart Rate sections")
    func noStrapHasNoHeartRate() {
        var stats = Self.stats
        stats.averageHeartRateBPM = nil
        #expect(HeartRateMetrics.wholeRide(track: Self.saved, stats: stats, zoneBounds: Self.live.hrZoneBounds) == nil)
    }

    // MARK: Elevation, Climbing, Grade

    @Test("Elevation, Climbing and Grade are the Elevation sheet's, without the current readings or the route")
    func elevationMatchesTheSheet() throws {
        var sheet = Self.live.elevationMetrics
        sheet.altitudeMeters = nil
        sheet.gradePercent = nil

        let built = try #require(ElevationMetrics.wholeRide(track: Self.saved, stats: Self.stats,
                                                            unit: Self.live.unitSystem))
        #expect(built == sheet)
        #expect(built.routeProfile == nil)
        #expect(built.steepestClimbPercent != nil)
    }

    @Test("no altitude, no Elevation sections")
    func noAltitudeHasNoElevation() {
        var stats = Self.stats
        stats.ascentMeters = nil
        stats.descentMeters = nil
        #expect(ElevationMetrics.wholeRide(track: Self.saved, stats: stats, unit: .metric) == nil)
    }
}
