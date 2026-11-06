import Foundation
import SwiftUI
import Testing
@testable import Cyclometer

/// #537 — the map sheet's track, stops and route coloring, as arithmetic.
enum RideMapFixtures {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)
    /// Degrees of latitude per 10 m, so points heading north are 10 m apart.
    static let tenMeters = 10 / 111_195.0

    /// One point a second heading north, 10 m apart, each reading from its closure.
    static func points(
        count: Int,
        from first: Int = 0,
        segment: Int = 0,
        secondsOffset: TimeInterval = 0,
        altitude: (Int) -> Double? = { _ in nil },
        speed: (Int) -> Double? = { _ in 6 },
        heartRate: (Int) -> Int? = { _ in nil },
        cadence: (Int) -> Int? = { _ in nil }
    ) -> [TrackPointDTO] {
        (first..<(first + count)).map { index in
            TrackPointDTO(
                rideId: UUID(), timestamp: start.addingTimeInterval(Double(index) + secondsOffset),
                latitude: 45 + Double(index) * tenMeters, longitude: -93,
                altitudeMeters: altitude(index), horizontalAccuracyMeters: 5,
                speedMPS: speed(index), speedSource: .gps,
                heartRateBPM: heartRate(index), heartRateSource: heartRate(index) == nil ? .none : .bleHR,
                cadenceRPM: cadence(index), segmentIndex: segment
            )
        }
    }
}

@Suite("RideMapTrack grades")
struct RideMapTrackGradeTests {
    @Test("a steady climb reads its grade, and the descent after it reads negative")
    func climbAndDescent() throws {
        // 300 m at 5% up, then 300 m at 5% down.
        let points = RideMapFixtures.points(count: 61, altitude: { $0 <= 30 ? 100 + Double($0) * 0.5 : 115 - Double($0 - 30) * 0.5 })
        let grades = try #require(RideMapTrack(points: points).segments.first?.map(\.gradePercent))
        #expect(abs(try #require(grades[10]) - 5) < 0.1)
        #expect(abs(try #require(grades[50]) + 5) < 0.1)
    }

    /// The altitude moved while paused (a lift, the weather), and nobody rode it.
    @Test("a grade never spans a pause")
    func gradeStaysInsideItsStretch() {
        let before = RideMapFixtures.points(count: 30, segment: 0, altitude: { _ in 100 })
        let after = RideMapFixtures.points(count: 30, from: 30, segment: 1, altitude: { _ in 200 })
        let track = RideMapTrack(points: before + after)
        #expect(track.segments.count == 2)
        for grade in track.points.map(\.gradePercent) {
            #expect(abs(grade ?? .infinity) < 0.01)
        }
    }

    @Test("no grade without altitude, on a stretch shorter than the window, or where it's steeper than road")
    func gradeIsAbsentWithoutABelievableReading() {
        #expect(!RideMapTrack(points: RideMapFixtures.points(count: 30)).hasGrade)
        #expect(!RideMapTrack(points: RideMapFixtures.points(count: 5, altitude: { _ in 100 })).hasGrade)
        // 40% — the barometer jumping, not a road.
        #expect(!RideMapTrack(points: RideMapFixtures.points(count: 30, altitude: { Double($0) * 4 })).hasGrade)
    }

    @Test("each metric is offered only when the ride recorded it")
    func availability() {
        let bare = RideMapTrack(points: RideMapFixtures.points(count: 30))
        #expect(bare.hasSpeed && !bare.hasGrade && !bare.hasHeartRate && !bare.hasCadence)
        let coasting = RideMapTrack(points: RideMapFixtures.points(count: 30, cadence: { _ in 0 }))
        #expect(!coasting.hasCadence, "0 rpm the whole way is a sensor that saw no pedalling")
        let full = RideMapTrack(points: RideMapFixtures.points(count: 30, altitude: { _ in 100 },
                                                               heartRate: { _ in 140 }, cadence: { _ in 88 }))
        #expect(full.hasGrade && full.hasHeartRate && full.hasCadence)
    }
}

@Suite("RideStops")
struct RideStopsTests {
    private let track = RideMapTrack(points:
        RideMapFixtures.points(count: 100, segment: 0)
        + RideMapFixtures.points(count: 100, from: 100, segment: 1, secondsOffset: 120)
        + RideMapFixtures.points(count: 100, from: 200, segment: 2, secondsOffset: 165)
    )

