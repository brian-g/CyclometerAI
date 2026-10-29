import Foundation
import Testing
@testable import Cyclometer

@Suite("CalorieSeries")
struct CalorieSeriesTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let rider = RideEnergy.Rider(kilograms: 75)
    private static let speed = 25 / 3.6

    /// One point a second for `seconds` seconds from `start`, riding due north at `speed`.
    private func track(seconds: Int, startingAt start: Date = start, segmentIndex: Int = 0) -> [TrackPointDTO] {
        (0..<seconds).map { second in
            TrackPointDTO(
                rideId: UUID(),
                timestamp: start.addingTimeInterval(Double(second)),
                latitude: 43 + Self.speed * Double(second) / 111_000,
                longitude: -89,
                altitudeMeters: 100,
                horizontalAccuracyMeters: 5,
                speedMPS: Self.speed,
                speedSource: .gps,
                heartRateBPM: nil,
                heartRateSource: .none,
                cadenceRPM: nil,
                powerWatts: nil,
                segmentIndex: segmentIndex
            )
        }
    }

    @Test("a pause adds nothing to recording time: the second segment carries on from the first")
    func offsetsSkipPauses() {
        let first = track(seconds: 3)
        let second = track(seconds: 2, startingAt: Self.start.addingTimeInterval(600), segmentIndex: 1)
        #expect(CalorieSeries.recordingOffsets(first + second) == [0, 1, 2, 3, 4])
    }

    @Test("a dropout inside a segment is recording time")
    func offsetsKeepDropouts() {
        var points = track(seconds: 4)
        points.remove(at: 2)
        #expect(CalorieSeries.recordingOffsets(points) == [0, 1, 3])
    }

    @Test("one point per whole minute, each the estimate over the track by then")
    func onePointPerMinute() {
        let points = track(seconds: 150)
        let series = CalorieSeries.rebuild(track: points, through: 150, rider: Self.rider)
        #expect(series.map(\.rideSeconds) == [60, 120])
        let firstMinute = RideEnergy.activeKilocalories(
            trackPoints: Array(points.prefix(60)), movingSeconds: 60,
            distanceMeters: 60 * Self.speed, rider: Self.rider
        )
        #expect(series.first?.kilocalories == firstMinute.kilocalories)
        #expect(series.first?.method == .physics)
        #expect(series[1].kilocalories > series[0].kilocalories)
    }

    @Test("a minute that ends at the track's end is the estimate the ride's workout would get")
    func lastMinuteIsTheWholeTrack() {
        let points = track(seconds: 180)
        let whole = RideEnergy.activeKilocalories(
            trackPoints: points, movingSeconds: 180, distanceMeters: 180 * Self.speed, rider: Self.rider
        )
        #expect(CalorieSeries.rebuild(track: points, through: 180, rider: Self.rider).last?.kilocalories == whole.kilocalories)
    }

    @Test("minutes the track doesn't reach take the whole track, as at finish")
    func pastTheTrack() {
        let points = track(seconds: 60)
        let series = CalorieSeries.rebuild(track: points, through: 120, rider: Self.rider)
        // Summed as the odometer sums it, a second at a time: here the distance prices the minute
        // the track misses, so `60 * speed` would differ in the last bits.
        let distance = points.reduce(0) { $0 + ($1.speedMPS ?? 0) }
        let whole = RideEnergy.activeKilocalories(
            trackPoints: points, movingSeconds: 120, distanceMeters: distance, rider: Self.rider
        )
        #expect(series.last?.kilocalories == whole.kilocalories)
    }

    @Test("no points before the first whole minute")
    func emptyBeforeAMinute() {
        #expect(CalorieSeries.rebuild(track: track(seconds: 59), through: 59, rider: Self.rider).isEmpty)
        #expect(CalorieSeries.rebuild(track: [], through: 0, rider: Self.rider).isEmpty)
    }

    @Test("the rider is built from Health's values, and not at all without a body mass")
    func riderFromHealth() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15
        let birth = DateComponents(year: 1980, month: 6, day: 1)
        #expect(RideEnergy.Rider(kilograms: 70, dateOfBirth: birth, sex: .female, on: date)
                == RideEnergy.Rider(kilograms: 70, age: 46, sex: .female))
        #expect(RideEnergy.Rider(kilograms: nil, dateOfBirth: birth, sex: .male, on: date) == nil)
    }

    @Test("the average burn is over moving time, and absent before any")
    func averagePerHour() {
        #expect(CalorieSeries.kilocaloriesPerHour(300, movingSeconds: 1_800) == 600)
        #expect(CalorieSeries.kilocaloriesPerHour(0, movingSeconds: 0) == nil)
    }
}
