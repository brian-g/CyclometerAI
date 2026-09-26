import Foundation
import Testing
@testable import Cyclometer

@Suite("RideEnergy")
struct RideEnergyTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let rider = 75.0
    /// Rider plus `RideEnergy.bikeKilograms`.
    private static let mass = 85.0
    /// Roughly metres per degree of latitude — the MET cases only need their speed inside a band.
    private static let metersPerDegree = 111_000.0

    /// One point a second for `seconds` seconds, riding due north at `speed` (horizontal) while
    /// the altitude rises at `climbRate` m/s. `reportedSpeed` is what the speed source said, which
    /// can differ from the geometry: nil is a second with no speed reading.
    private func track(
        seconds: Int,
        speed: Double,
        reportedSpeed: Double?? = .none,
        climbRate: Double = 0,
        segmentIndex: Int = 0,
        startingAt start: Date = start,
        stepSeconds: Double = 1,
        heartRate: Int? = nil
    ) -> [TrackPointDTO] {
        (0...seconds).map { second in
            let elapsed = Double(second) * stepSeconds
            return TrackPointDTO(
                rideId: UUID(),
                timestamp: start.addingTimeInterval(elapsed),
                latitude: 43 + speed * elapsed / Self.metersPerDegree,
                longitude: -89,
                altitudeMeters: 100 + climbRate * elapsed,
                horizontalAccuracyMeters: 5,
                speedMPS: reportedSpeed ?? speed,
                speedSource: .gps,
                heartRateBPM: heartRate,
                heartRateSource: heartRate == nil ? .none : .bleHR,
                cadenceRPM: nil,
                powerWatts: nil,
                segmentIndex: segmentIndex
            )
        }
    }

    /// Physics unless a test says otherwise: a rider with no age or sex has no heart-rate model.
    private func estimate(
        _ points: [TrackPointDTO], movingSeconds: TimeInterval? = nil, distance: Double = 0,
        rider: RideEnergy.Rider = RideEnergy.Rider(kilograms: RideEnergyTests.rider)
    ) -> RideEnergy.Estimate {
        let covered = zip(points, points.dropFirst())
            .filter { $0.segmentIndex == $1.segmentIndex }
            .reduce(0) { $0 + $1.1.timestamp.timeIntervalSince($1.0.timestamp) }
        return RideEnergy.activeKilocalories(
            trackPoints: points, movingSeconds: movingSeconds ?? covered,
            distanceMeters: distance, rider: rider
        )
    }

    private func energy(_ points: [TrackPointDTO], movingSeconds: TimeInterval? = nil, distance: Double = 0) -> Double {
        estimate(points, movingSeconds: movingSeconds, distance: distance).kilocalories
    }

    /// kcal a MET value gives a 75 kg rider over `seconds`, resting metabolism excluded.
    private func metKilocalories(_ met: Double, seconds: Double) -> Double {
        (met - 1) * Self.rider * seconds / 3600
    }

    // MARK: - Physics

    @Test("an hour on the flat at 30 km/h is air plus rolling resistance over the drivetrain: ≈ 547 kcal")
    func flatRoad() {
        let speed = 30 / 3.6
        // 113.4 W of air + 34.7 W of rolling = 148.2 W at the wheel, 152.0 W at the pedals.
        let watts = (0.5 * 1.225 * 0.32 * pow(speed, 3) + 0.005 * Self.mass * 9.806_65 * speed) / 0.975
        let result = energy(track(seconds: 3_600, speed: speed))
        #expect(abs(result - watts * 3_600 / 1_000) < 1e-6)
        #expect(abs(result - 547.0) < 0.5)
    }

    @Test("a climb adds exactly the work of lifting rider and bike through its height")
    func climbAddsPotentialEnergy() {
        let speed = 5.0, climbRate = 0.3   // 6%
        // Flat either side, longer than the smoothing half-window, so the smoothed profile
        // reaches both the bottom and the top of the climb.
        let lead = track(seconds: 60, speed: speed)
        let climb = track(seconds: 600, speed: speed, climbRate: climbRate, startingAt: Self.start.addingTimeInterval(60))
        let top = climb.last!.altitudeMeters
        let tail = track(seconds: 60, speed: speed, startingAt: Self.start.addingTimeInterval(660))
            .map { var point = $0; point.altitudeMeters = top; return point }
        let hilly = lead + climb.dropFirst() + tail.dropFirst()
        let flat = track(seconds: 720, speed: speed)

        let height = 600 * climbRate   // 180 m
        let expected = Self.mass * 9.806_65 * height / 0.975 / 1_000   // ≈ 153.9 kcal
        #expect(abs(energy(hilly) - energy(flat) - expected) < 1e-6)
    }

    @Test("a descent steep enough to coast adds nothing — not negative work paying back a climb")
    func coastingDescentIsZero() {
        // 12 m/s down 10%: gravity supplies 1,000 W against the 389 W air and rolling take, and
        // still more than half that at the smoothed ends of the track.
        let descent = track(seconds: 300, speed: 12, climbRate: -1.2)
        #expect(energy(descent) == 0)
    }

    @Test("a standing second is not riding: a stationary track adds nothing")
    func stationaryIsZero() {
        #expect(energy(track(seconds: 60, speed: 0)) == 0)
        #expect(energy([]) == 0)
        #expect(energy([], movingSeconds: 0) == 0)
    }

    @Test("time between two segments is a pause and is never counted")
    func pauseIsNotCounted() {
        let first = track(seconds: 60, speed: 5)
        let second = track(seconds: 60, speed: 5, segmentIndex: 1, startingAt: Self.start.addingTimeInterval(660))
        let one = energy(first)
        #expect(one > 0)
        #expect(abs(energy(first + second) - 2 * one) < 1e-9)
    }

    // MARK: - Where the track can't say more

    /// Joules on the flat at `speed` for `seconds`: the same formula as the flat-road test.
    private func flatKilocalories(speed: Double, seconds: Double) -> Double {
        (0.5 * 1.225 * 0.32 * pow(speed, 3) + 0.005 * Self.mass * 9.806_65 * speed) / 0.975 * seconds / 1_000
    }

    @Test("a gap longer than five seconds is costed on the flat at the straight-line speed across it")
    func gapIsCostedFlat() {
        // Two fixes 10 s and 50 m apart: 5 m/s. Loose only because the fixture's metres per degree is.
        let gap = track(seconds: 1, speed: 5, stepSeconds: 10)
        let expected = flatKilocalories(speed: 5, seconds: 10)
        #expect(abs(energy(gap) - expected) < expected * 0.01)
    }

    @Test("smoothing never reaches across a gap: altitude either side of it isn't climbing next to it")
    func gapDoesNotBlendAltitude() {
        // 60 s, a 30 s dropout, then 60 s more. The only difference between the two rides is that
        // the second stretch of one is 30 m higher — which the dropout hides, and a window reaching
        // across it would turn into a grade on the seconds either side.
        func ride(secondStretchRise: Double) -> [TrackPointDTO] {
            let before = track(seconds: 60, speed: 5)
            let after = track(seconds: 60, speed: 5, startingAt: Self.start.addingTimeInterval(90))
                .map { point in
                    var point = point
                    point.latitude += 450 / Self.metersPerDegree
                    point.altitudeMeters += secondStretchRise
                    return point
                }
            return before + after
        }
        let level = energy(ride(secondStretchRise: 0), movingSeconds: 150)
        #expect(level > 0)
        #expect(abs(energy(ride(secondStretchRise: 30), movingSeconds: 150) - level) < 1e-9)
    }

    @Test("a second with no speed reading is stationary, as the ride's own odometer counts it (#262)")
    func missingSpeedIsStationary() {
        // The fixes still move 5 m a second: GPS wander at a stop looks exactly like this.
        let points = track(seconds: 60, speed: 5, reportedSpeed: .some(nil))
        #expect(energy(points) == 0)
    }

    @Test("a grade too steep to be road is GPS altitude noise, and is costed as flat")
    func implausibleGradeIsCostedFlat() {
        // 60%: even the smoothed ends of the track, which see half the slope, are past 25%.
        let wall = track(seconds: 300, speed: 5, climbRate: 3)
        #expect(abs(energy(wall) - energy(track(seconds: 300, speed: 5))) < 1e-9)
    }

    @Test("recording time the track doesn't reach is costed flat at the ride's average speed")
    func uncoveredTimeIsCostedFlat() {
        // 60 s of track in 120 s of recording, 600 m in all: the missing minute at 5 m/s.
        let points = track(seconds: 60, speed: 5)
        let result = energy(points, movingSeconds: 120, distance: 600)
        #expect(abs(result - 2 * energy(points)) < 1e-9)
    }

    @Test("a ride with no track at all gets MET at its average speed")
    func noTrackUsesMET() {
        // Location denied, speed from a wheel sensor. 5.5 m/s is 12.3 mph: 8.0 MET.
        let result = estimate([], movingSeconds: 3_600, distance: 5.5 * 3_600)
        #expect(abs(result.kilocalories - metKilocalories(8.0, seconds: 3_600)) < 1e-9)   // 525 kcal
        #expect(result.method == .met)
    }

    // MARK: - Heart rate (Keytel 2005)

    private static let man = RideEnergy.Rider(kilograms: 80, age: 45, sex: .male)
    private static let woman = RideEnergy.Rider(kilograms: 60, age: 35, sex: .female)

    @Test("a man at 120 bpm: Keytel's 45.59 kJ/min gross is 10.90 kcal/min, 9.56 active")
    func keytelMale() {
        let ride = estimate(track(seconds: 900, speed: 5, heartRate: 120), movingSeconds: 900, rider: Self.man)
        let gross = (-55.0969 + 0.6309 * 120 + 0.1988 * 80 + 0.2017 * 45) / 4.184
        #expect(ride.method == .heartRate)
        #expect(abs(ride.kilocalories - (gross - 80.0 / 60) * 15) < 1e-9)
        #expect(abs(ride.kilocalories - 143.4) < 0.1)
    }

    @Test("a woman at 130 bpm: Keytel's 32.75 kJ/min gross is 7.83 kcal/min, 6.83 active")
    func keytelFemale() {
        let ride = estimate(track(seconds: 900, speed: 5, heartRate: 130), movingSeconds: 900, rider: Self.woman)
        let gross = (-20.4022 + 0.4472 * 130 - 0.1263 * 60 + 0.074 * 35) / 4.184
        #expect(ride.method == .heartRate)
        #expect(abs(ride.kilocalories - (gross - 60.0 / 60) * 15) < 1e-9)
    }

    @Test("a resting heart rate is no activity, not negative activity")
    func restingHeartRateClampsToZero() {
        // 50 bpm: 1.4 kJ/min gross is below the man's own resting 1.33 kcal/min.
        let ride = estimate(track(seconds: 300, speed: 5, heartRate: 50), movingSeconds: 300, rider: Self.man)
        #expect(ride == RideEnergy.Estimate(kilocalories: 0, method: .heartRate))
    }

    /// 100 seconds of recording, the first `withHeartRate` points carrying 120 bpm.
    private func partlyCovered(withHeartRate readings: Int) -> [TrackPointDTO] {
        track(seconds: 99, speed: 5).enumerated().map { index, point in
            var point = point
            if index < readings { point.heartRateBPM = 120; point.heartRateSource = .bleHR }
            return point
        }
    }

    @Test("readings on half the ride are a strap: the heart-rate model; fewer are a Watch's samples: physics")
    func coverageThreshold() {
        #expect(estimate(partlyCovered(withHeartRate: 50), movingSeconds: 100, rider: Self.man).method == .heartRate)
        #expect(estimate(partlyCovered(withHeartRate: 49), movingSeconds: 100, rider: Self.man).method == .physics)
    }

    @Test("a second without a reading is costed at the ride's mean, not at nothing")
    func missingReadingsCostedAtMean() {
        let partly = estimate(partlyCovered(withHeartRate: 60), movingSeconds: 100, rider: Self.man)
        let fully = estimate(partlyCovered(withHeartRate: 100), movingSeconds: 100, rider: Self.man)
        #expect(partly.method == .heartRate)
        #expect(abs(partly.kilocalories - fully.kilocalories) < 1e-9)
    }

    @Test("without a sex or an age there is no equation to use, and the ride falls back to physics")
    func missingSexOrAgeFallsBackToPhysics() {
        let points = track(seconds: 300, speed: 5, heartRate: 140)
        let physics = estimate(points, movingSeconds: 300)
        #expect(physics.method == .physics)
        for rider in [RideEnergy.Rider(kilograms: 75, age: 45, sex: nil),
                      RideEnergy.Rider(kilograms: 75, age: nil, sex: .female)] {
            #expect(estimate(points, movingSeconds: 300, rider: rider) == physics)
        }
    }

    @Test("MET follows the Compendium's speed bands, and is nil at a standstill",
          arguments: [(9.9, 4.0), (10.5, 6.8), (13.0, 8.0), (15.0, 10.0), (17.0, 12.0), (25.0, 16.8)])
    func metBands(mph: Double, met: Double) {
        let speed = Measurement(value: mph, unit: UnitSpeed.milesPerHour).converted(to: .metersPerSecond).value
        #expect(RideEnergy.met(speed: speed) == met)
    }

    @Test("no MET at or below the stationary threshold")
    func metAtStandstill() {
        #expect(RideEnergy.met(speed: ActiveRideFeature.stationarySpeedMPS) == nil)
    }
}