    @Test("a manual and an auto pause each mark where the rider stopped, and for how long")
    func pausesBecomeStops() {
        let start = RideMapFixtures.start
        let stops = RideStops.stops(pauses: [
            RidePause(startedAt: start.addingTimeInterval(100), endedAt: start.addingTimeInterval(220), isAuto: false),
            RidePause(startedAt: start.addingTimeInterval(320), endedAt: start.addingTimeInterval(365), isAuto: true),
        ], track: track)

        #expect(stops.map(\.isAuto) == [false, true])
        #expect(stops.map(\.duration) == [120, 45])
        // The last point before each pause: the 100th, then the 200th.
        #expect(stops.map(\.coordinate) == [track.segments[0].last?.coordinate, track.segments[1].last?.coordinate])
        #expect(stops.map(\.title) == ["Pause · 2 min", "Auto-pause · 45 sec"])
    }

    @Test("the pause a ride ends in, and one before any point, are not stops")
    func openAndPointlessPausesAreLeftOut() {
        let start = RideMapFixtures.start
        #expect(RideStops.stops(pauses: [
            RidePause(startedAt: start.addingTimeInterval(-60), endedAt: start.addingTimeInterval(-10), isAuto: false),
            RidePause(startedAt: start.addingTimeInterval(500), endedAt: nil, isAuto: false),
        ], track: track).isEmpty)
    }

    /// A tunnel leaves a gap in the track but no pause, and draws no stop.
    @Test("a gap in the track with no pause is not a stop")
    func gapsAreNotStops() {
        #expect(RideStops.stops(pauses: [], track: track).isEmpty)
    }
}

@Suite("RouteColorScale")
struct RouteColorScaleTests {
    private let zones = [60...123, 124...143, 144...162, 163...181, 182...200]

    // MARK: Bands

    @Test("speed splits the ride's own 5th–95th percentile span in five, clamped at each end")
    func speedBands() throws {
        let points = RideMapFixtures.points(count: 100, speed: { Double($0 + 1) })
            + RideMapFixtures.points(count: 10, from: 100, speed: { _ in 0.2 })
        let span = try #require(RouteColorScale.speedSpan(RideMapTrack(points: points)))
        #expect(span == 6...95, "stopped seconds aren't speeds the ride was ridden at")

        #expect(RouteColorScale.speedBand(2, span: span) == 1)
        #expect(RouteColorScale.speedBand(6, span: span) == 1)
        #expect(RouteColorScale.speedBand(50, span: span) == 3)
        #expect(RouteColorScale.speedBand(95, span: span) == 5)
        #expect(RouteColorScale.speedBand(300, span: span) == 5)
    }

    @Test("a ride at one speed is all the middle band")
    func oneSpeedIsTheMiddleBand() {
        #expect(RouteColorScale.speedBand(7, span: 7...7) == 3)
    }

    @Test("grade uses the map's grade bands, and a descent is flat")
    func gradeBands() {
        #expect([-8, 0, 2.9, 3, 5.9, 6, 9, 11.9, 12, 20].map(RouteColorScale.gradeBand) == [1, 1, 1, 2, 2, 3, 4, 4, 5, 5])
    }

