import Foundation
import Testing
@testable import Cyclometer

/// #547: S15's per-mile and per-km splits, replayed on moving time from the saved track.
@Suite("Pace splits")
struct RidePaceSplitsTests {

    private static let start = Date(timeIntervalSince1970: 1_750_000_000)
    private static let tolerance = 1e-9

    /// One point a second, as the tick records them.
    private static func track(_ speeds: [Double?]) -> [TrackPointDTO] {
        speeds.enumerated().map { second, mps in
            TrackPointDTO(
                rideId: UUID(), timestamp: start.addingTimeInterval(Double(second)),
                latitude: 45, longitude: -93, altitudeMeters: nil, horizontalAccuracyMeters: 5,
                speedMPS: mps, speedSource: .gps, heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil
            )
        }
    }

    @Test("constant speed gives equal whole splits")
    func constantSpeed() {
        // 10 m/s for 350 s: 3 whole 1000 m splits of 100 s, and 500 m left.
        let splits = PaceSplits.splits(Self.track(Array(repeating: 10, count: 350)), metersPerSplit: 1_000)
        #expect(splits.count == 4)
        for (offset, split) in splits.prefix(3).enumerated() {
            #expect(split.index == offset + 1)
            #expect(!split.isPartial)
            #expect(abs(split.movingSeconds - 100) < Self.tolerance)
        }
    }

    @Test("a second that crosses a boundary is shared between the two splits")
    func boundaryMidSecond() {
        // 3 m/s: 1000 m falls a third of the way through second 334.
        let splits = PaceSplits.splits(Self.track(Array(repeating: 3, count: 400)), metersPerSplit: 1_000)
        #expect(abs(splits[0].movingSeconds - 1_000.0 / 3) < Self.tolerance)
        #expect(abs(splits[1].movingSeconds - (400 - 1_000.0 / 3)) < Self.tolerance)
        #expect(abs(splits[1].meters - 200) < Self.tolerance)
    }

    @Test("stopped seconds and seconds with no speed add no time: splits are on moving time")
    func movingTimeOnly() {
        let stopped = Array(repeating: Double?.some(0.3), count: 60) + Array(repeating: nil, count: 20)
        let speeds: [Double?] = Array(repeating: 10, count: 50) + stopped + Array(repeating: 10, count: 60)
        let splits = PaceSplits.splits(Self.track(speeds), metersPerSplit: 1_000)
        #expect(abs(splits[0].movingSeconds - 100) < Self.tolerance)
        #expect(abs(splits[1].movingSeconds - 10) < Self.tolerance)
    }

    @Test("the partial last split keeps its distance, and its pace is scaled to a whole unit")
    func partialLastSplit() throws {
        let splits = PaceSplits.splits(Self.track(Array(repeating: 10, count: 140)), metersPerSplit: 1_000)
        let last = try #require(splits.last)
        #expect(last.isPartial)
        #expect(abs(last.meters - 400) < Self.tolerance)
        #expect(last.label(.metric) == "0.4")
        // 400 m in 40 s is 10 m/s, the whole splits' pace.
        #expect(last.pace(.metric) == splits[0].pace(.metric))
        #expect(splits[0].label(.metric) == "1")
        #expect(splits[0].spokenLabel(.metric) == "Kilometer 1")
        #expect(splits[0].spokenLabel(.imperial) == "Mile 1")
    }

    @Test("a leftover that would read 0.0 is not a split")
    func tinyLeftoverDropped() {
        // 1000 m and then 40 m: 0.04 km.
        let splits = PaceSplits.splits(Self.track(Array(repeating: 10, count: 104)), metersPerSplit: 1_000)
        #expect(splits.count == 1)
        #expect(!splits[0].isPartial)
    }

    @Test("a ride shorter than one whole split has no splits")
    func underOneSplit() {
        #expect(PaceSplits.splits(Self.track(Array(repeating: 10, count: 99)), metersPerSplit: 1_000).isEmpty)
        #expect(PaceSplits.splits([], metersPerSplit: 1_000).isEmpty)
    }

    @Test("miles and kilometres split the same ride differently")
    func unitsDiffer() {
        // 10 km at 8 m/s.
        let points = Self.track(Array(repeating: 8, count: 1_250))
        let km = PaceSplits.splits(points, metersPerSplit: PaceSplits.metersPerSplit(.metric))
        let miles = PaceSplits.splits(points, metersPerSplit: PaceSplits.metersPerSplit(.imperial))
        #expect(km.count == 10)
        #expect(km.allSatisfy { !$0.isPartial })
        #expect(miles.count == 7)  // 6 whole miles and 0.21 mi
        #expect(miles.last?.label(.imperial) == "0.2")
        #expect(abs(PaceSplits.metersPerSplit(.imperial) - 1_609.344) < 1e-6)
    }

    @Test("the splits add up to the replayed distance and moving time, so they average to the Average pace")
    func splitsSumToTheRide() throws {
        let speeds: [Double?] = (0..<3_000).map { second in
            (900..<960).contains(second) ? 0 : 6 + 3 * sin(Double(second) / 70)
        }
        let points = Self.track(speeds)
        let moving = speeds.compactMap { $0 }.filter { $0 > ActiveRideFeature.stationarySpeedMPS }
        let splits = PaceSplits.splits(points, metersPerSplit: PaceSplits.metersPerSplit(.imperial))
        #expect(try #require(splits.last).isPartial)
        #expect(abs(splits.map(\.meters).reduce(0, +) - moving.reduce(0, +)) < 1e-6)
        #expect(abs(splits.map(\.movingSeconds).reduce(0, +) - Double(moving.count)) < 1e-6)
    }
}
