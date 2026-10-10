import Foundation
import Testing
@testable import Cyclometer

@Suite("ElevationGainTally")
struct ElevationGainTallyTests {

    @Test("jitter inside the noise floor about a level road banks nothing")
    func jitterBanksNothing() {
        var tally = ElevationGainTally()
        // ±0.4 m: 0.8 m peak to peak, inside a 1 m floor.
        for index in 0..<200 { tally.add(200 + (index.isMultiple(of: 2) ? 0.4 : -0.4), noiseMeters: 1) }
        #expect(tally.gainMeters == 0)
        #expect(tally.lossMeters == 0)
    }

    @Test("a climb in steps far below the floor still counts in full")
    func smallStepsAccumulate() {
        var tally = ElevationGainTally()
        // To 501 m, a whole number of 3 m floors: a tail short of one is never banked.
        for step in 0...1_002 { tally.add(Double(step) * 0.5, noiseMeters: 3) }
        #expect(tally.gainMeters == 501)
        #expect(tally.lossMeters == 0)
    }

    @Test("a climb and a descent bank separately")
    func climbThenDescent() {
        var tally = ElevationGainTally()
        for altitude in [100.0, 110, 120, 105, 90] { tally.add(altitude, noiseMeters: 1) }
        #expect(tally.gainMeters == 20)
        #expect(tally.lossMeters == 30)
    }
}

@Suite("ElevationTracker")
struct ElevationTrackerTests {

    /// Fed once a metre-per-second second: `altitudes[i]` at `i * spacing` metres.
    private func tracker(
        _ altitudes: [Double], spacing: Double = 10, source: AltitudeResolver.Source = .barometric
    ) -> ElevationTracker {
        var tracker = ElevationTracker()
        for (index, altitude) in altitudes.enumerated() {
            tracker.record(altitude: altitude, distanceMeters: Double(index) * spacing, source: source)
        }
        return tracker
    }

    @Test("grade is nil until the ride has covered the grade window")
    func gradeNeedsAFullWindow() {
        // 9 × 10 m = 90 m: short of 100 m.
        #expect(tracker((0..<10).map { Double($0) }).gradePercent == nil)
        #expect(tracker((0...10).map { Double($0) }).gradePercent != nil)
    }

    @Test("grade is rise over run across the last window")
    func gradeIsRiseOverRun() throws {
        // Flat for 200 m, then 5 m up per 100 m.
        let altitudes = Array(repeating: 100.0, count: 21) + (1...10).map { 100 + Double($0) * 0.5 }
        let grade = try #require(tracker(altitudes).gradePercent)
        #expect(abs(grade - 5) < 1e-9)
    }

    @Test("a descent reads negative, and the steepest of each way is kept")
    func steepestBothWays() throws {
        let up = (0...20).map { Double($0) }                     // +10%
        let down = (1...20).map { 20 - Double($0) * 0.4 }        // -4%
        let tracker = tracker(up + down)
        #expect(try #require(tracker.gradePercent) < 0)
        #expect(abs(try #require(tracker.steepestClimbPercent) - 10) < 1e-9)
        #expect(abs(try #require(tracker.steepestDescentPercent) + 4) < 1e-9)
    }

    @Test("a grade steeper than any road is dropped and the last believable one kept")
    func implausibleGradeIsDropped() throws {
        var altitudes = (0...10).map { Double($0) * 0.3 }        // +3%
        altitudes.append(altitudes.last! + 40)                   // a 40 m jump in 10 m
        let tracker = tracker(altitudes)
        #expect(abs(try #require(tracker.gradePercent) - 3) < 1e-9)
    }

    @Test("stopped, the grade holds")
    func gradeHoldsWhileStopped() throws {
        var tracker = tracker((0...10).map { Double($0) * 0.6 })
        let grade = tracker.gradePercent
        // Ten seconds at the same distance, the altitude wandering.
        for second in 0..<10 { tracker.record(altitude: 6 + Double(second), distanceMeters: 100, source: .barometric) }
        #expect(tracker.gradePercent == grade)
    }

    @Test("GPS takes the route's 3 m floor, the barometer 1 m")
    func floorFollowsSource() {
        let rollers = (0..<100).map { 100 + ($0.isMultiple(of: 2) ? 0.0 : 2.0) }
        #expect(tracker(rollers, source: .gps).ascentMeters == 0)
        #expect(tracker(rollers, source: .barometric).ascentMeters == 100)
    }

    @Test("high and low follow the ride")
    func highAndLow() {
        let tracker = tracker([120, 140, 90, 110])
        #expect(tracker.highestMeters == 140)
        #expect(tracker.lowestMeters == 90)
    }

    @Test("a resume's seed adds to what the ride has done since, whenever it lands")
    func seedAdds() throws {
        var tracker = tracker([100, 110])
        let seed = try #require(ElevationTracker.Seed(savedAltitudes: [50, 80, 60, 200]))
        tracker.seed(seed)
        #expect(tracker.ascentMeters == 30 + 140 + 10)
        #expect(tracker.descentMeters == 20)
        #expect(tracker.highestMeters == 200)
        #expect(tracker.lowestMeters == 50)
    }

    @Test("a saved track with no altitude seeds nothing")
    func emptySeed() {
        #expect(ElevationTracker.Seed(savedAltitudes: []) == nil)
    }
}

@Suite("AltitudeResolver")
struct AltitudeResolverTests {

    @Test("with no barometer, GPS altitude is the altitude — and an invalid fix clears it (#303)")
    func gpsOnly() {
        var resolver = AltitudeResolver()
        resolver.gpsFix(altitude: 280, verticalAccuracy: 6)
        #expect(resolver.altitude == 280)
        #expect(resolver.source == .gps)
        resolver.gpsFix(altitude: nil, verticalAccuracy: nil)
        #expect(resolver.altitude == nil)
    }

    @Test("absolute barometric altitude wins over GPS")
    func absoluteWins() {
        var resolver = AltitudeResolver()
        resolver.gpsFix(altitude: 280, verticalAccuracy: 6)
        resolver.barometer(.absolute(meters: 274.5, accuracy: 2))
        resolver.gpsFix(altitude: 290, verticalAccuracy: 6)
        #expect(resolver.altitude == 274.5)
        #expect(resolver.source == .barometric)
    }

    @Test("relative altitude anchors on a good fix and carries on from it without a step")
    func relativeAnchors() {
        var resolver = AltitudeResolver()
        resolver.barometer(.relative(meters: 0))
        // Too poor to anchor on: GPS stands in.
        resolver.gpsFix(altitude: 300, verticalAccuracy: 25)
        #expect(resolver.altitude == 300)
        #expect(resolver.source == .gps)

        resolver.barometer(.relative(meters: 1.5))
        resolver.gpsFix(altitude: 280, verticalAccuracy: 5)
        #expect(resolver.altitude == 280)
        #expect(resolver.source == .barometric)

        resolver.barometer(.relative(meters: 4))
        #expect(resolver.altitude == 282.5)
        // Anchored: later fixes don't move it.
        resolver.gpsFix(altitude: 270, verticalAccuracy: 3)
        #expect(resolver.altitude == 282.5)
    }

    @Test("when the barometer stops, the next GPS fix takes over")
    func fallsBackToGPS() {
        var resolver = AltitudeResolver()
        resolver.barometer(.absolute(meters: 274.5, accuracy: 2))
        resolver.barometerEnded()
        resolver.gpsFix(altitude: 281, verticalAccuracy: 6)
        #expect(resolver.altitude == 281)
        #expect(resolver.source == .gps)
    }
}
