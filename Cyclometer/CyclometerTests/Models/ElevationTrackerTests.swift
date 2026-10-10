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
    func seedAdds() {
        var tracker = tracker([100, 110])
        tracker.seed(ElevationTracker.Seed(ascentMeters: 170, descentMeters: 20, highestMeters: 200, lowestMeters: 50))
        #expect(tracker.ascentMeters == 170 + 10)
        #expect(tracker.descentMeters == 20)
        #expect(tracker.highestMeters == 200)
        #expect(tracker.lowestMeters == 50)
    }

    // MARK: Breaks in the profile (#387 review)

    @Test("the step between two sources' altitudes isn't climbing")
    func sourceChangeIsNotClimbing() {
        var tracker = tracker([280, 280.5], source: .gps)
        // Core Motion settles 5.5 m below GPS's idea of the same spot.
        tracker.record(altitude: 274.5, distanceMeters: 20, source: .barometric)
        tracker.record(altitude: 274.6, distanceMeters: 30, source: .barometric)
        #expect(tracker.ascentMeters == 0)
        #expect(tracker.descentMeters == 0)
        // Nor a grade across the step: the window starts afresh on the new source.
        #expect(tracker.steepestDescentPercent == nil)
    }

    @Test("stopped, the altitude's drift banks nothing, and riding on carries on from there")
    func stopIsNotClimbing() throws {
        var tracker = tracker((0...10).map { Double($0) * 0.6 })   // +6%, 100 m
        let ascent = tracker.ascentMeters
        // An hour at the café: 4 m of pressure drift at the same distance.
        for minute in 1...4 { tracker.record(altitude: 6 + Double(minute), distanceMeters: 100, source: .barometric) }
        #expect(tracker.ascentMeters == ascent)
        // Riding on from the drifted reading: the climb after it counts, the drift doesn't.
        for step in 1...5 { tracker.record(altitude: 10 + Double(step), distanceMeters: 100 + Double(step) * 10, source: .barometric) }
        #expect(tracker.ascentMeters == ascent + 5)
    }

    @Test("a restart — a pause — banks nothing across it and waits for a fresh grade window")
    func restartBreaksTheProfile() throws {
        var tracker = tracker((0...10).map { Double($0) * 0.3 })   // +3%
        let ascent = tracker.ascentMeters
        tracker.restart()
        // A gondola 300 m up, then a level road.
        tracker.record(altitude: 303, distanceMeters: 110, source: .barometric)
        tracker.record(altitude: 303, distanceMeters: 120, source: .barometric)
        #expect(tracker.ascentMeters == ascent)
        #expect(abs(try #require(tracker.gradePercent) - 3) < 1e-9)
        #expect(abs(try #require(tracker.steepestClimbPercent) - 3) < 1e-9)
    }

    // MARK: Seed

    private static func saved(_ altitudes: [Double?], speedMPS: Double = 6, segmentIndex: Int = 0) -> [TrackPointDTO] {
        altitudes.map { altitude in
            TrackPointDTO(
                rideId: UUID(), timestamp: .now, latitude: 43, longitude: -89, altitudeMeters: altitude,
                horizontalAccuracyMeters: 5, speedMPS: speedMPS, speedSource: .gps, heartRateBPM: nil,
                heartRateSource: .none, cadenceRPM: nil, powerWatts: nil, segmentIndex: segmentIndex
            )
        }
    }

    @Test("the seed counts the saved track on the floor of the source it's given")
    func seedFloorFollowsSource() throws {
        let rollers = Self.saved((0..<10).map { 100 + ($0.isMultiple(of: 2) ? 0.0 : 2.0) })
        #expect(try #require(ElevationTracker.Seed(savedTrack: rollers, source: .barometric)).ascentMeters == 10)
        #expect(try #require(ElevationTracker.Seed(savedTrack: rollers, source: .gps)).ascentMeters == 0)
    }

    @Test("the seed replays the live rule: a stop and a pause bank nothing")
    func seedReplaysBreaks() throws {
        let track = Self.saved([100, 101])
            + Self.saved([104], speedMPS: 0)                    // drift while stopped
            + Self.saved([105, 106])
            + Self.saved([400, 401], segmentIndex: 1)           // resumed 300 m up
        let seed = try #require(ElevationTracker.Seed(savedTrack: track, source: .barometric))
        // 100→101, then 104→106 after the stop, then 400→401 after the pause.
        #expect(seed.ascentMeters == 1 + 2 + 1)
        #expect(seed.descentMeters == 0)
        #expect(seed.highestMeters == 401)
        #expect(seed.lowestMeters == 100)
    }

    @Test("a saved track with no altitude seeds nothing")
    func emptySeed() {
        #expect(ElevationTracker.Seed(savedTrack: [], source: .barometric) == nil)
        #expect(ElevationTracker.Seed(savedTrack: Self.saved([nil, nil]), source: .barometric) == nil)
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

    @Test("absolute altitude waits until Core Motion is sure of it, then stays")
    func absoluteWaitsForAccuracy() {
        var resolver = AltitudeResolver()
        resolver.gpsFix(altitude: 280, verticalAccuracy: 6)
        // Pressure alone: tens of metres out.
        resolver.barometer(.absolute(meters: 240, accuracy: 40))
        #expect(resolver.altitude == 280)
        #expect(resolver.source == .gps)

        resolver.barometer(.absolute(meters: 276, accuracy: 4))
        #expect(resolver.altitude == 276)
        #expect(resolver.source == .barometric)
        // Trusted once, it stays the source.
        resolver.barometer(.absolute(meters: 277, accuracy: 12))
        resolver.gpsFix(altitude: 290, verticalAccuracy: 6)
        #expect(resolver.altitude == 277)
    }

    @Test("when the barometer stops there's no altitude until GPS gives one — not its last reading")
    func endedBarometerLeavesNoAltitude() {
        var resolver = AltitudeResolver()
        resolver.barometer(.absolute(meters: 274.5, accuracy: 2))
        resolver.barometerEnded()
        #expect(resolver.altitude == nil)
        #expect(resolver.source == .gps)
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