    @Test("heart rate falls in the rider's zones, below zone 1 as zone 1 and above zone 5 as zone 5")
    func heartRateBands() {
        #expect([40, 60, 123, 124, 150, 181, 182, 220].map { RouteColorScale.heartRateBand($0, zones: zones) }
                == [1, 1, 1, 2, 3, 4, 5, 5])
    }

    @Test("cadence falls in the rider's zones, and no reading or 0 rpm is neutral")
    func cadenceBands() {
        let track = RideMapTrack(segments: [])
        let scale = RouteColorScale(coloring: .cadence, track: track, heartRateZones: zones, cadenceZones: .default)
        func point(_ rpm: Int?) -> RideMapTrack.Point {
            RideMapTrack.Point(coordinate: RouteCoordinate(latitude: 45, longitude: -93), timestamp: .now, cadenceRPM: rpm)
        }
        #expect(scale.band(point(nil)) == nil)
        #expect(scale.band(point(0)) == nil)
        #expect(scale.band(point(65)) == 1)
        #expect(scale.band(point(88)) == 3)
        #expect(scale.band(point(120)) == 5)
    }

    @Test("speed and grade draw on the map's grade ramp, heart rate and cadence on the zone colors")
    func colors() {
        #expect(RouteColoring.speed.color(band: 2) == .cyMapGrade2)
        #expect(RouteColoring.grade.color(band: 5) == .cyMapGrade5)
        #expect(RouteColoring.heartRate.color(band: 4) == .hrZone(4))
        #expect(RouteColoring.cadence.color(band: 1) == .hrZone(1))
        #expect(RouteColoring.heartRate.color(band: nil) == .cyTextTertiary)
    }

    // MARK: Runs

    private func runs(_ points: [TrackPointDTO]) -> [ColoredRun] {
        let track = RideMapTrack(points: points)
        return RouteColorScale(coloring: .heartRate, track: track, heartRateZones: zones, cadenceZones: .default).runs(track)
    }

    @Test("neighbouring points in a band draw as one run, and runs meet at a shared point")
    func runsShareTheirEnds() {
        // 200 m in zone 1, 200 m in zone 3.
        let colored = runs(RideMapFixtures.points(count: 40, heartRate: { $0 < 20 ? 100 : 150 }))
        #expect(colored.map(\.band) == [1, 3])
        #expect(colored[0].coordinates.last == colored[1].coordinates.first)
        #expect(colored[0].coordinates.count == 21)
        #expect(colored[1].coordinates.count == 20)
    }

    @Test("a flicker shorter than the minimum run folds into the run before it")
    func shortRunsFold() {
        // 20 m of zone 3 in the middle of zone 1.
        let colored = runs(RideMapFixtures.points(count: 40, heartRate: { (20..<22).contains($0) ? 150 : 100 }))
        #expect(colored.map(\.band) == [1])
        #expect(colored[0].coordinates.count == 40)
    }

    @Test("a short first run folds into the run after it")
    func shortFirstRunFoldsForward() {
        let colored = runs(RideMapFixtures.points(count: 40, heartRate: { $0 < 2 ? 150 : 100 }))
        #expect(colored.map(\.band) == [1])
        #expect(colored[0].coordinates.count == 40)
    }

    @Test("runs never join across a pause, even in the same band")
    func runsStopAtAPause() {
        let colored = runs(RideMapFixtures.points(count: 20, segment: 0, heartRate: { _ in 100 })
                           + RideMapFixtures.points(count: 20, from: 20, segment: 1, heartRate: { _ in 100 }))
        #expect(colored.map(\.band) == [1, 1])
        #expect(colored[0].coordinates.last != colored[1].coordinates.first)
    }

    @Test("a stretch with no reading draws neutral rather than borrowing a band")
    func missingReadingsAreNeutral() {
        let colored = runs(RideMapFixtures.points(count: 40, heartRate: { $0 < 20 ? 100 : nil }))
        #expect(colored.map(\.band) == [1, nil])
    }

    // MARK: Legend

    @Test("grade's legend is the map's bands, under 3% to 12% and over")
    func gradeLegend() {
        let scale = RouteColorScale(coloring: .grade, track: RideMapTrack(segments: []), heartRateZones: zones, cadenceZones: .default)
        #expect(scale.legend(.metric).map(\.label) == ["<3", "3–6", "6–9", "9–12", "12+"])
        #expect(scale.legend(.metric).first?.spoken == "under 3 percent")
        #expect(scale.legend(.metric).last?.spoken == "12 percent and over")
        #expect(scale.legendUnit(.metric) == "%")
    }

    @Test("speed's legend is the ride's own bands, in the rider's units")
    func speedLegend() throws {
        // 5–10 m/s: 18–36 km/h, 11.2–22.4 mph.
        let points = RideMapFixtures.points(count: 101, speed: { 5 + Double($0) * 0.05 })
        let track = RideMapTrack(points: points)
        let scale = RouteColorScale(coloring: .speed, track: track, heartRateZones: zones, cadenceZones: .default)
        let span = try #require(scale.speedSpan)
        #expect(abs(span.lowerBound - 5.25) < 1e-9 && abs(span.upperBound - 9.75) < 1e-9)

        #expect(scale.legend(.metric).map(\.label) == ["<22", "22–25", "25–29", "29–32", "32+"])
        #expect(scale.legend(.imperial).map(\.label) == ["<14", "14–16", "16–18", "18–20", "20+"])
        #expect(scale.legendUnit(.imperial) == UnitSystem.imperial.speedLabel)
        #expect(scale.legend(.imperial).first?.spoken == "under \(UnitSystem.imperial.spokenSpeed(fromMPS: 6.15, fractionLength: 0))")
    }

    @Test("heart rate's and cadence's legends are the rider's zones")
    func zoneLegends() {
        let track = RideMapTrack(segments: [])
        let heartRate = RouteColorScale(coloring: .heartRate, track: track, heartRateZones: zones, cadenceZones: .default)
        #expect(heartRate.legend(.metric).map(\.label) == ["60–123", "124–143", "144–162", "163–181", "182–200"])
        #expect(heartRate.legend(.metric)[2].spoken == "Zone 3, 144 to 162 beats per minute")

        let cadence = RouteColorScale(coloring: .cadence, track: track, heartRateZones: zones, cadenceZones: .default)
        #expect(cadence.legend(.metric).map(\.label) == ["<70", "70–85", "85–95", "95–110", "110+"])
        #expect(cadence.legend(.metric)[0].spoken == "Zone 1, under 70 r p m")
        #expect(cadence.legendUnit(.metric) == "rpm")
    }

    @Test("Plain has no legend")
    func plainHasNoLegend() {
        let scale = RouteColorScale(coloring: .plain, track: RideMapTrack(segments: []), heartRateZones: zones, cadenceZones: .default)
        #expect(scale.legend(.metric).isEmpty)
    }
}
