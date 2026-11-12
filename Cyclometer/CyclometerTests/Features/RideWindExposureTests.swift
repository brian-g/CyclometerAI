import Foundation
import Testing
@testable import Cyclometer

/// #151 — how the recorded wind met the rider: the direction of travel from the track, set against
/// the sample in effect, as shares of moving time.
@Suite("RideWindExposure")
struct RideWindExposureTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)
    private static let origin = RouteCoordinate(latitude: 45, longitude: -93)

    /// One point a second at `speed`, travelling `bearings[i]` for second `i`, each `segments[i]`
    /// (default one segment), starting from `from`.
    private static func track(
        _ bearings: [Double],
        speed: Double = 6,
        segments: [Int]? = nil,
        jumps: [Int: (north: Double, east: Double)] = [:],
        from: RouteCoordinate = origin
    ) -> [TrackPointDTO] {
        var position = from
        return bearings.enumerated().map { second, bearing in
            if second > 0 {
                let radians = bearing * .pi / 180
                position = RouteGeometry.coordinate(offsetFrom: position,
                                                    north: speed * cos(radians), east: speed * sin(radians))
            }
            if let jump = jumps[second] {
                position = RouteGeometry.coordinate(offsetFrom: position, north: jump.north, east: jump.east)
            }
            return TrackPointDTO(
                rideId: UUID(), timestamp: start.addingTimeInterval(Double(second)),
                latitude: position.latitude, longitude: position.longitude,
                horizontalAccuracyMeters: 5, speedMPS: speed, speedSource: .gps,
                heartRateSource: .none, segmentIndex: segments?[second] ?? 0
            )
        }
    }

    private static func sample(at second: Double = 0, from degrees: Double, mps: Double = 4) -> RideWeatherSample {
        RideWeatherSample(date: start.addingTimeInterval(second), temperatureCelsius: 15, humidity: 0.6,
                          windSpeedMPS: mps, windFromDegrees: degrees, condition: nil)
    }

    private static func exposure(_ points: [TrackPointDTO], _ samples: [RideWeatherSample]) -> RideWindExposure? {
        RideWindExposure(headings: TimedHeading.movingHeadings(points), samples: samples)
    }

    // MARK: Headings

    @Test("A heading needs a 20 m baseline, so the first few seconds of a stretch have none")
    func headingsNeedABaseline() {
        // 6 m a second: point 4 is the first 24 m from the start.
        let headings = TimedHeading.movingHeadings(Self.track(Array(repeating: 90, count: 10)))
        #expect(headings.count == 6)
        #expect(headings.first?.date == Self.start.addingTimeInterval(4))
        #expect(headings.allSatisfy { abs($0.degrees - 90) < 0.5 })
    }

    @Test("A point at a standstill has no heading: it isn't a moving second")
    func stationaryPointsHaveNone() {
        let points = Self.track(Array(repeating: 0, count: 10)).enumerated().map { index, point in
            var point = point
            if index == 8 { point.speedMPS = 0 }
            return point
        }
        #expect(TimedHeading.movingHeadings(points).count == 5)
    }

    /// Resumed 500 m west of where the pause began: a bearing across the gap would be west, a
    /// crosswind in a northerly, though the rider rode north throughout.
    @Test("A bearing never spans a pause")
    func bearingsStayInTheirSegment() {
        let points = Self.track(Array(repeating: 0, count: 40),
                                segments: (0..<40).map { $0 < 20 ? 0 : 1 },
                                jumps: [20: (north: 0, east: -500)])
        let headings = TimedHeading.movingHeadings(points)
        #expect(headings.allSatisfy { $0.degrees < 0.5 || $0.degrees > 359.5 })
        // Each stretch loses its first four seconds to the baseline.
        #expect(headings.count == 32)
        #expect(Self.exposure(points, [Self.sample(from: 0)]) == .shares(headwind: 100, crosswind: 0, tailwind: 0))
    }

    // MARK: Shares

    @Test("Riding east into an easterly is all headwind; with a westerly, all tailwind")
    func directionDecidesTheShare() {
        let east = Self.track(Array(repeating: 90, count: 60))
        #expect(Self.exposure(east, [Self.sample(from: 90)]) == .shares(headwind: 100, crosswind: 0, tailwind: 0))
        #expect(Self.exposure(east, [Self.sample(from: 270)]) == .shares(headwind: 0, crosswind: 0, tailwind: 100))
        #expect(Self.exposure(east, [Self.sample(from: 0)]) == .shares(headwind: 0, crosswind: 100, tailwind: 0))
    }

    @Test("Out and back in a steady wind is half into it and half with it")
    func outAndBack() {
        let points = Self.track(Array(repeating: 90, count: 100) + Array(repeating: 270, count: 100))
        guard case let .shares(head, cross, tail) = Self.exposure(points, [Self.sample(from: 90)]) else {
            Issue.record("expected shares")
            return
        }
        // The turn costs a few seconds of crosswind while the 20 m baseline swings round.
        #expect(cross <= 3)
        #expect(abs(head - tail) <= 2)
        #expect(head + cross + tail == 100)
    }

    @Test("Each second takes the latest sample at or before it")
    func samplesTakeEffectInTurn() {
        let points = Self.track(Array(repeating: 0, count: 104))
        // Headings from second 4 to 103: 50 under the northerly, 50 under the easterly.
        let samples = [Self.sample(at: 0, from: 0), Self.sample(at: 54, from: 90)]
        #expect(Self.exposure(points, samples) == .shares(headwind: 50, crosswind: 50, tailwind: 0))
        // Order of storage doesn't matter.
        #expect(Self.exposure(points, samples.reversed()) == .shares(headwind: 50, crosswind: 50, tailwind: 0))
    }

    @Test("Seconds before the first sample take the first: it arrives a fix or two in")
    func beforeTheFirstSample() {
        let points = Self.track(Array(repeating: 0, count: 60))
        #expect(Self.exposure(points, [Self.sample(at: 45, from: 180)]) == .shares(headwind: 0, crosswind: 0, tailwind: 100))
    }

    @Test("Seconds under a calm sample don't count; all calm is Calm")
    func calm() {
        let points = Self.track(Array(repeating: 0, count: 104))
        #expect(Self.exposure(points, [Self.sample(from: 0, mps: 0.3)]) == .calm)
        let mixed = [Self.sample(at: 0, from: 0, mps: 0.3), Self.sample(at: 54, from: 0)]
        #expect(Self.exposure(points, mixed) == .shares(headwind: 100, crosswind: 0, tailwind: 0))
    }

    @Test("No samples, or no moving track, is no wind")
    func nothingToSetAgainst() {
        #expect(Self.exposure(Self.track(Array(repeating: 0, count: 60)), []) == nil)
        #expect(Self.exposure([], [Self.sample(from: 0)]) == nil)
        #expect(Self.exposure(Self.track(Array(repeating: 0, count: 60), speed: 0), [Self.sample(from: 0)]) == nil)
    }

    @Test("Shares round to whole percents that always add up to 100")
    func wholePercents() {
        #expect(RideWindExposure.wholePercents([1, 1, 1]) == [34, 33, 33])
        #expect(RideWindExposure.wholePercents([2, 1, 0]) == [67, 33, 0])
        #expect(RideWindExposure.wholePercents([1, 2, 3]) == [17, 33, 50])
        #expect(RideWindExposure.wholePercents([0, 0, 7]) == [0, 0, 100])
    }
}
